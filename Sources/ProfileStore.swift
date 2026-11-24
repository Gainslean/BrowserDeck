import AppKit
import Foundation

/// Keeps the profile list in ~/Library/Application Support/BrowserDeck/profiles.json
/// and owns the per-profile Chrome data folders.
@MainActor
final class ProfileStore: ObservableObject {
    @Published var profiles: [BrowserProfile] = [] {
        didSet { if !isLoading { scheduleSave() } }
    }

    let baseDir: URL
    let cacheBaseDir: URL
    private var isLoading = false
    private var saveTask: Task<Void, Never>?

    /// `baseDir` is for tests; the app uses ~/Library/Application Support/BrowserDeck.
    init(baseDir custom: URL? = nil) {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        baseDir = custom ?? support.appendingPathComponent("BrowserDeck", isDirectory: true)
        cacheBaseDir = custom?.appendingPathComponent("Caches", isDirectory: true)
            ?? caches.appendingPathComponent("BrowserDeck/Profiles", isDirectory: true)
        try? fm.createDirectory(at: profilesDir, withIntermediateDirectories: true)
        load()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    var profilesDir: URL { baseDir.appendingPathComponent("Profiles", isDirectory: true) }
    private var fileURL: URL { baseDir.appendingPathComponent("profiles.json") }

    /// Chrome's --user-data-dir for the profile: cookies, history, logins, extensions.
    func dataDir(for id: UUID) -> URL {
        profilesDir.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Chrome on macOS keeps the disk cache of a data dir that lives under
    /// ~/Library/Application Support at the mirrored path in ~/Library/Caches.
    func cacheDir(for id: UUID) -> URL {
        cacheBaseDir.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func profile(_ id: UUID) -> BrowserProfile? { profiles.first { $0.id == id } }

    // MARK: Persistence

    private func load() {
        isLoading = true
        defer { isLoading = false }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            profiles = try decoder.decode([BrowserProfile].self, from: data)
        } catch {
            // Keep the unreadable file instead of losing it on the next save.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = baseDir.appendingPathComponent("profiles.broken-\(stamp).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
        }
    }

    /// Typing in the editor changes the list on every keystroke; write once it settles.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func flush() {
        saveTask?.cancel()
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(profiles) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: Editing

    @discardableResult
    func addProfile() -> BrowserProfile {
        let p = BrowserProfile(name: nextName(prefix: "Профиль"))
        profiles.append(p)
        return p
    }

    func nextName(prefix: String) -> String {
        let taken = Set(profiles.map(\.name))
        var n = 1
        while taken.contains("\(prefix) \(n)") { n += 1 }
        return "\(prefix) \(n)"
    }

    func createBatch(_ o: BatchOptions, userAgents: [String]) -> [UUID] {
        var taken = Set(profiles.map(\.name))
        var created: [BrowserProfile] = []
        var n = 1
        for i in 0..<max(o.count, 0) {
            while taken.contains("\(o.prefix) \(n)") { n += 1 }
            var p = BrowserProfile(name: "\(o.prefix) \(n)")
            taken.insert(p.name)
            if o.randomUserAgent, let ua = userAgents.randomElement() { p.userAgent = ua }
            p.language = o.language
            p.timezone = o.timezone
            p.performance = o.performance
            if !o.proxies.isEmpty { p.proxy = o.proxies[i % o.proxies.count] }
            created.append(p)
        }
        profiles.append(contentsOf: created)
        return created.map(\.id)
    }

    /// Copies the settings (not the cookies/history) into a new profile.
    func duplicate(_ id: UUID) -> UUID? {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = profiles[i]
        copy.id = UUID()
        copy.name = nextName(prefix: profiles[i].name + " копия")
        copy.createdAt = Date()
        copy.lastLaunched = nil
        profiles.insert(copy, at: i + 1)
        return copy.id
    }

    func markLaunched(_ ids: [UUID]) {
        var updated = profiles
        for i in updated.indices where ids.contains(updated[i].id) {
            updated[i].lastLaunched = Date()
        }
        profiles = updated
    }

    /// Raises the Chrome version in the profiles' user agents to the installed one.
    func syncUserAgents(_ ids: [UUID], chromeMajor: String) {
        var updated = profiles
        for i in updated.indices where ids.contains(updated[i].id) && updated[i].syncUserAgent {
            updated[i].userAgent = UserAgentVersion.updated(updated[i].userAgent, major: chromeMajor)
        }
        if updated != profiles { profiles = updated }
    }

    /// Moves the profile folders to the Trash (recoverable) and forgets the profiles.
    func delete(_ ids: Set<UUID>) {
        let fm = FileManager.default
        for id in ids {
            for dir in [dataDir(for: id), cacheDir(for: id)] where fm.fileExists(atPath: dir.path) {
                try? fm.trashItem(at: dir, resultingItemURL: nil)
            }
        }
        profiles.removeAll { ids.contains($0.id) }
    }

    /// Drops only cache folders; cookies, logins and history stay.
    func clearCache(_ id: UUID) {
        let fm = FileManager.default
        try? fm.removeItem(at: cacheDir(for: id))
        let d = dataDir(for: id).appendingPathComponent("Default")
        for sub in ["Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache"] {
            try? fm.removeItem(at: d.appendingPathComponent(sub))
        }
    }
}
