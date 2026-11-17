import AppKit

struct LaunchError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Command-line flags for one Chrome instance.
enum LaunchArguments {
    static func build(for p: BrowserProfile, dataDir: URL, frame: CGRect) throws -> [String] {
        var a = [
            "--user-data-dir=\(dataDir.path)",
            "--no-first-run",
            "--no-default-browser-check",
            "--hide-crash-restore-bubble",
            // Reopen the tabs from last time, even after an unclean exit.
            "--restore-last-session",
            // Shows in the Window menu, Mission Control and the Dock icon's menu.
            "--window-name=\(p.name.isEmpty ? "Без имени" : p.name)",
            "--window-position=\(Int(frame.minX)),\(Int(frame.minY))",
            "--window-size=\(Int(frame.width)),\(Int(frame.height))",
        ]
        let ua = p.userAgent.trimmed
        if !ua.isEmpty { a.append("--user-agent=\(ua)") }

        if let proxy = try normalizedProxy(p.proxy) { a.append("--proxy-server=\(proxy)") }

        if p.blockWebRTCLeak {
            a.append("--force-webrtc-ip-handling-policy=disable_non_proxied_udp")
        }

        let lang = p.language.trimmed
        if !lang.isEmpty { a.append("--lang=\(lang)") }

        let tz = p.timezone.trimmed
        if !tz.isEmpty && TimeZone(identifier: tz) == nil {
            throw LaunchError(message: "Неизвестный часовой пояс «\(tz)». Пример: Europe/Moscow")
        }

        a += PerformanceTuning.flags(p.performance, blockImages: p.blockImages)

        // The start page opens only on the first launch; later the last tabs come back.
        let url = p.startURL.trimmed
        if !url.isEmpty && !hasSavedSession(dataDir) { a.append(url.contains("://") ? url : "https://" + url) }
        return a
    }

    static func hasSavedSession(_ dataDir: URL) -> Bool {
        let dir = dataDir.appendingPathComponent("Default/Sessions").path
        return !((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).isEmpty
    }

    static func normalizedProxy(_ raw: String) throws -> String? {
        let s = raw.trimmed
        if s.isEmpty { return nil }
        if s.contains("@") {
            throw LaunchError(message: "Прокси с логином и паролем Chrome через флаг не принимает. "
                + "Используйте прокси с авторизацией по IP (без user:pass@).")
        }
        let withScheme = s.contains("://") ? s : "http://" + s
        guard let u = URL(string: withScheme),
              let scheme = u.scheme?.lowercased(),
              ["http", "https", "socks4", "socks5"].contains(scheme),
              u.host != nil, u.port != nil else {
            throw LaunchError(message: "Не понимаю прокси «\(s)». Формат: socks5://host:port или http://host:port")
        }
        return withScheme
    }
}

/// Seeds Chrome's pref files before launch. Only unprotected prefs are touched,
/// so Chrome's tamper protection keeps them.
enum PreferencesWriter {
    static func apply(_ p: BrowserProfile, dataDir: URL) throws {
        let dir = dataDir.appendingPathComponent("Default", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        try JSONTree.update(dir.appendingPathComponent("Preferences")) { prefs in
            JSONTree.set(&prefs, ["profile", "name"], p.name)
            // No "Chrome didn't shut down correctly" bubble after a forced close.
            JSONTree.set(&prefs, ["profile", "exit_type"], "Normal")
            JSONTree.set(&prefs, ["profile", "exited_cleanly"], true)
            // 1 = "Continue where you left off": reopen last tabs on every start.
            JSONTree.set(&prefs, ["session", "restore_on_startup"], 1)
            JSONTree.set(&prefs, ["webrtc", "ip_handling_policy"],
                         p.blockWebRTCLeak ? "disable_non_proxied_udp" : "default")

            let lang = p.language.trimmed
            if lang.isEmpty {
                JSONTree.set(&prefs, ["intl", "accept_languages"], nil)
                JSONTree.set(&prefs, ["intl", "selected_languages"], nil)
            } else {
                let base = lang.split(separator: "-").first.map(String.init) ?? lang
                let list = base == lang ? lang : "\(lang),\(base)"
                JSONTree.set(&prefs, ["intl", "accept_languages"], list)
                JSONTree.set(&prefs, ["intl", "selected_languages"], list)
            }
            PerformanceTuning.applyProfilePrefs(p.performance, to: &prefs)
            // Tint the whole Chrome frame in the profile's colour.
            let colorPath = ["browser", "theme", "user_color"]
            if p.tintWindow {
                JSONTree.set(&prefs, colorPath, p.themeSkColor)
            } else if ((prefs["browser"] as? [String: Any])?["theme"] as? [String: Any])?["user_color"]
                        as? Int == p.themeSkColor {
                JSONTree.set(&prefs, colorPath, nil)   // undo only our own tint
            }
        }

        try JSONTree.update(dataDir.appendingPathComponent("Local State")) { state in
            PerformanceTuning.applyLocalState(p.performance, to: &state)
        }
    }
}

/// Window frames in Chrome's coordinates (top-left origin of the primary display).
enum WindowLayout {
    static func grid(count: Int) -> [CGRect] {
        guard count > 0, let screen = NSScreen.main ?? NSScreen.screens.first else { return [] }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let vf = screen.visibleFrame
        let cols = Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(cols)))
        let w = vf.width / CGFloat(cols)
        let h = vf.height / CGFloat(rows)
        let top = primaryHeight - vf.maxY
        return (0..<count).map { i in
            CGRect(x: vf.minX + CGFloat(i % cols) * w,
                   y: top + CGFloat(i / cols) * h,
                   width: w, height: h)
        }
    }

    static func cascade(index: Int, width: Int, height: Int) -> CGRect {
        let offset = CGFloat(index % 12) * 32
        return CGRect(x: 80 + offset, y: 60 + offset,
                      width: CGFloat(max(width, 400)), height: CGFloat(max(height, 300)))
    }
}
