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
    @State private var tourAfterWelcome = false
    @State private var signInAfterWelcome = false
    @State private var pendingServer: NucleusServer?
    @State private var importProblem: LocalizedStringResource?

    var body: some View {
        @Bindable var navigator = navigator
        NavigationStack(path: $navigator.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .item(let id): ItemDetailView(itemID: id)
                    case .collection(let id): CollectionDetailView(collectionID: id)
                    case .settings: SettingsView()
                    case .profile: ProfileView()
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
        // Plugins' trailers play through this hidden player.
        .trailerHost(host.trailers)
        .sheet(item: $navigator.sheet) { sheet in
            sheetView(sheet)
                .overlay { Confetti(trigger: store.celebrations) }
        }
        .overlay { Confetti(trigger: store.celebrations) }
        .fullScreenCover(item: $navigator.browser) { BrowserView(request: $0) }
        .sheet(isPresented: $showWelcome, onDismiss: {
            if signInAfterWelcome { navigator.present(.signIn(nil)) }
            else if tourAfterWelcome && !preferences.hasSeenTour { navigator.present(.tour) }
        }) {
            WelcomeView(onTour: { tourAfterWelcome = true }, onSignIn: { signInAfterWelcome = true })
                .interactiveDismissDisabled()
                .presentationDragIndicator(.hidden)
        }
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            guard preferences.shakeToReport, navigator.sheet == nil, !showWelcome else { return }
            Haptics.tap()
            navigator.present(.report)
        }
        // Links from other apps and server setups; the OAuth redirect goes to ASWebAuthenticationSession, never here.
        .onOpenURL { url in
            if url.isFileURL, url.pathExtension.lowercased() == "nucleusserver" {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                importServer { try NucleusServer.setup(fromFile: try Data(contentsOf: url)) }
                return
            }
            if url.scheme == NucleusID.callbackScheme, url.host() == "server" {
                importServer { try NucleusServer.setup(from: url) }
                return
            }
            guard let id = Navigator.linkedItemID(url), store.item(id) != nil else { return }
            navigator.sheet = nil
            navigator.browser = nil
            navigator.path = [.item(id)]
        }
        .confirmationDialog(Text("Use server \(pendingServer?.host ?? "")?"),
                            isPresented: Binding(get: { pendingServer != nil }, set: { if !$0 { pendingServer = nil } }),
                            titleVisibility: .visible, presenting: pendingServer) { server in
            Button("Use server") { navigator.present(.signIn(server)) }
        } message: { server in
            Text("\(server.origin.absoluteString) will be used for signing in.")
        }
        .alert(Text(importProblem ?? ""), isPresented: Binding(get: { importProblem != nil }, set: { if !$0 { importProblem = nil } })) {}
        .task {
            DebugLaunch.route(navigator, store: store)
            if !preferences.hasSeenWelcome && !auth.isSignedIn && !DebugLaunch.skipWelcome {
                try? await Task.sleep(for: .milliseconds(400))
                // A setup link that opened the app goes first.
                if pendingServer == nil && navigator.sheet == nil { showWelcome = true }
            }
            await auth.validate()
            await sync.syncNow()
        }
        // The synced accent, from this device or another; a device that never picked one keeps what it shows.
        .onChange(of: store.settings.accent, initial: true) { _, accent in
            if let accent { NucleusTheme.shared.app = accent }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            // validate() also picks up an account theme changed elsewhere.
            case .active: Task { await auth.validate(); await sync.syncNow() }
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
        case .tour: TourView().presentationDragIndicator(.hidden)
        case .signIn(let prefill, let mode): ServerSignInSheet(prefill: prefill, mode: mode)
        }
    }

    /// A setup link or file from the server's administrator: confirm, then sign in with it filled in.
    private func importServer(_ read: () throws -> NucleusServer) {
        guard !auth.isSignedIn else {
            Haptics.error()
            importProblem = "Sign out to switch servers."
            return
        }
        do {
            pendingServer = try read()
        } catch {
            Haptics.error()
            importProblem = (error as? ServerProblem ?? .badSetup).message
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
