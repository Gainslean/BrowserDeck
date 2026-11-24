import SwiftUI

/// Chrome version in the status bar, with update state and actions in a menu.
struct ChromeStatusView: View {
    @ObservedObject var updater: ChromeUpdater
    let chromeFound: Bool
    let outdated: Int
    let onRestartOutdated: () -> Void
    @AppStorage("chromeAutoUpdate") private var autoUpdate = true

    var body: some View {
        if chromeFound {
            Menu {
                Text(stateText)
                Button("Проверить обновление Chrome") { updater.check() }
                    .disabled(updater.state == .checking)
                Toggle("Обновлять Chrome автоматически", isOn: $autoUpdate)
                if outdated > 0 {
                    Divider()
                    Button("Перезапустить на новой версии (\(outdated))", action: onRestartOutdated)
                }
            } label: {
                Label("Chrome \(updater.installedVersion)", systemImage: icon)
                    .foregroundStyle(outdated > 0 ? Color.orange : Color.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(outdated > 0
                  ? "Открытых профилей на старой версии Chrome: \(outdated). Перезапустите их из этого меню."
                  : stateText)
            .onAppear {
                updater.autoCheck = autoUpdate
                updater.start()
            }
            .onChange(of: autoUpdate) { _, on in updater.autoCheck = on }
        } else {
            Label("Chrome не найден", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private var icon: String {
        if case .failed = updater.state { return "exclamationmark.triangle" }
        if updater.state == .checking { return "arrow.triangle.2.circlepath" }
        return outdated > 0 ? "arrow.clockwise.circle.fill" : "checkmark.circle"
    }

    private var stateText: String {
        switch updater.state {
        case .idle: return "Обновление ещё не проверялось"
        case .checking: return "Проверяю обновление Chrome…"
        case .upToDate(let date):
            return "Обновлений нет, проверено в \(date.formatted(date: .omitted, time: .shortened))"
        case .updated(let from, let to): return "Chrome обновлён: \(from) → \(to)"
        case .failed(let text): return text
        }
    }
}
