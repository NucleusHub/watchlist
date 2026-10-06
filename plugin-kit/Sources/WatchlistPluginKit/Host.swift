import NucleusPlugins
import SwiftUI

/// Someone in a title's credits.
public struct PluginCredit: Identifiable, Hashable, Sendable {
    public let personID: Int
    public let name: String
    /// The character for cast, the job for crew.
    public let role: String
    /// TMDb's department: "Acting", "Directing", "Writing", "Production", ...
    public let department: String
    public let photoURL: URL?

    public var id: String { "\(personID)-\(department)-\(role)" }

    public init(personID: Int, name: String, role: String, department: String, photoURL: URL?) {
        self.personID = personID
        self.name = name
        self.role = role
        self.department = department
        self.photoURL = photoURL
    }
}

public struct PluginCredits: Hashable, Sendable {
    /// In billing order.
    public let cast: [PluginCredit]
    /// The key jobs (director, creator, writers) first.
    public let crew: [PluginCredit]

    public init(cast: [PluginCredit], crew: [PluginCredit]) {
        self.cast = cast
        self.crew = crew
    }
}

/// A title in a person's filmography.
public struct PluginPersonCredit: Identifiable, Hashable, Sendable {
    public let titleID: Int
    public let kind: MediaKind
    public let title: String
    /// `yyyy-mm-dd`, or nil when TMDb doesn't know yet.
    public let date: String?
    public let posterURL: URL?
    public let role: String
    public let department: String
    /// How many TMDb votes the title has; a stand-in for how well known it is.
    public let voteCount: Int

    public var id: String { "\(kind.rawValue)-\(titleID)-\(department)-\(role)" }
    public var year: String? { date.flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil } }

    public init(titleID: Int, kind: MediaKind, title: String, date: String?, posterURL: URL?, role: String, department: String, voteCount: Int) {
        self.titleID = titleID
        self.kind = kind
        self.title = title
        self.date = date
        self.posterURL = posterURL
        self.role = role
        self.department = department
        self.voteCount = voteCount
    }
}

public struct PluginPerson: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let biography: String
    /// The department TMDb lists them under, e.g. "Acting".
    public let knownFor: String?
    public let birthday: String?
    public let deathday: String?
    public let birthplace: String?
    public let photoURL: URL?
    public let wikidataID: String?
    public let imdbID: String?
    public let credits: [PluginPersonCredit]

    public init(id: Int, name: String, biography: String, knownFor: String?, birthday: String?, deathday: String?,
                birthplace: String?, photoURL: URL?, wikidataID: String?, imdbID: String?, credits: [PluginPersonCredit]) {
        self.id = id
        self.name = name
        self.biography = biography
        self.knownFor = knownFor
        self.birthday = birthday
        self.deathday = deathday
        self.birthplace = birthplace
        self.photoURL = photoURL
        self.wikidataID = wikidataID
        self.imdbID = imdbID
        self.credits = credits
    }
}

/// Where a plugin can send the person.
public enum HostDestination: Hashable, Sendable {
    /// The page a plugin contributed with `PluginPageID.person`; nothing happens without one.
    case person(Int)
    /// The title's page if it's in the library, otherwise a preview it can be added from.
    case title(MediaKind, Int)
    /// Another page of the same plugin.
    case page(id: String, argument: String)
    /// A web page: the default browser, or the app's own when `inApp`.
    case web(URL, inApp: Bool)
}

/// What the app does for plugins: TMDb data with the person's key, navigation, the library and MovieDNA.
@MainActor
public protocol WatchlistHost: AnyObject, Sendable {
    func credits(_ kind: MediaKind, tmdbID: Int) async throws -> PluginCredits
    func person(_ id: Int) async throws -> PluginPerson
    func open(_ destination: HostDestination)
    func isFollowing(_ personID: Int) -> Bool
    func setFollowing(_ following: Bool, personID: Int, name: String, photoURL: URL?)
    func inLibrary(_ kind: MediaKind, tmdbID: Int) -> Bool

    /// A TMDb API response, e.g. `tmdb("/trending/all/week")`. The app adds the person's key, which plugins never see.
    func tmdb(_ path: String, query: [String: String]) async throws -> Data
    /// Whether a TMDb key is set; without one `tmdb` throws.
    var hasTMDbKey: Bool { get }
    /// The person's MovieDNA right now; `enabled` is false when they turned it off.
    var movieDNA: PluginMovieDNA { get }
    /// Everything in the watchlist, for plugins that work from the library when MovieDNA is off.
    var library: [PluginLibraryTitle] { get }
    /// Adds a TMDb title to the watchlist with its details filled in.
    func addToWatchlist(_ kind: MediaKind, tmdbID: Int) async throws
    /// Hides the title from suggestions for good and tells MovieDNA its genres were less welcome.
    func markNotInterested(_ kind: MediaKind, tmdbID: Int, title: String, genres: [String])
    /// Plays a YouTube trailer in the full-screen player; `prepare` loads it ahead of a tap.
    func playTrailer(_ youTubeKey: String)
    func prepareTrailer(_ youTubeKey: String)
    /// The trailer that was asked for and hasn't started yet.
    var trailerLoadingKey: String? { get }
    /// What other plugins add to a person's page (news mentions, ...), for the plugin that draws that page.
    func personSections(personID: Int, name: String) -> AnyView
}

/// One thing in someone's MovieDNA.
public struct PluginTrait: Hashable, Sendable {
    public let name: String
    /// -100 … 100.
    public let strength: Double

    public init(name: String, strength: Double) {
        self.name = name
        self.strength = strength
    }
}

public struct PluginTitleTrait: Hashable, Sendable {
    public let kind: MediaKind
    public let tmdbID: Int
    public let name: String
    public let strength: Double

    public init(kind: MediaKind, tmdbID: Int, name: String, strength: Double) {
        self.kind = kind
        self.tmdbID = tmdbID
        self.name = name
        self.strength = strength
    }
}

public struct PluginPersonTrait: Hashable, Sendable {
    public let personID: Int
    public let name: String
    public let strength: Double
    public let followed: Bool

    public init(personID: Int, name: String, strength: Double, followed: Bool) {
        self.personID = personID
        self.name = name
        self.strength = strength
        self.followed = followed
    }
}

/// A read-only copy of the person's MovieDNA, strongest first in each list.
public struct PluginMovieDNA: Hashable, Sendable {
    public let enabled: Bool
    public let genres: [PluginTrait]
    public let titles: [PluginTitleTrait]
    public let people: [PluginPersonTrait]
    /// `movie:603`, `show:1399`: titles the person said no to.
    public let notInterested: Set<String>

    public init(enabled: Bool, genres: [PluginTrait], titles: [PluginTitleTrait], people: [PluginPersonTrait], notInterested: Set<String>) {
        self.enabled = enabled
        self.genres = genres
        self.titles = titles
        self.people = people
        self.notInterested = notInterested
    }

    public static func key(_ kind: MediaKind, _ tmdbID: Int) -> String { "\(kind.rawValue):\(tmdbID)" }
}

/// A title in the watchlist, as plugins see it.
public struct PluginLibraryTitle: Hashable, Sendable {
    public let kind: MediaKind
    public let tmdbID: Int?
    public let title: String
    public let genres: [String]
    /// 0.5 … 10, nil when unrated.
    public let rating: Double?
    public let favorite: Bool
    public let isCompleted: Bool
    /// When it was finished, or last changed when there's no finish date.
    public let finishedAt: Date?

    public init(kind: MediaKind, tmdbID: Int?, title: String, genres: [String], rating: Double?, favorite: Bool,
                isCompleted: Bool, finishedAt: Date?) {
        self.kind = kind
        self.tmdbID = tmdbID
        self.title = title
        self.genres = genres
        self.rating = rating
        self.favorite = favorite
        self.isCompleted = isCompleted
        self.finishedAt = finishedAt
    }
}

/// What the app hands a section on a title's page.
@MainActor
public struct ItemSectionContext {
    public let kind: MediaKind
    /// Nil for titles TMDb doesn't have.
    public let tmdbID: Int?
    public let title: String
    public let host: any WatchlistHost
    /// False inside a sheet (adding a title), where opening another page would lose what's being entered.
    public let canNavigate: Bool
    /// People entered by hand for a title TMDb doesn't have; person id 0 means they aren't on TMDb.
    public let credits: PluginCredits?

    public init(kind: MediaKind, tmdbID: Int?, title: String, host: any WatchlistHost, canNavigate: Bool = true, credits: PluginCredits? = nil) {
        self.kind = kind
        self.tmdbID = tmdbID
        self.title = title
        self.host = host
        self.canNavigate = canNavigate
        self.credits = credits
    }
}

/// A section a plugin adds to a title's page. Return an empty view to show nothing.
public protocol ItemSection: Sendable {
    var id: String { get }
    @MainActor func view(_ context: ItemSectionContext) -> AnyView
}

/// A full page a plugin adds, opened through `HostDestination`.
public protocol PluginPage: Sendable {
    @MainActor func view(argument: String, host: any WatchlistHost) -> AnyView
}

/// Page ids the app itself opens.
public enum PluginPageID {
    /// Answers `HostDestination.person`; the argument is the TMDb person id.
    public static let person = "person"
}

public extension ExtensionPoint where Contribution == any ItemSection {
    static var itemSections: Self { .init("watchlist.itemSections") }
}

public extension ExtensionPoint where Contribution == any PluginPage {
    static var pages: Self { .init("watchlist.pages") }
}

/// A page of its own on Home, next to Watchlist and Collections.
public protocol PluginTab: Sendable {
    /// The segment's label, in English; the app translates it.
    var title: String { get }
    @MainActor func view(host: any WatchlistHost) -> AnyView
}

public extension ExtensionPoint where Contribution == any PluginTab {
    static var homeTabs: Self { .init("watchlist.homeTabs") }
}

/// A round button in the Home header that opens one of the plugin's pages.
public struct HeaderButton: Sendable {
    public let symbol: String
    /// For VoiceOver, in English; the app translates it.
    public let title: String
    public let pageID: String

    public init(symbol: String, title: String, pageID: String) {
        self.symbol = symbol
        self.title = title
        self.pageID = pageID
    }
}

public extension ExtensionPoint where Contribution == HeaderButton {
    static var headerButtons: Self { .init("watchlist.headerButtons") }
}

/// What a plugin gets to add a section to someone's page.
@MainActor
public struct PersonSectionContext {
    public let personID: Int
    public let name: String
    public let host: any WatchlistHost

    public init(personID: Int, name: String, host: any WatchlistHost) {
        self.personID = personID
        self.name = name
        self.host = host
    }
}

/// A section on a person's page; return an empty view to show nothing.
public protocol PersonSection: Sendable {
    @MainActor func view(_ context: PersonSectionContext) -> AnyView
}

public extension ExtensionPoint where Contribution == any PersonSection {
    static var personSections: Self { .init("watchlist.personSections") }
}
