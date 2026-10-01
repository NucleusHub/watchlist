import NucleusUI
import SwiftUI

enum HomeTab: Int, Hashable, CaseIterable {
    case watchlist, collections
}

/// Watchlist and Collections under one header, with the search bar at the bottom (Shell's layout).
struct HomeView: View {
    @Environment(WatchlistStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @State private var tab: HomeTab = .watchlist
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var direction: CGFloat = 1

    var body: some View {
        ZStack {
            NucleusBackground()
            VStack(spacing: 0) {
                header
                ZStack {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        page(tab)
                            .id(tab)
                            .transition(.asymmetric(
                                insertion: .offset(x: 24 * direction).combined(with: .opacity),
                                removal: .offset(x: -24 * direction).combined(with: .opacity)
                            ))
                    } else {
                        SearchResults(query: query, tab: tab)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentMargins(.bottom, 84, for: .scrollContent)
                .ignoresSafeArea(.container, edges: .bottom)
                .onHorizontalSwipe(.left) { step(1) }
                .onHorizontalSwipe(.right) { step(-1) }
            }
        }
        .overlay(alignment: .bottom) {
            NucleusSearchBar(
                text: $query,
                focused: $searchFocused,
                prompt: tab == .watchlist ? "Search titles and collections" : "Search collections",
                onSubmit: {},
                onAdd: add
            )
            .padding(.bottom, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: tab) { _, _ in query = "" }
    }

    @ViewBuilder
    private func page(_ tab: HomeTab) -> some View {
        switch tab {
        case .watchlist: WatchlistTab()
        case .collections: CollectionsTab()
        }
    }

    private func add() {
        Haptics.tap()
        searchFocused = false
        navigator.present(tab == .watchlist ? .newItem(collectionID: nil) : .newCollection)
    }

    private func switchTo(_ next: HomeTab) {
        guard next != tab else { return }
        direction = next.rawValue > tab.rawValue ? 1 : -1
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.16)) { tab = next }
        }
    }

    private func step(_ offset: Int) {
        guard let next = HomeTab(rawValue: tab.rawValue + offset) else { return }
        Haptics.selection()
        switchTo(next)
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                GlassCircleButton("chart.bar.xaxis") { navigator.open(.stats) }
                    .accessibilityLabel("Statistics")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(store.items.isEmpty ? 0 : 1)
                    .disabled(store.items.isEmpty)

                NucleusSegmented(selection: Binding(get: { tab }, set: switchTo), items: [
                    (HomeTab.watchlist, "Watchlist"),
                    (HomeTab.collections, "Collections"),
                ])
                .fixedSize()

                GlassCircleButton("gearshape") { navigator.open(.settings) }
                    .accessibilityLabel("Settings")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Text(stats)
                .font(.system(size: 12))
                .foregroundStyle(Nucleus.secondaryText)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var stats: String {
        let items = store.document.items
        let watching = items.filter { $0.status == .watching }.count
        let done = items.filter(\.isCompleted).count
        return String(localized: "\(items.count) titles · \(watching) watching · \(done) watched")
    }
}

/// What the search bar finds: collections by name and titles by title or notes.
struct SearchResults: View {
    let query: String
    let tab: HomeTab
    @Environment(WatchlistStore.self) private var store
    @Environment(Navigator.self) private var navigator

    private var needle: String { query.trimmingCharacters(in: .whitespaces) }

    private var collections: [WatchCollection] {
        store.collections.filter { $0.name.localizedCaseInsensitiveContains(needle) }
    }

    private var items: [Item] {
        guard tab == .watchlist else { return [] }
        return Array(store.items.filter {
            $0.title.localizedCaseInsensitiveContains(needle) || $0.notes.localizedCaseInsensitiveContains(needle)
        }.prefix(60))
    }

    var body: some View {
        List {
            if !collections.isEmpty {
                Section {
                    ForEach(collections) { col in
                        Button { navigator.open(.collection(col.id)) } label: {
                            HStack(spacing: 12) {
                                CollectionCover(collection: col)
                                    .frame(width: 52, height: 52)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: col.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Nucleus.primaryText)
                                    Text("\(store.members(of: col.id).count) titles").font(.system(size: 13)).foregroundStyle(Nucleus.secondaryText)
                                }
                                Spacer()
                                Chevron()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(NucleusRowButtonStyle())
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear.nucleusGlass(cornerRadius: 18).padding(.horizontal, 16).padding(.vertical, 4))
                        .listRowSeparator(.hidden)
                    }
                } header: { sectionHeader("Collections") }
            }
            if !items.isEmpty {
                Section {
                    ForEach(items) { item in
                        ItemRow(item: item)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear.nucleusGlass(cornerRadius: 20).padding(.horizontal, 16).padding(.vertical, 6))
                            .listRowSeparator(.hidden)
                    }
                } header: { sectionHeader("Titles") }
            }
            if collections.isEmpty && items.isEmpty {
                NucleusEmptyState("magnifyingglass", title: "No matches", message: "Nothing here matches “\(needle)”.")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(Nucleus.secondaryText)
            .padding(.horizontal, 4)
    }
}
