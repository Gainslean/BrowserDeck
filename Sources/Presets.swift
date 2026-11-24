import Foundation

struct Preset: Identifiable, Hashable {
    let label: String
    let value: String
    var id: String { label + "|" + value }
}

/// Ready-made values for the profile editor menus.
enum Presets {
    /// Chrome sends a "reduced" user agent: only OS family and major version vary.
    /// Using the installed major keeps the UA consistent with the real engine.
    static func userAgents(chromeMajor v: String) -> [Preset] {
        func tail(_ ver: String) -> String {
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(ver).0.0.0 Safari/537.36"
        }
        let mac = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
        let win = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
        let linux = "Mozilla/5.0 (X11; Linux x86_64)"
        return [
            Preset(label: "macOS · Chrome \(v)", value: "\(mac) \(tail(v))"),
            Preset(label: "Windows 10/11 · Chrome \(v)", value: "\(win) \(tail(v))"),
            Preset(label: "Linux · Chrome \(v)", value: "\(linux) \(tail(v))"),
        ]
    }

    static let languages: [Preset] = [
        Preset(label: "Русский", value: "ru-RU"),
        Preset(label: "English (US)", value: "en-US"),
        Preset(label: "English (UK)", value: "en-GB"),
        Preset(label: "Deutsch", value: "de-DE"),
        Preset(label: "Français", value: "fr-FR"),
        Preset(label: "Español", value: "es-ES"),
        Preset(label: "Italiano", value: "it-IT"),
        Preset(label: "Polski", value: "pl-PL"),
        Preset(label: "Українська", value: "uk-UA"),
        Preset(label: "Türkçe", value: "tr-TR"),
        Preset(label: "Português (BR)", value: "pt-BR"),
    ]

    static let timezones: [Preset] = [
        "Europe/Moscow", "Europe/Kyiv", "Europe/Minsk", "Europe/Berlin", "Europe/London",
        "Europe/Paris", "Europe/Warsaw", "Europe/Istanbul", "Asia/Almaty", "Asia/Dubai",
        "Asia/Tokyo", "Asia/Singapore", "America/New_York", "America/Chicago",
        "America/Los_Angeles", "America/Sao_Paulo", "UTC",
    ].map { Preset(label: $0, value: $0) }
}
