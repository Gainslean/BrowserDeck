import AppKit
import Foundation

/// Tracks which profiles have a Chrome running, how much they use, and which are frozen.
/// Launch / stop / freeze actions live in ProfileControl.swift.
@MainActor
final class ChromeLauncher: ObservableObject {
    @Published internal(set) var running: [UUID: pid_t] = [:]
    @Published private(set) var usage: [UUID: ProfileUsage] = [:]
    /// Profiles paused with SIGSTOP. Kept here (not derived from sampling) so it is
    /// always current, even while the BrowserDeck window is hidden.
    @Published internal(set) var frozen: Set<UUID> = []
    @Published var lastError: String?

    let chromeApp: URL?
    let chromeVersion: String

    internal weak var store: ProfileStore?
    internal var processes: [UUID: Process] = [:]
    private var timer: Timer?
    private var lastCPU: [UUID: UInt64] = [:]
    private var lastSample: Date?

    /// Name labels on top of each open Chrome window.
    let badges = WindowBadges()
    /// Pauses profiles nobody has used for a while.
    private(set) lazy var autoFreezer = AutoFreezer(launcher: self)

    init() {
        chromeApp = Self.locateChrome()
        let info = chromeApp.flatMap { Bundle(url: $0)?.infoDictionary }
        chromeVersion = info?["CFBundleShortVersionString"] as? String ?? "?"
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Never leave a Chrome paused behind us: it could not be closed normally.
            MainActor.assumeIsolated { self?.unfreezeAll() }
        }
    }

    /// Major version used to build user agents that match the real engine.
    var chromeMajor: String {
        let m = chromeVersion.split(separator: ".").first.map(String.init) ?? ""
        return Int(m) != nil ? m : "157"
    }

    var chromeExecutable: URL? { chromeApp.flatMap { Bundle(url: $0)?.executableURL } }

    static func locateChrome() -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") {
            return url
        }
        let paths = ["/Applications/Google Chrome.app",
                     NSHomeDirectory() + "/Applications/Google Chrome.app",
                     "/Applications/Chromium.app"]
        return paths.map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    func isRunning(_ id: UUID) -> Bool { running[id] != nil }
    func isFrozen(_ id: UUID) -> Bool { frozen.contains(id) }

    var totalMemoryMB: Int { usage.values.reduce(0) { $0 + $1.memoryMB } }

    // MARK: Monitoring

    func startMonitoring(_ store: ProfileStore) {
        self.store = store
        refresh()
        adoptStoppedProfiles()
        sampleUsage()
        autoFreezer.start()
        guard timer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        t.tolerance = 1   // lets macOS batch wake-ups
        timer = t
    }

    /// Nothing to redraw while the window is hidden or covered, so skip the work.
    private var windowVisible: Bool {
        NSApp.windows.contains { $0.isVisible && $0.occlusionState.contains(.visible) }
    }

    private func tick() {
        guard windowVisible else { return }
        refresh()
        sampleUsage()
    }

    /// A Chrome left paused by an earlier run (e.g. after a crash) is shown as frozen,
    /// so it can be resumed or closed properly.
    private func adoptStoppedProfiles() {
        let stopped = ResourceMonitor.snapshot(roots: running).filter { $0.value.stopped }
        frozen.formUnion(stopped.keys)
    }

    func sampleUsage() {
        guard !running.isEmpty else {
            if !usage.isEmpty { usage = [:] }
            lastCPU = [:]
            lastSample = nil
            return
        }
        let snap = ResourceMonitor.snapshot(roots: running)
        let now = Date()
        let dt = lastSample.map { now.timeIntervalSince($0) } ?? 0
        var next: [UUID: ProfileUsage] = [:]
        for (id, s) in snap {
            var cpu = 0.0
            if let prev = lastCPU[id], dt > 0.2, s.cpuTime >= prev {
                cpu = Double(s.cpuTime - prev) / 1e9 / dt * 100
            }
            next[id] = ProfileUsage(memoryMB: Int(s.memory / 1_048_576), cpuPercent: Int(cpu.rounded()),
                                    processes: s.pids.count, frozen: frozen.contains(id))
        }
        lastCPU = snap.mapValues(\.cpuTime)
        lastSample = now
        if next != usage { usage = next }
    }

    func refresh() {
        guard let store else { return }
        var now: [UUID: pid_t] = [:]
        for p in store.profiles {
            if let pid = Self.lockOwner(store.dataDir(for: p.id)) { now[p.id] = pid }
        }
        if now != running { running = now }
        let stillFrozen = frozen.filter { now[$0] != nil }
        if stillFrozen != frozen { frozen = stillFrozen }
        badges.update(running: now, profiles: store.profiles, frozen: frozen)
    }

    /// Chrome marks a user-data-dir in use with a `SingletonLock` symlink that
    /// points at "<hostname>-<pid>". A live pid means the profile is open,
    /// even if it was started before this app.
    static func lockOwner(_ dir: URL) -> pid_t? {
        let path = dir.appendingPathComponent("SingletonLock").path
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path),
              let last = target.split(separator: "-").last,
              let pid = pid_t(last), pid > 0,
              kill(pid, 0) == 0 else { return nil }
        return pid
    }
}
