import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Window labels and auto-freeze run in this app, so closing its window keeps it
    /// alive in the Dock. Quit with Cmd+Q; frozen profiles are resumed on quit.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct BrowserDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = ProfileStore()
    @StateObject private var launcher = ChromeLauncher()

    var body: some Scene {
        Window("BrowserDeck", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(launcher)
                .frame(minWidth: 880, minHeight: 560)
        }
        .defaultSize(width: 1080, height: 700)
    }
}
