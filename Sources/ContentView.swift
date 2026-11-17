import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ProfileStore
    @EnvironmentObject private var launcher: ChromeLauncher
    @State private var selection = Set<UUID>()
    @State private var search = ""
    @State private var showBatch = false
    @State private var confirmDelete = false
    @AppStorage("tileWindows") private var tileWindows = true
    @AppStorage("windowBadges") private var windowBadges = true
    @AppStorage("autoFreezeMinutes") private var autoFreezeMinutes = AutoFreezer.defaultMinutes

    private var visible: [BrowserProfile] {
        let q = search.trimmed
        guard !q.isEmpty else { return store.profiles }
        return store.profiles.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.notes.localizedCaseInsensitiveContains(q)
                || $0.proxy.localizedCaseInsensitiveContains(q)
        }
    }

    /// Selected profiles, or all of them when nothing is selected.
    private var targetIDs: [UUID] {
        let all = store.profiles.map(\.id)
        return selection.isEmpty ? all : all.filter(selection.contains)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle("BrowserDeck")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showBatch) {
            BatchCreateSheet { opts in
                let uas = Presets.userAgents(chromeMajor: launcher.chromeMajor).map(\.value)
                let ids = store.createBatch(opts, userAgents: uas)
                selection = Set(ids)
                if opts.launchAfterCreate { launch(ids) }
            }
        }
        .confirmationDialog(deleteTitle, isPresented: $confirmDelete) {
            Button("Удалить", role: .destructive) { deleteSelected() }
        } message: {
            Text("Папки профилей (куки, история, кеш) будут перемещены в Корзину.")
        }
        .alert("Не получилось", isPresented: errorShown) {
            Button("OK") { launcher.lastError = nil }
        } message: {
            Text(launcher.lastError ?? "")
        }
        .onAppear {
            launcher.badges.enabled = windowBadges
            launcher.autoFreezer.idleMinutes = autoFreezeMinutes
            launcher.startMonitoring(store)
        }
        .onChange(of: windowBadges) { _, on in launcher.badges.enabled = on }
        .onChange(of: autoFreezeMinutes) { _, m in launcher.autoFreezer.idleMinutes = m }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(visible, selection: $selection) { p in
            ProfileRow(profile: p, running: launcher.isRunning(p.id), usage: launcher.usage[p.id])
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            menu(for: ids)
        } primaryAction: { ids in
            launch(Array(ids))
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Поиск профилей")
        .safeAreaInset(edge: .bottom) { statusBar }
        .navigationSplitViewColumnWidth(min: 250, ideal: 300)
        .onDeleteCommand { if !selection.isEmpty { confirmDelete = true } }
    }

    @ViewBuilder
    private func menu(for ids: Set<UUID>) -> some View {
        if !ids.isEmpty {
            Button("Запустить") { launch(Array(ids)) }
            Button("Закрыть") { launcher.stop(Array(ids)) }
            if ids.contains(where: launcher.isRunning) {
                if ids.contains(where: launcher.isFrozen) {
                    Button("Разморозить") { launcher.setFrozen(Array(ids), false) }
                }
                if ids.contains(where: { launcher.isRunning($0) && !launcher.isFrozen($0) }) {
                    Button("Заморозить (0% ЦП)") { launcher.setFrozen(Array(ids), true) }
                }
            }
            Divider()
            if ids.count == 1, let id = ids.first {
                Button("Дублировать настройки") {
                    if let n = store.duplicate(id) { selection = [n] }
                }
                Button("Показать в Finder") { reveal(id) }
                Button("Очистить кеш") { store.clearCache(id) }
                    .disabled(launcher.isRunning(id))
                Divider()
            }
            Button("Удалить…", role: .destructive) {
                selection = ids
                confirmDelete = true
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(launcher.chromeApp == nil ? Color.red : Color.green)
                .frame(width: 7, height: 7)
            Text(launcher.chromeApp == nil ? "Chrome не найден" : "Chrome \(launcher.chromeVersion)")
            Spacer()
            if launcher.totalMemoryMB > 0 {
                Text(ProfileUsage.format(launcher.totalMemoryMB))
                    .help("Память всех открытых профилей")
                Text("·")
            }
            Text("открыто \(launcher.running.count) из \(store.profiles.count)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if selection.count == 1, let id = selection.first, store.profile(id) != nil {
            ProfileEditor(
                profile: binding(for: id),
                running: launcher.isRunning(id),
                usage: launcher.usage[id],
                chromeMajor: launcher.chromeMajor,
                dataPath: store.dataDir(for: id).path,
                onLaunch: { launch([id]) },
                onStop: { launcher.stop([id]) },
                onFreeze: { launcher.setFrozen([id], !launcher.isFrozen(id)) },
                onClearCache: { store.clearCache(id) },
                onReveal: { reveal(id) }
            )
            .id(id)
        } else if selection.count > 1 {
            MultiSelectionView(
                count: selection.count,
                runningCount: selection.filter(launcher.isRunning).count,
                onLaunch: { launch(targetIDs) },
                onStop: { launcher.stop(targetIDs) },
                onDelete: { confirmDelete = true }
            )
        } else {
            EmptyStateView(
                hasProfiles: !store.profiles.isEmpty,
                onNew: { selection = [store.addProfile().id] },
                onBatch: { showBatch = true }
            )
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button { selection = [store.addProfile().id] } label: {
                Label("Новый профиль", systemImage: "plus")
            }
            .help("Новый профиль")

            Button { showBatch = true } label: {
                Label("Создать несколько", systemImage: "plus.square.on.square")
            }
            .help("Создать несколько профилей сразу")

            Toggle(isOn: $tileWindows) {
                Label("Плиткой", systemImage: "square.grid.2x2")
            }
            .help("Раскладывать окна сеткой по экрану при запуске")

            Toggle(isOn: $windowBadges) {
                Label("Подписи окон", systemImage: "tag")
            }
            .help("Показывать название профиля в углу каждого окна Chrome")

            Menu {
                Picker("Замораживать окна, которыми не пользуются", selection: $autoFreezeMinutes) {
                    Text("Выключено").tag(0)
                    ForEach([2, 5, 10, 30], id: \.self) { Text("через \($0) мин").tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Автозаморозка", systemImage: autoFreezeMinutes > 0 ? "snowflake" : "snowflake.slash")
            }
            .help(autoFreezeMinutes > 0
                  ? "Неиспользуемые окна замораживаются через \(autoFreezeMinutes) мин"
                  : "Автозаморозка выключена")

            Button { launch(targetIDs) } label: {
                Label("Запустить", systemImage: "play.fill")
            }
            .disabled(store.profiles.isEmpty)
            .help("Запустить выбранные (или все, если ничего не выбрано)")

            Button { launcher.stop(targetIDs) } label: {
                Label("Закрыть", systemImage: "stop.fill")
            }
            .disabled(launcher.running.isEmpty)
            .help("Закрыть выбранные (или все, если ничего не выбрано)")
        }
    }

    // MARK: Actions

    private func launch(_ ids: [UUID]) {
        let list = store.profiles.filter { ids.contains($0.id) }
        launcher.launch(list, tile: tileWindows)
        store.markLaunched(list.map(\.id))
    }

    private func deleteSelected() {
        let busy = selection.filter(launcher.isRunning)
        if !busy.isEmpty {
            launcher.lastError = "Сначала закройте открытые профили — их нельзя удалить на ходу."
            return
        }
        store.delete(selection)
        selection = []
    }

    private func reveal(_ id: UUID) {
        let dir = store.dataDir(for: id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    private func binding(for id: UUID) -> Binding<BrowserProfile> {
        Binding(
            get: { store.profile(id) ?? BrowserProfile(name: "") },
            set: { new in
                if let i = store.profiles.firstIndex(where: { $0.id == id }) { store.profiles[i] = new }
            }
        )
    }

    private var deleteTitle: String {
        selection.count == 1 ? "Удалить профиль?" : "Удалить профили (\(selection.count))?"
    }

    private var errorShown: Binding<Bool> {
        Binding(get: { launcher.lastError != nil }, set: { if !$0 { launcher.lastError = nil } })
    }
}
