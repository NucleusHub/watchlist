import Foundation
import Observation

enum Route: Hashable {
    case item(String)
    case collection(String)
    case settings
    case stats
    case openDefaults
    case searchSources
    case plugins
    case movieDNA
    /// A TMDb title that isn't in the library, with a way to add it.
    case preview(ItemType, Int)
    /// A page a plugin contributed.
    case pluginPage(id: String, argument: String)
}

/// A page for the in-app browser; a saved playback of the item reopens instead of `home`.
struct BrowserRequest: Identifiable {
    let id = UUID()
    let home: URL
    let itemID: String?
}

/// A sheet over everything else. One at a time, as iOS presents them.
enum Sheet: Identifiable, Hashable {
    case newItem(collectionID: String?)
    case editItem(String)
    case manageCollections(String)
    case seasons(String)
    case newCollection
    case editCollection(String)
    case addItems(String)
    case reorder(String)
    case report
    case tour

    var id: Self { self }
}

/// Where the app is: the pushed pages and the open sheet. Any view can open an editor through it.
@MainActor
@Observable
final class Navigator {
    var path: [Route] = []
    var sheet: Sheet?
    var browser: BrowserRequest?

    func open(_ route: Route) { path.append(route) }
    func present(_ sheet: Sheet) { self.sheet = sheet }
    func browse(_ url: URL, item: Item? = nil) { browser = BrowserRequest(home: url, itemID: item?.id) }
}
