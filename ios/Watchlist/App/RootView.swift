import NucleusUI
import SwiftUI

struct RootView: View {
    @Environment(WatchlistStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(NucleusID.self) private var auth
    @Environment(CloudSync.self) private var sync
    @Environment(Navigator.self) private var navigator
    @Environment(AppHost.self) private var host
    @Environment(\.scenePhase) private var scenePhase
    @State private var showWelcome = false

    var body: some View {
        @Bindable var navigator = navigator
        NavigationStack(path: $navigator.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .item(let id): ItemDetailView(itemID: id)
                    case .collection(let id): CollectionDetailView(collectionID: id)
                    case .settings: SettingsView()
                    case .stats: StatsView()
                    case .openDefaults: OpenDefaultsView()
                    case .searchSources: SearchSourcesView()
                    case .plugins: PluginsView()
                    case .movieDNA: MovieDNAView()
                    case .preview(let type, let id): TitlePreviewView(type: type, tmdbID: id)
                    case .pluginPage(let id, let argument): PluginPageView(id: id, argument: argument)
                    }
                }
        }
        .sheet(item: $navigator.sheet) { sheet in
            sheetView(sheet)
                .overlay { Confetti(trigger: store.celebrations) }
        .background {
            // Plugins' trailers play through this hidden player.
            TrailerPlayerHost(player: host.trailers).frame(width: 2, height: 2).opacity(0.01).accessibilityHidden(true)
        }
        }
        .overlay { Confetti(trigger: store.celebrations) }
        .fullScreenCover(item: $navigator.browser) { BrowserView(request: $0) }
        .sheet(isPresented: $showWelcome) {
            WelcomeView()
                .interactiveDismissDisabled()
                .presentationDragIndicator(.hidden)
        }
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            guard preferences.shakeToReport, navigator.sheet == nil, !showWelcome else { return }
            Haptics.tap()
            navigator.present(.report)
        }
        .task {
            DebugLaunch.route(navigator, store: store)
            if !preferences.hasSeenWelcome && !auth.isSignedIn && !DebugLaunch.skipWelcome {
                try? await Task.sleep(for: .milliseconds(400))
                showWelcome = true
            }
            await auth.validate()
            await sync.syncNow()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await sync.syncNow() }
            case .background:
                store.flush()
                sync.flushInBackground()
            default: break
            }
        }
    }

    @ViewBuilder
    private func sheetView(_ sheet: Sheet) -> some View {
        switch sheet {
        case .newItem(let collectionID): ItemEditor(itemID: nil, collectionID: collectionID)
        case .editItem(let id): ItemEditor(itemID: id)
        case .manageCollections(let id): ManageCollectionsSheet(itemID: id).presentationDetents([.medium, .large])
        case .seasons(let id): SeasonProgressSheet(itemID: id)
        case .newCollection: CollectionEditor(collectionID: nil)
        case .editCollection(let id): CollectionEditor(collectionID: id)
        case .addItems(let id): AddItemsSheet(collectionID: id)
        case .reorder(let id): ReorderSheet(collectionID: id)
        case .report: ReportSheet()
        }
    }
}

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

// Shakes reach the key window only; SwiftUI has no hook for them.
extension UIWindow {
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { NotificationCenter.default.post(name: .deviceDidShake, object: nil) }
        super.motionEnded(motion, with: event)
    }
}
