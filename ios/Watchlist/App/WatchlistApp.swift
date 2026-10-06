import AnimeSourcePlugin
import JumpBackInPlugin
import CastAndCrewPlugin
import DiscoverPlugin
import NewsPlugin
import NucleusPlugins
import NucleusUI
import SwiftUI

@main
struct WatchlistApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var store: WatchlistStore
    @State private var preferences: Preferences
    @State private var auth: NucleusID
    @State private var sync: CloudSync
    @State private var navigator: Navigator
    @State private var plugins: PluginRegistry
    @State private var host: AppHost
    private let watch: PhoneWatchBridge

    init() {
        let store = WatchlistStore()
        let preferences = Preferences()
        Migration.dropLeftoverSession(store: store)
        Migration.run(store: store, preferences: preferences)
        DebugLaunch.prepare(store: store, preferences: preferences)
        let auth = NucleusID()
        _store = State(initialValue: store)
        _preferences = State(initialValue: preferences)
        _auth = State(initialValue: auth)
        _sync = State(initialValue: CloudSync(store: store, auth: auth))
        // Plugins are compiled in; the registry checks them and honours the person's switches.
        let plugins = PluginRegistry(app: "watchlist")
        plugins.install(AnimeSourcePlugin())
        plugins.install(JumpBackInPlugin())
        plugins.install(CastAndCrewPlugin())
        plugins.install(DiscoverPlugin())
        plugins.install(NewsPlugin())
        _plugins = State(initialValue: plugins)
        let navigator = Navigator()
        _navigator = State(initialValue: navigator)
        _host = State(initialValue: AppHost(store: store, navigator: navigator, registry: plugins))
        watch = PhoneWatchBridge(store: store)
        Haptics.warmUp()
        FrameMonitor.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(preferences)
                .environment(auth)
                .environment(sync)
                .environment(navigator)
                .environment(plugins)
                .environment(host)
                .preferredColorScheme(preferences.appearance.colorScheme)
                .tint(Nucleus.accent)
        }
    }
}

/// Launch arguments for UI tests and screenshots. Debug builds only.
enum DebugLaunch {
    /// A trailer on every title, started a few seconds after the page opens: `-playTrailer [youtubeKey]`.
    static var playTrailer: String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-playTrailer") else { return nil }
        return i + 1 < args.count && !args[i + 1].hasPrefix("-") ? args[i + 1] : "Way9Dexny3w"
        #else
        nil
        #endif
    }

    /// Canned cast, crew and person pages, without a TMDb key.
    static var samplePeople: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-samplePeople")
        #else
        false
        #endif
    }

    /// Opens Home on a plugin's tab: `-tab discover`.
    static var homeTab: String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-tab"), i + 1 < args.count else { return nil }
        return args[i + 1]
        #else
        nil
        #endif
    }

    static var skipWelcome: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-skipWelcome")
        #else
        false
        #endif
    }

    @MainActor
    static func prepare(store: WatchlistStore, preferences: Preferences) {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-resetAll") {
            store.replace(with: WatchlistDocument(), silent: true)
            preferences.hasSeenWelcome = false
            preferences.hasSeenTour = false
            preferences.appearance = .dark
            preferences.gridStyle = .small
            NucleusSession.clear()
            SyncState.clear()
        }
        if args.contains("-sampleData"), store.document.isEmpty {
            store.replace(with: SampleData.document, silent: true)
        }
        // Plugin sections only show with a key; the canned people don't need a real one.
        if args.contains("-samplePeople") || args.contains("-sampleDiscover"), store.settings.tmdbApiKey.isEmpty { store.updateSettings { $0.tmdbApiKey = "debug" } }
        if args.contains("-animeSource") { store.updateSettings { $0.searchSources = ["tmdb", "kitsu-anime"] } }
        if args.contains("-sampleJump") {
            for (n, item) in store.items.filter({ !$0.isCompleted }).prefix(3).enumerated() {
                store.updateItem(item.id) {
                    $0.playback = Playback(url: "https://example.com/watch/\(n)", position: Double(900 + n * 1500), duration: 6000)
                    $0.set("lastWatchedAt", .string(Timestamp.string(Date().addingTimeInterval(Double(-n * 3600)))))
                }
            }
        }
        if let i = args.firstIndex(of: "-appearance"), i + 1 < args.count {
            preferences.appearance = AppearanceMode(rawValue: args[i + 1]) ?? .dark
        }
        if let i = args.firstIndex(of: "-grid"), i + 1 < args.count, let style = GridStyle(rawValue: args[i + 1]) {
            preferences.gridStyle = style
        }
        #endif
    }

    @MainActor
    static func route(_ navigator: Navigator, store: WatchlistStore) {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-route"), i + 1 < args.count else { return }
        switch args[i + 1] {
        case "settings": navigator.path = [.settings]
        case "stats": navigator.path = [.stats]
        case "sources": navigator.path = [.settings, .searchSources]
        case "plugins": navigator.path = [.settings, .plugins]
        case "dna": navigator.path = [.settings, .movieDNA]
        case "news": navigator.path = [.pluginPage(id: "news", argument: "")]
        case "person": navigator.path = [.pluginPage(id: "person", argument: "137427")]
        case "item": if let first = store.items.first { navigator.path = [.item(first.id)] }
        case "collection": if let first = store.collections.first { navigator.path = [.collection(first.id)] }
        case "add": navigator.sheet = .newItem(collectionID: nil)
        case "edit": if let first = store.items.first { navigator.sheet = .editItem(first.id) }
        case "seasons": if let show = store.items.first(where: \.isShow) { navigator.sheet = .seasons(show.id) }
        case "tour": navigator.sheet = .tour
        default: break
        }
        #endif
    }
}
