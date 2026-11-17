import SwiftUI

/// Round badge with a stable colour per profile.
struct ProfileAvatar: View {
    let profile: BrowserProfile
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle().fill(color.gradient)
            Text(initials)
                .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    private var color: Color {
        Color(nsColor: profile.badgeColor)
    }

    private var initials: String {
        let name = profile.name.trimmed
        let digits = name.reversed().prefix { $0.isNumber }
        if !digits.isEmpty { return String(digits.reversed().suffix(3)) }
        return String(name.prefix(2)).uppercased()
    }
}

struct ProfileRow: View {
    let profile: BrowserProfile
    let running: Bool
    var usage: ProfileUsage?

    var body: some View {
        HStack(spacing: 10) {
            ProfileAvatar(profile: profile)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name.isEmpty ? "Без имени" : profile.name).lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            if usage?.frozen == true {
                Image(systemName: "snowflake").font(.caption).foregroundStyle(.blue).help("Заморожен")
            } else if running {
                Circle().fill(.green).frame(width: 8, height: 8).help("Открыт")
            }
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        if let u = usage {
            return u.frozen ? "\(u.memoryText) · заморожен" : "\(u.memoryText) · ЦП \(u.cpuPercent)%"
        }
        var parts = [profile.osLabel]
        if let host = URL(string: profile.proxy.contains("://") ? profile.proxy : "http://" + profile.proxy)?.host,
           !profile.proxy.trimmed.isEmpty {
            parts.append(host)
        }
        if !profile.timezone.isEmpty { parts.append(profile.timezone) }
        return parts.joined(separator: " · ")
    }
}

struct MultiSelectionView: View {
    let count: Int
    let runningCount: Int
    let onLaunch: () -> Void
    let onStop: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Выбрано профилей: \(count)").font(.title2.bold())
            Text("Открыто: \(runningCount)").foregroundStyle(.secondary)
            HStack {
                Button(action: onLaunch) { Label("Запустить все", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
                Button(action: onStop) { Label("Закрыть все", systemImage: "stop.fill") }
                    .disabled(runningCount == 0)
                Button(role: .destructive, action: onDelete) { Label("Удалить…", systemImage: "trash") }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
    let hasProfiles: Bool
    let onNew: () -> Void
    let onBatch: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text(hasProfiles ? "Выберите профиль" : "Профилей пока нет").font(.title2.bold())
            Text("У каждого профиля своя папка Chrome: куки, кеш, история и логины "
                 + "хранятся отдельно и сохраняются между запусками.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            HStack {
                Button(action: onNew) { Label("Новый профиль", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                Button(action: onBatch) { Label("Создать несколько", systemImage: "plus.square.on.square") }
            }
            .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Sheet for creating many profiles at once.
struct BatchCreateSheet: View {
    let onCreate: (BatchOptions) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var options = BatchOptions()
    @State private var proxyText = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Создать профили") {
                    Stepper(value: $options.count, in: 1...100) {
                        LabeledContent("Количество", value: "\(options.count)")
                    }
                    TextField("Префикс имени", text: $options.prefix)
                }
                Section("Отпечаток") {
                    Toggle("Случайный User-Agent (Windows / macOS / Linux)", isOn: $options.randomUserAgent)
                    PresetField(title: "Язык", text: $options.language,
                                prompt: "системный", presets: Presets.languages)
                    PresetField(title: "Часовой пояс", text: $options.timezone,
                                prompt: "системный", presets: Presets.timezones)
                }
                Section("Память и процессор") {
                    Picker("Режим", selection: $options.performance) {
                        ForEach(PerformanceMode.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section {
                    TextEditor(text: $proxyText)
                        .font(.body.monospaced())
                        .frame(height: 90)
                } header: {
                    Text("Прокси — по одному на строку, раздаются по кругу")
                }
                Section {
                    Toggle("Сразу запустить", isOn: $options.launchAfterCreate)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Отмена") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Создать \(options.count)") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(options.prefix.trimmed.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 660)
    }

    private func submit() {
        options.prefix = options.prefix.trimmed
        options.proxies = proxyText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
        onCreate(options)
        dismiss()
    }
}
