import NucleusPlugins
import NucleusUI
import SwiftUI
import WatchlistPluginKit

enum HomeTab: Hashable {
    case watchlist, collections
    /// A page a plugin added, by its contribution id.
    case plugin(String)
}

/// Watchlist and Collections under one header, with the search bar at the bottom (Shell's layout).
struct HomeView: View {
    @Environment(WatchlistStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @Environment(PluginRegistry.self) private var registry
    @Environment(AppHost.self) private var host
    @State private var tab: HomeTab = .watchlist
    /// Shared by the pages and the pills, so the pill slides with the finger.
    @State private var progress = CarouselProgress()
    @State private var headerWidth: CGFloat = 0
    @State private var pillsWidth: CGFloat = 0
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack {
            NucleusBackground()
            VStack(spacing: 0) {
                header
                ZStack {
                    // The pages stay loaded under the search results, so closing a search doesn't rebuild them.
                    pager
                        .opacity(searching ? 0 : 1)
                        .allowsHitTesting(!searching)
                    if searching {
                        SearchResults(query: query, tab: tab)
                            .contentMargins(.bottom, 84, for: .scrollContent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .overlay(alignment: .bottom) {
            NucleusSearchBar(
                text: $query,
                focused: $searchFocused,
                prompt: tab == .collections ? "Search collections" : "Search titles and collections",
                onSubmit: {},
                onAdd: add
            )
            .padding(.bottom, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: tab) { _, _ in query = "" }
        .onAppear { if let id = DebugLaunch.homeTab, tabs.contains(.plugin(id)) { tab = .plugin(id) } }
        // A plugin turned off while its tab was open.
        .onChange(of: tabs) { _, now in if !now.contains(tab) { tab = .watchlist } }
    }

    /// Every page side by side and always loaded; it follows the finger and settles on a page.
    private var pager: some View {
        PagedCarousel(tabs, selection: Binding(get: { tab }, set: { next in
            guard next != tab else { return }
            Haptics.selection()
            tab = next
        }), progress: progress) { t in
            page(t).contentMargins(.bottom, 84, for: .scrollContent)
        }
    }

    private var pluginTabs: [PluginContribution<any PluginTab>] { registry.contributions(to: .homeTabs) }

    /// Plugin tabs on the left, Watchlist in the middle where Home opens, Collections on the right.
    private var tabs: [HomeTab] { pluginTabs.map { .plugin($0.id) } + [.watchlist, .collections] }

    @ViewBuilder
    private func page(_ tab: HomeTab) -> some View {
        switch tab {
        case .watchlist: WatchlistTab()
        case .collections: CollectionsTab()
        case .plugin(let id):
            if let contribution = pluginTabs.first(where: { $0.id == id }) { contribution.value.view(host: host) }
        }
    }

    private func label(_ tab: HomeTab) -> LocalizedStringKey {
        switch tab {
        case .watchlist: "Watchlist"
        case .collections: "Collections"
        case .plugin(let id): LocalizedStringKey(pluginTabs.first { $0.id == id }?.value.title ?? id)
        }
    }

    private func add() {
        Haptics.tap()
        searchFocused = false
        navigator.present(tab == .collections ? .newCollection : .newItem(collectionID: nil))
    }

    /// A tapped pill slides the pages there.
    private func switchTo(_ next: HomeTab) {
        guard next != tab else { return }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) { tab = next }
    }

    private var header: some View {
        VStack(spacing: 10) {
            // Everything on one line when it fits; otherwise the buttons go above the pills, with the title
            // count between them. Decided from widths that don't depend on which layout is showing.
            if headerWidth == 0 || pillsWidth + leadingWidth * 2 <= headerWidth {
                HStack(spacing: 0) {
                    leadingButtons.frame(maxWidth: .infinity, alignment: .leading)
                    pills.fixedSize()
                    settingsButton.frame(maxWidth: .infinity, alignment: .trailing)
                }
                statsLine
            } else {
                HStack(spacing: 8) {
                    leadingButtons
                    statsLine.frame(maxWidth: .infinity)
                    settingsButton.frame(width: leadingWidth, alignment: .trailing)
                }
                pills.fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background {
            // A still copy of the pills, measured for their natural width whatever the layout.
            SlidingSegmented(selection: .constant(tab), items: tabs.map { ($0, label($0)) })
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pillsWidth = $0 }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width - 32 } action: { headerWidth = $0 }
    }

    private var statsLine: some View {
        Text(stats)
            .font(.system(size: 12))
            .foregroundStyle(Nucleus.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .contentTransition(.numericText())
    }

    private var pills: some View {
        SlidingSegmented(selection: Binding(get: { tab }, set: switchTo), items: tabs.map { ($0, label($0)) }, progress: progress)
    }

    private var headerButtons: [PluginContribution<HeaderButton>] { registry.contributions(to: .headerButtons) }

    /// 40 pt buttons 8 pt apart; never narrower than one, so the pills stay centred.
    private var leadingWidth: CGFloat {
        let count = (store.items.isEmpty ? 0 : 1) + headerButtons.count
        return max(40, CGFloat(count) * 40 + CGFloat(max(0, count - 1)) * 8)
    }

    private var leadingButtons: some View {
        HStack(spacing: 8) {
            if !store.items.isEmpty {
                GlassCircleButton("chart.bar.xaxis") { navigator.open(.stats) }
                    .accessibilityLabel("Statistics")
            }
            ForEach(headerButtons, id: \.id) { button in
                GlassCircleButton(button.value.symbol) { host.open(.page(id: button.value.pageID, argument: "")) }
                    .accessibilityLabel(Text(LocalizedStringKey(button.value.title)))
            }
        }
        .frame(width: leadingWidth, alignment: .leading)
    }

    private var settingsButton: some View {
        GlassCircleButton("gearshape") { navigator.open(.settings) }
            .accessibilityLabel("Settings")
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
        guard tab != .collections else { return [] }
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
