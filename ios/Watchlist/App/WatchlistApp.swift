import NucleusUI
import SwiftUI

@main
struct WatchlistApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var store: WatchlistStore
    @State private var preferences: Preferences
    @State private var auth: NucleusID
    @State private var sync: CloudSync
    @State private var navigator = Navigator()
    private let watch: PhoneWatchBridge

    init() {
        let store = WatchlistStore()
        let preferences = Preferences()
        Migration.run(store: store, preferences: preferences)
        DebugLaunch.prepare(store: store, preferences: preferences)
        let auth = NucleusID()
        _store = State(initialValue: store)
        _preferences = State(initialValue: preferences)
        _auth = State(initialValue: auth)
        _sync = State(initialValue: CloudSync(store: store, auth: auth))
        watch = PhoneWatchBridge(store: store)
        Haptics.warmUp()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(preferences)
                .environment(auth)
                .environment(sync)
                .environment(navigator)
                .preferredColorScheme(preferences.appearance.colorScheme)
                .tint(Nucleus.accent)
        }
    }
}

/// Launch arguments for UI tests and screenshots. Debug builds only.
enum DebugLaunch {
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
            preferences.appearance = .dark
            preferences.gridStyle = .small
            NucleusSession.clear()
            SyncState.clear()
        }
        if args.contains("-sampleData"), store.document.isEmpty {
            store.replace(with: SampleData.document, silent: true)
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
        case "item": if let first = store.items.first { navigator.path = [.item(first.id)] }
        case "collection": if let first = store.collections.first { navigator.path = [.collection(first.id)] }
        case "add": navigator.sheet = .newItem(collectionID: nil)
        case "edit": if let first = store.items.first { navigator.sheet = .editItem(first.id) }
        case "seasons": if let show = store.items.first(where: \.isShow) { navigator.sheet = .seasons(show.id) }
        default: break
        }
        #endif
    }
}
