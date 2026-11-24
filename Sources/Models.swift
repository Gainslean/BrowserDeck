import Foundation

/// One isolated browser identity: its own Chrome user-data-dir plus launch settings.
struct BrowserProfile: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var userAgent = ""
    var proxy = ""
    var language = ""
    var timezone = ""
    var windowWidth = 1280
    var windowHeight = 800
    var startURL = ""
    var blockWebRTCLeak = true
    var performance = PerformanceMode.economy
    var blockImages = false
    var tintWindow = true
    var autoFreeze = true
    var syncUserAgent = true
    var notes = ""
    var createdAt = Date()
    var lastLaunched: Date?

    init(name: String) { self.name = name }

    // Tolerant decoding: fields added in later versions fall back to defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BrowserProfile(name: "")
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? d.id
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Без имени"
        userAgent = try c.decodeIfPresent(String.self, forKey: .userAgent) ?? d.userAgent
        proxy = try c.decodeIfPresent(String.self, forKey: .proxy) ?? d.proxy
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? d.language
        timezone = try c.decodeIfPresent(String.self, forKey: .timezone) ?? d.timezone
        windowWidth = try c.decodeIfPresent(Int.self, forKey: .windowWidth) ?? d.windowWidth
        windowHeight = try c.decodeIfPresent(Int.self, forKey: .windowHeight) ?? d.windowHeight
        startURL = try c.decodeIfPresent(String.self, forKey: .startURL) ?? d.startURL
        blockWebRTCLeak = try c.decodeIfPresent(Bool.self, forKey: .blockWebRTCLeak) ?? d.blockWebRTCLeak
        performance = try c.decodeIfPresent(PerformanceMode.self, forKey: .performance) ?? d.performance
        blockImages = try c.decodeIfPresent(Bool.self, forKey: .blockImages) ?? d.blockImages
        tintWindow = try c.decodeIfPresent(Bool.self, forKey: .tintWindow) ?? d.tintWindow
        autoFreeze = try c.decodeIfPresent(Bool.self, forKey: .autoFreeze) ?? d.autoFreeze
        syncUserAgent = try c.decodeIfPresent(Bool.self, forKey: .syncUserAgent) ?? d.syncUserAgent
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? d.notes
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? d.createdAt
        lastLaunched = try c.decodeIfPresent(Date.self, forKey: .lastLaunched)
    }

    /// Stable per-profile hue (0…1) shared by the avatar, window label and Chrome theme.
    var badgeHue: Double { Double(id.uuid.0) / 255 }

    /// Short OS label derived from the user agent, for list rows.
    var osLabel: String {
        if userAgent.isEmpty { return "UA по умолчанию" }
        if userAgent.contains("Windows") { return "Windows" }
        if userAgent.contains("Macintosh") { return "macOS" }
        if userAgent.contains("Linux") { return "Linux" }
        return "свой UA"
    }
}

/// Settings for creating many profiles at once.
struct BatchOptions {
    var count = 5
    var prefix = "Профиль"
    var randomUserAgent = false
    var language = ""
    var timezone = ""
    var proxies: [String] = []
    var performance = PerformanceMode.economy
    var launchAfterCreate = false
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
