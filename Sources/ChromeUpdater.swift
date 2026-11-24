import Foundation

/// Keeps Chrome current through Google's own updater (the one behind chrome://settings/help).
/// BrowserDeck downloads nothing itself: it only asks that updater to check and install.
/// Open Chromes keep running their old version until they are restarted.
@MainActor
final class ChromeUpdater: ObservableObject {
    enum State: Equatable {
        case idle, checking
        case upToDate(Date)
        case updated(from: String, to: String)
        case failed(String)
    }

    @Published private(set) var installedVersion: String
    @Published private(set) var state = State.idle

    /// Automatic checks on or off; a manual check always works.
    var autoCheck = true

    private let chromeApp: URL?
    private var lastCheck: Date?
    private var timer: Timer?
    static let checkEvery: TimeInterval = 6 * 3600

    init(chromeApp: URL?) {
        self.chromeApp = chromeApp
        installedVersion = chromeApp.flatMap(Self.version(of:)) ?? "?"
    }

    func start() {
        guard timer == nil else { return }
        tick()
        let t = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        t.tolerance = 20
        timer = t
    }

    private func tick() {
        reloadVersion()   // Chrome may also be updated outside this app
        guard autoCheck, state != .checking else { return }
        if let last = lastCheck, Date().timeIntervalSince(last) < Self.checkEvery { return }
        check()
    }

    func reloadVersion() {
        guard let v = chromeApp.flatMap(Self.version(of:)), v != installedVersion else { return }
        installedVersion = v
    }

    /// Checks now and installs an update if Google offers one.
    func check() {
        guard state != .checking else { return }
        lastCheck = Date()
        let before = installedVersion
        state = .checking
        Task {
            let error = await Task.detached(priority: .utility) { Self.runUpdater() }.value
            reloadVersion()
            if installedVersion != before {
                state = .updated(from: before, to: installedVersion)
            } else if let error {
                state = .failed(error)
            } else {
                state = .upToDate(Date())
            }
        }
    }

    /// Read from disk each time: `Bundle` caches Info.plist for the life of the app.
    nonisolated static func version(of app: URL) -> String? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return info["CFBundleShortVersionString"] as? String
    }

    // MARK: Google's updater

    nonisolated private static let product = "com.google.Chrome"

    /// Chrome is registered with either the per-user or the system-wide updater.
    nonisolated private static func registeredUpdater() -> (tool: URL, store: String)? {
        let tail = "Library/Application Support/Google/GoogleUpdater/Current/GoogleUpdater.app/Contents/"
            + "Helpers/GoogleSoftwareUpdate.bundle/Contents/Helpers/ksadmin"
        let candidates = [(NSHomeDirectory() + "/" + tail, "-U"), ("/" + tail, "-S")]
        for (path, store) in candidates where FileManager.default.isExecutableFile(atPath: path) {
            let url = URL(fileURLWithPath: path)
            let r = run(url, [store, "-p", "-P", product], timeout: 30)
            if r.status == 0, r.output.lowercased().contains(product.lowercased()) { return (url, store) }
        }
        return nil
    }

    /// Returns an error text, or nil when the check finished.
    nonisolated private static func runUpdater() -> String? {
        guard let u = registeredUpdater() else {
            return "Апдейтер Google не найден. Откройте обычный Chrome → «О браузере»."
        }
        let r = run(u.tool, [u.store, "-i", "-F", "-P", product], timeout: 900)
        if r.timedOut { return "Апдейтер Google не ответил за 15 минут." }
        return r.status == 0 ? nil : "Апдейтер Google завершился с ошибкой (код \(r.status))."
    }

    nonisolated private static func run(
        _ exe: URL, _ args: [String], timeout: TimeInterval
    ) -> (status: Int32, output: String, timedOut: Bool) {
        let proc = Process()
        proc.executableURL = exe
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return (-1, "", false) }
        let deadline = DispatchTime.now() + timeout
        var expired = false
        let lock = NSLock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: deadline) {
            guard proc.isRunning else { return }
            lock.withLock { expired = true }
            proc.terminate()
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return (proc.terminationStatus, String(decoding: data, as: UTF8.self), lock.withLock { expired })
    }
}

/// Keeps the Chrome version inside a profile's user agent equal to the installed one:
/// Client Hints always report the real version, so an old number in the UA stands out.
enum UserAgentVersion {
    /// Only plain Chrome agents ("Chrome/157.0.0.0 Safari/537.36") are touched.
    /// Edge, Opera and other custom strings stay as typed.
    static func updated(_ ua: String, major: String) -> String {
        guard Int(major) != nil,
              let r = ua.range(of: #"Chrome/\d+(\.\d+){3}(?= (Mobile )?Safari/[\d.]+\s*$)"#,
                               options: .regularExpression) else { return ua }
        return ua.replacingCharacters(in: r, with: "Chrome/\(major).0.0.0")
    }
}
