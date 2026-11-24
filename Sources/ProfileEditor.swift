import SwiftUI

/// Settings form for a single profile.
struct ProfileEditor: View {
    @Binding var profile: BrowserProfile
    let running: Bool
    let usage: ProfileUsage?
    let chromeMajor: String
    let dataPath: String
    let onLaunch: () -> Void
    let onStop: () -> Void
    let onFreeze: () -> Void
    let onClearCache: () -> Void
    let onReveal: () -> Void

    var body: some View {
        Form {
            Section { header }

            Section("Профиль") {
                TextField("Название", text: $profile.name)
                TextField("Стартовая страница", text: $profile.startURL,
                          prompt: Text("https://example.com"))
                TextField("Заметки", text: $profile.notes,
                          prompt: Text("аккаунт, логин, что угодно"), axis: .vertical)
                    .lineLimit(2...5)
            }

            Section {
                PresetField(title: "User-Agent", text: $profile.userAgent,
                            prompt: "как у установленного Chrome",
                            presets: Presets.userAgents(chromeMajor: chromeMajor))
                Toggle("Обновлять версию Chrome в User-Agent", isOn: $profile.syncUserAgent)
                    .help("При запуске номер версии в User-Agent становится таким же, как у установленного Chrome")
                PresetField(title: "Язык", text: $profile.language,
                            prompt: "системный", presets: Presets.languages)
                PresetField(title: "Часовой пояс", text: $profile.timezone,
                            prompt: "системный", presets: Presets.timezones)
                Toggle("Не раскрывать реальный IP через WebRTC", isOn: $profile.blockWebRTCLeak)
            } header: {
                Text("Отпечаток")
            } footer: {
                Text("User-Agent меняет заголовок и navigator.userAgent. navigator.platform и "
                     + "Client Hints всё равно сообщают macOS, поэтому самый правдоподобный "
                     + "вариант — UA для macOS. Язык и часовой пояс подменяются полностью.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Режим", selection: $profile.performance) {
                    ForEach(PerformanceMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Не загружать картинки", isOn: $profile.blockImages)
                Toggle("Замораживать, когда окном не пользуются", isOn: $profile.autoFreeze)
                    .help("Выключите для страниц, которые должны работать в фоне: трансляции, торговля, чаты")
                Toggle("Окно Chrome в цвете профиля", isOn: $profile.tintWindow)
            } header: {
                Text("Память и процессор")
            } footer: {
                Text(profile.performance.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("Прокси", text: $profile.proxy,
                          prompt: Text("socks5://host:port или http://host:port"))
            } header: {
                Text("Сеть")
            } footer: {
                Text("Прокси с логином/паролем Chrome через флаги не поддерживает — "
                     + "используйте прокси с авторизацией по IP.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    TextField("Ширина", value: $profile.windowWidth,
                              format: .number.grouping(.never))
                    TextField("Высота", value: $profile.windowHeight,
                              format: .number.grouping(.never))
                }
            } header: {
                Text("Окно")
            } footer: {
                Text("Размер используется, когда раскладка «плиткой» выключена.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Данные") {
                LabeledContent("Папка профиля") {
                    Text(dataPath)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                HStack {
                    Button("Показать в Finder", action: onReveal)
                    Button("Очистить кеш", action: onClearCache)
                        .disabled(running)
                        .help("Удаляет только кеш. Куки, логины и история остаются.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ProfileAvatar(profile: profile, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name.isEmpty ? "Без имени" : profile.name)
                    .font(.title2.bold())
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(frozen ? Color.blue : running ? Color.green : Color.secondary)
                    .monospacedDigit()
            }
            Spacer()
            if running {
                Button(action: onFreeze) {
                    Label(frozen ? "Разморозить" : "Заморозить", systemImage: "snowflake")
                }
                .controlSize(.large)
                .help("Заморозка ставит профиль на паузу: 0% процессора, страницы остаются как были")
                Button(action: onStop) { Label("Закрыть", systemImage: "stop.fill") }
                    .controlSize(.large)
            } else {
                Button(action: onLaunch) { Label("Запустить", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(.vertical, 4)
    }

    private var frozen: Bool { usage?.frozen ?? false }

    private var statusText: String {
        if running {
            guard let u = usage else { return "Открыт · изменения применятся после перезапуска" }
            let load = u.frozen ? "заморожен" : "ЦП \(u.cpuPercent)%"
            return "Открыт · \(u.memoryText) · \(load) · процессов: \(u.processes)"
        }
        guard let d = profile.lastLaunched else { return "Ещё не запускался" }
        return "Последний запуск: " + d.formatted(date: .abbreviated, time: .shortened)
    }
}

/// Text field with a menu of ready-made values.
struct PresetField: View {
    let title: String
    @Binding var text: String
    let prompt: String
    let presets: [Preset]

    var body: some View {
        HStack(spacing: 6) {
            TextField(title, text: $text, prompt: Text(prompt))
            Menu {
                ForEach(presets) { p in
                    Button(p.label) { text = p.value }
                }
                if !text.isEmpty {
                    Divider()
                    Button("Сбросить") { text = "" }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Выбрать из списка")
        }
    }
}
