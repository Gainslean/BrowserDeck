import AppKit
import Foundation

/// Launch, close, freeze and resume profiles.
extension ChromeLauncher {

    // MARK: Launch

    /// Starts profiles that are closed and brings already open ones to the front.
    func launch(_ profiles: [BrowserProfile], tile: Bool) {
        guard let store else { return }
        guard let exe = chromeExecutable else {
            lastError = "Google Chrome не найден. Установите его в /Applications."
            return
        }
        refresh()
        let open = profiles.filter { isRunning($0.id) }
        if !open.isEmpty { bringToFront(open, exe: exe) }

        updater.reloadVersion()
        let closed = profiles.map(\.id).filter { !isRunning($0) }
        store.syncUserAgents(closed, chromeMajor: chromeMajor)
        let toStart = closed.compactMap(store.profile)
        guard !toStart.isEmpty else { return }
        let frames = tile ? WindowLayout.grid(count: toStart.count) : []

        Task { @MainActor in
            var errors: [String] = []
            for (i, p) in toStart.enumerated() {
                let frame = i < frames.count
                    ? frames[i]
                    : WindowLayout.cascade(index: i, width: p.windowWidth, height: p.windowHeight)
                do {
                    try start(p, exe: exe, dir: store.dataDir(for: p.id), frame: frame)
                } catch {
                    errors.append("\(p.name): \(error.localizedDescription)")
                }
                // Small gap so a large batch doesn't start all at once.
                if toStart.count > 1 { try? await Task.sleep(nanoseconds: 350_000_000) }
            }
            if !errors.isEmpty { lastError = errors.joined(separator: "\n") }
            refresh()
        }
    }

    private func start(_ p: BrowserProfile, exe: URL, dir: URL, frame: CGRect) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let args = try LaunchArguments.build(for: p, dataDir: dir, frame: frame)
        try PreferencesWriter.apply(p, dataDir: dir)

        let proc = Process()
        proc.executableURL = exe
        proc.arguments = args
        var env = ProcessInfo.processInfo.environment
        let tz = p.timezone.trimmed
        if !tz.isEmpty { env["TZ"] = tz }
        proc.environment = env
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        let id = p.id
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.processes[id] = nil
                self?.refresh()
            }
        }
        try proc.run()
        processes[id] = proc
    }

    /// Chrome on macOS keeps running after its last window is closed. Starting the
    /// profile again then activates it, or asks the running Chrome for a new window.
    private func bringToFront(_ profiles: [BrowserProfile], exe: URL) {
        guard let store else { return }
        setFrozen(profiles.map(\.id), false)
        for p in profiles {
            guard let pid = running[p.id] else { continue }
            autoFreezer.markActive(pid)
            if Self.hasWindows(pid) {
                NSRunningApplication(processIdentifier: pid)?.activate()
            } else {
                let proc = Process()
                proc.executableURL = exe
                proc.arguments = ["--user-data-dir=\(store.dataDir(for: p.id).path)"]
                proc.standardOutput = FileHandle.nullDevice
                proc.standardError = FileHandle.nullDevice
                try? proc.run()
            }
        }
    }

    static func hasWindows(_ pid: pid_t) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return true
        }
        return list.contains { w in
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: dict) else { return false }
            return r.width >= 300 && r.height >= 200
        }
    }

    // MARK: Close

    /// Asks Chrome to quit normally so tabs, history, cookies and cache are written
    /// to disk. A frozen profile is resumed first: a paused Chrome cannot quit.
    func stop(_ ids: [UUID]) {
        Task { @MainActor in await quit(ids) }
    }

    /// Closes open profiles and starts them again, e.g. on an updated Chrome.
    /// Their tabs come back; profiles that did not close are left alone.
    func restart(_ ids: [UUID], tile: Bool) {
        Task { @MainActor in
            await quit(ids)
            let closed = ids.filter { !isRunning($0) }.compactMap { store?.profile($0) }
            if !closed.isEmpty { launch(closed, tile: tile) }
        }
    }

    private func quit(_ ids: [UUID]) async {
        let targets = ids.compactMap { id in running[id].map { (id: id, pid: $0) } }
        guard !targets.isEmpty else { return }
        setFrozen(targets.map(\.id), false)

        try? await Task.sleep(nanoseconds: 300_000_000)
        for t in targets {
            if let app = NSRunningApplication(processIdentifier: t.pid), app.terminate() { continue }
            kill(t.pid, SIGTERM)
        }
        // Wait up to 20 s for a clean exit. Never force-kill: that loses data.
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            refresh()
            if targets.allSatisfy({ running[$0.id] == nil }) { break }
        }
        let stuck = targets.filter { running[$0.id] != nil }
            .compactMap { store?.profile($0.id)?.name }
        if !stuck.isEmpty {
            lastError = "Не закрылись: \(stuck.joined(separator: ", ")). "
                + "Chrome, возможно, ждёт ответа в своём окне (например, о незавершённой загрузке)."
        }
        sampleUsage()
    }

    func stopAll() { stop(Array(running.keys)) }

    // MARK: Freeze

    /// Freezing pauses every process of the profile: 0% CPU, memory stays allocated
    /// (macOS can compress or swap it). Pages resume exactly where they were.
    func setFrozen(_ ids: [UUID], _ freeze: Bool) {
        let targets = ids.filter { isRunning($0) && isFrozen($0) != freeze }
        guard !targets.isEmpty else { return }
        signalTree(targets, freeze ? SIGSTOP : SIGCONT)
        if freeze {
            frozen.formUnion(targets)
        } else {
            frozen.subtract(targets)
            for id in targets { if let pid = running[id] { autoFreezer.markActive(pid) } }
        }
        if let store { badges.update(running: running, profiles: store.profiles, frozen: frozen) }
        sampleUsage()
    }

    func unfreezeAll() {
        guard !frozen.isEmpty else { return }
        signalTree(Array(frozen), SIGCONT)
        frozen = []
    }

    private func signalTree(_ ids: [UUID], _ sig: Int32) {
        let roots = running.filter { ids.contains($0.key) }
        for (id, tree) in ResourceMonitor.snapshot(roots: roots) {
            // Resume the browser process last so it never sees its helpers still paused.
            let pids = sig == SIGCONT ? tree.pids.reversed() : tree.pids
            for pid in pids { kill(pid, sig) }
            if sig == SIGCONT, let root = roots[id] { kill(root, SIGCONT) }
        }
    }
}
