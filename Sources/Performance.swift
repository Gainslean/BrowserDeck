import Foundation

/// How hard a profile's Chrome is tuned to save RAM and CPU.
enum PerformanceMode: String, Codable, CaseIterable, Identifiable {
    case standard, economy, maximum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Обычный Chrome"
        case .economy: return "Экономный"
        case .maximum: return "Максимальная экономия"
        }
    }

    var hint: String {
        switch self {
        case .standard:
            return "Без изменений — как обычный Chrome."
        case .economy:
            return "Сайтам сообщается «меньше анимаций» (главная экономия процессора), неактивные "
                + "вкладки выгружаются из памяти, отключены фоновые службы и предзагрузка страниц."
        case .maximum:
            return "Дополнительно: меньше процессов на окно, режим слабого устройства, "
                + "энергосбережение (до 30 кадров/с), без автозапуска видео. "
                + "Слабее изоляция сайтов друг от друга; тяжёлые сайты могут работать медленнее."
        }
    }
}

/// Chrome flags and prefs behind each mode.
enum PerformanceTuning {
    static func flags(_ mode: PerformanceMode, blockImages: Bool) -> [String] {
        var a: [String] = []
        var disabled: [String] = []

        if mode != .standard {
            a += [
                "--disable-background-mode",
                "--disable-breakpad",
                "--disable-domain-reliability",
                "--no-pings",
                "--disable-component-extensions-with-background-pages",
                // Measured: page animations were ~13% CPU per idle window; this drops it to ~0-5%.
                "--force-prefers-reduced-motion",
                "--disable-smooth-scrolling",
            ]
            // A pre-warmed spare renderer and the back/forward page cache cost
            // tens of MB per window; casting and hint services run in the background.
            disabled += ["SpareRendererForSitePerProcess", "BackForwardCache",
                         "MediaRouter", "DialMediaRouteProvider", "OptimizationHints"]
        }
        if mode == .maximum {
            a += [
                "--process-per-site",
                "--renderer-process-limit=3",
                "--disable-site-isolation-trials",
                "--enable-low-end-device-mode",
                "--autoplay-policy=user-gesture-required",
            ]
            disabled += ["IsolateOrigins", "site-per-process"]
        }
        if !disabled.isEmpty { a.append("--disable-features=" + disabled.joined(separator: ",")) }
        if blockImages { a.append("--blink-settings=imagesEnabled=false") }
        return a
    }

    /// Per-profile prefs (Default/Preferences).
    static func applyProfilePrefs(_ mode: PerformanceMode, to prefs: inout [String: Any]) {
        // 2 = never preload/prerender pages the user has not opened.
        JSONTree.set(&prefs, ["net", "network_prediction_options"], mode == .standard ? nil : 2)
    }

    /// Browser-wide prefs (Local State): Memory Saver and Energy Saver.
    static func applyLocalState(_ mode: PerformanceMode, to state: inout [String: Any]) {
        let saver = ["performance_tuning", "high_efficiency_mode"]
        let battery = ["performance_tuning", "battery_saver_mode", "state"]
        switch mode {
        case .standard:
            JSONTree.set(&state, saver + ["state"], nil)
            JSONTree.set(&state, saver + ["aggressiveness"], nil)
            JSONTree.set(&state, battery, nil)
        case .economy:
            JSONTree.set(&state, saver + ["state"], 2)           // enabled
            JSONTree.set(&state, saver + ["aggressiveness"], 1)  // medium
            JSONTree.set(&state, battery, nil)
            JSONTree.set(&state, ["background_mode", "enabled"], false)
        case .maximum:
            JSONTree.set(&state, saver + ["state"], 2)
            JSONTree.set(&state, saver + ["aggressiveness"], 2)  // discard tabs sooner
            JSONTree.set(&state, battery, 3)                     // energy saver always on
            JSONTree.set(&state, ["background_mode", "enabled"], false)
        }
    }
}

/// Small helpers for editing Chrome's JSON pref files.
enum JSONTree {
    static func set(_ dict: inout [String: Any], _ path: [String], _ value: Any?) {
        guard let key = path.first else { return }
        if path.count == 1 {
            dict[key] = value
            return
        }
        var child = dict[key] as? [String: Any] ?? [:]
        set(&child, Array(path.dropFirst()), value)
        dict[key] = child
    }

    /// Reads the JSON object at `url` (or starts empty), edits it, writes it back.
    static func update(_ url: URL, _ edit: (inout [String: Any]) -> Void) throws {
        var obj: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            obj = parsed
        }
        edit(&obj)
        try JSONSerialization.data(withJSONObject: obj).write(to: url, options: .atomic)
    }
}
