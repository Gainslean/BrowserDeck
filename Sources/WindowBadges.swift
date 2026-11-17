import AppKit
import SwiftUI

extension BrowserProfile {
    var badgeColor: NSColor {
        NSColor(hue: badgeHue, saturation: 0.55, brightness: 0.82, alpha: 1)
    }

    /// The same colour as Chrome's SkColor (ARGB packed into a signed 32-bit int).
    var themeSkColor: Int {
        let c = badgeColor.usingColorSpace(.sRGB) ?? badgeColor
        func byte(_ v: CGFloat) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        let r = byte(c.redComponent), g = byte(c.greenComponent), b = byte(c.blueComponent)
        return Int(Int32(bitPattern: 0xFF00_0000 | r << 16 | g << 8 | b))
    }
}

/// Floating name labels pinned to the bottom-right corner of every Chrome window
/// opened from BrowserDeck. They ignore clicks and sit just above their window,
/// so other apps' windows still cover them normally.
@MainActor
final class WindowBadges {
    struct Target {
        let name: String
        let color: NSColor
        let frozen: Bool
    }

    var enabled = true {
        didSet { if !enabled { removeAll() }; reschedule() }
    }

    private var targets: [pid_t: Target] = [:]
    private var panels: [CGWindowID: BadgePanel] = [:]
    private var timer: Timer?

    /// Called whenever the set of open profiles or their names may have changed.
    func update(running: [UUID: pid_t], profiles: [BrowserProfile], frozen: Set<UUID>) {
        var next: [pid_t: Target] = [:]
        for p in profiles {
            if let pid = running[p.id] {
                next[pid] = Target(name: p.name, color: p.badgeColor, frozen: frozen.contains(p.id))
            }
        }
        targets = next
        reschedule()
    }

    private func reschedule() {
        let needed = enabled && !targets.isEmpty
        if needed, timer == nil {
            // ~5 checks per second: a label follows a dragged window with a short lag,
            // at well under 1% CPU.
            let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            t.tolerance = 0.05
            RunLoop.main.add(t, forMode: .common)
            timer = t
            tick()
        } else if !needed {
            timer?.invalidate()
            timer = nil
            removeAll()
        }
    }

    private func removeAll() {
        panels.values.forEach { $0.orderOut(nil) }
        panels = [:]
    }

    private func tick() {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let ownPid = ProcessInfo.processInfo.processIdentifier

        // Front-to-back position and owner of every on-screen window.
        var index: [CGWindowID: Int] = [:]
        var owners: [pid_t] = []
        for (i, w) in list.enumerated() {
            if let n = w[kCGWindowNumber as String] as? CGWindowID { index[n] = i }
            owners.append(w[kCGWindowOwnerPID as String] as? pid_t ?? 0)
        }

        var seen = Set<CGWindowID>()
        for w in list {
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t,
                  let target = targets[pid],
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let num = w[kCGWindowNumber as String] as? CGWindowID,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict),
                  rect.width >= 300, rect.height >= 200 else { continue }
            seen.insert(num)

            let panel = panels[num] ?? BadgePanel()
            panels[num] = panel
            panel.show(target)

            let size = panel.frame.size
            let origin = NSPoint(x: rect.maxX - size.width - 14,
                                 y: primaryHeight - rect.maxY + 12)
            if panel.frame.origin != origin { panel.setFrameOrigin(origin) }

            // Re-stack only when another app's window got between label and window.
            var inPlace = false
            if panel.isVisible, panel.windowNumber > 0,
               let a = index[CGWindowID(panel.windowNumber)], let b = index[num], a < b {
                inPlace = !owners[(a + 1)..<b].contains { $0 != pid && $0 != ownPid }
            }
            if !inPlace { panel.order(.above, relativeTo: Int(num)) }
        }

        for (num, panel) in panels where !seen.contains(num) {
            panel.orderOut(nil)
            panels[num] = nil
        }
    }
}

/// Borderless, click-through window holding one label.
final class BadgePanel: NSPanel {
    private var current: (String, NSColor, Bool)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .normal
        collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(_ t: WindowBadges.Target) {
        if let c = current, c.0 == t.name, c.1 == t.color, c.2 == t.frozen { return }
        current = (t.name, t.color, t.frozen)
        let host = NSHostingView(rootView: BadgeLabel(name: t.name, color: Color(nsColor: t.color),
                                                      frozen: t.frozen))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        contentView = host
        setContentSize(size)
    }
}

private struct BadgeLabel: View {
    let name: String
    let color: Color
    let frozen: Bool

    var body: some View {
        HStack(spacing: 6) {
            if frozen {
                Image(systemName: "snowflake").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            } else {
                Circle().fill(.white.opacity(0.9)).frame(width: 7, height: 7)
            }
            Text((name.isEmpty ? "Без имени" : name) + (frozen ? " · заморожен, кликните" : ""))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(frozen ? Color(white: 0.35).opacity(0.92) : color.opacity(0.92)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
        .padding(4)   // room for the shadow
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        .fixedSize()
    }
}
