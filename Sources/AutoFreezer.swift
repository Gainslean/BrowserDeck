import AppKit
import Foundation

/// Freezes a profile's Chrome when nobody has used it for `idleMinutes`, and wakes it
/// as soon as the user clicks its window, switches to it (Cmd+Tab, Dock) or opens it
/// from BrowserDeck.
@MainActor
final class AutoFreezer {
    static let defaultMinutes = 5

    /// 0 turns automatic freezing off.
    var idleMinutes = AutoFreezer.defaultMinutes

    private unowned let launcher: ChromeLauncher
    private var lastActive: [pid_t: Date] = [:]
    private var timer: Timer?
    private var tokens: [NSObjectProtocol] = []
    private var mouseMonitor: Any?

    init(launcher: ChromeLauncher) {
        self.launcher = launcher
    }

    func start() {
        guard timer == nil else { return }
        let wc = NSWorkspace.shared.notificationCenter

        tokens.append(wc.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                     object: nil, queue: .main) { [weak self] note in
            guard let pid = Self.pid(note) else { return }
            MainActor.assumeIsolated { self?.userTouched(pid) }
        })
        // Leaving the front starts the idle countdown from now.
        tokens.append(wc.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification,
                                     object: nil, queue: .main) { [weak self] note in
            guard let pid = Self.pid(note) else { return }
            MainActor.assumeIsolated { self?.markActive(pid) }
        })
        // A paused Chrome would block log out / shut down.
        tokens.append(wc.addObserver(forName: NSWorkspace.willPowerOffNotification,
                                     object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.launcher.unfreezeAll() }
        })

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            let point = NSEvent.mouseLocation
            MainActor.assumeIsolated { self?.clicked(at: point) }
        }

        let t = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func markActive(_ pid: pid_t) { lastActive[pid] = Date() }

    private static func pid(_ note: Notification) -> pid_t? {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
    }

    private func profileID(for pid: pid_t) -> UUID? {
        launcher.running.first { $0.value == pid }?.key
    }

    private func userTouched(_ pid: pid_t) {
        markActive(pid)
        if let id = profileID(for: pid), launcher.isFrozen(id) {
            launcher.setFrozen([id], false)
        }
    }

    /// A click on a frozen profile's window wakes it; the click is delivered right after.
    private func clicked(at point: NSPoint) {
        guard !launcher.frozen.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let p = CGPoint(x: point.x, y: primaryHeight - point.y)
        let own = ProcessInfo.processInfo.processIdentifier

        for w in list {   // front to back
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != own,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: dict), r.contains(p) else { continue }
            if (w[kCGWindowLayer as String] as? Int) == 0 { userTouched(pid) }
            return   // the topmost window under the cursor got the click
        }
    }

    private func check() {
        guard idleMinutes > 0, let store = launcher.store else { return }
        launcher.refresh()
        let now = Date()
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let live = Set(launcher.running.values)
        lastActive = lastActive.filter { live.contains($0.key) }

        var idle: [UUID] = []
        for (id, pid) in launcher.running {
            if pid == front {
                lastActive[pid] = now
                continue
            }
            guard let since = lastActive[pid] else {
                lastActive[pid] = now   // first time seen: start counting now
                continue
            }
            guard !launcher.isFrozen(id), store.profile(id)?.autoFreeze ?? true else { continue }
            if now.timeIntervalSince(since) >= Double(idleMinutes) * 60 { idle.append(id) }
        }
        if !idle.isEmpty { launcher.setFrozen(idle, true) }
    }
}
