import Foundation

/// A record stored as its JSON object, with typed accessors on top.
protocol JSONRecord: Codable, Hashable, Identifiable {
    var raw: [String: JSONValue] { get set }
    init(raw: [String: JSONValue])
}

extension JSONRecord {
    init(from decoder: Decoder) throws {
        self.init(raw: try [String: JSONValue](from: decoder))
    }

    func encode(to encoder: Encoder) throws { try raw.encode(to: encoder) }

    var id: String { raw["_id"]?.string ?? "" }
    var createdAt: String? { raw["createdAt"]?.string }
    var updatedAt: String? {
        get { raw["updatedAt"]?.string }
        set { raw["updatedAt"] = JSONValue(newValue) }
    }

    func string(_ key: String) -> String? { raw[key]?.string }
    func double(_ key: String) -> Double? { raw[key]?.double }
    func int(_ key: String) -> Int? { raw[key]?.int }
    func strings(_ key: String) -> [String] { raw[key]?.array?.compactMap(\.string) ?? [] }

    mutating func set(_ key: String, _ value: JSONValue) { raw[key] = value }
}

enum ItemType: String, CaseIterable, Codable, Sendable {
    case movie, show
}

enum WatchStatus: String, CaseIterable, Codable, Sendable {
    case planned, watching, completed
}

struct SeasonProgress: Hashable, Codable, Identifiable, Sendable {
    var seasonNumber: Int
    var name: String
    var episodeCount: Int
    var watched: Int

    var id: Int { seasonNumber }

    init(seasonNumber: Int, name: String, episodeCount: Int, watched: Int) {
        self.seasonNumber = seasonNumber
        self.name = name
        self.episodeCount = episodeCount
        self.watched = watched
    }

    init?(_ value: JSONValue) {
        guard let o = value.object else { return nil }
        seasonNumber = o["seasonNumber"]?.int ?? 0
        name = o["name"]?.string ?? ""
        episodeCount = o["episodeCount"]?.int ?? 0
        watched = o["watched"]?.int ?? 0
    }

    var json: JSONValue {
        ["seasonNumber": .number(Double(seasonNumber)), "name": .string(name),
         "episodeCount": .number(Double(episodeCount)), "watched": .number(Double(watched))]
    }
}

/// Where the in-app browser left off: the page and the position in its video.
struct Playback: Hashable, Sendable {
    var url: String
    var position: Double
    var duration: Double

    init(url: String, position: Double, duration: Double) {
        self.url = url
        self.position = position
        self.duration = duration
    }

    init?(_ value: JSONValue?) {
        guard let o = value?.object, let url = o["url"]?.string, !url.isEmpty,
              let position = o["position"]?.double, let duration = o["duration"]?.double, duration > 0 else { return nil }
        self.init(url: url, position: position, duration: duration)
    }

    var fraction: Double { min(1, max(0, position / duration)) }

    var json: JSONValue {
        ["url": .string(url), "position": .number(position.rounded()), "duration": .number(duration.rounded())]
    }
}

/// Where tapping a title opens it.
struct OpenTarget: Hashable, Codable, Sendable {
    enum Kind: String, CaseIterable, Codable, Sendable { case tmdb, csfd, google, custom }
    enum TitleFormat: String, CaseIterable, Codable, Sendable { case raw, lower, kebab, snake, pascal, camel }

    var type: Kind = .tmdb
    var customUrl: String = ""
    var titleFormat: TitleFormat = .raw

    init(type: Kind = .tmdb, customUrl: String = "", titleFormat: TitleFormat = .raw) {
        self.type = type
        self.customUrl = customUrl
        self.titleFormat = titleFormat
    }

    init?(_ value: JSONValue?) {
        guard let o = value?.object else { return nil }
        type = Kind(rawValue: o["type"]?.string ?? "") ?? .tmdb
        customUrl = o["customUrl"]?.string ?? ""
        titleFormat = TitleFormat(rawValue: o["titleFormat"]?.string ?? "") ?? .raw
    }

    var json: JSONValue {
        ["type": .string(type.rawValue), "customUrl": .string(customUrl), "titleFormat": .string(titleFormat.rawValue)]
    }
}

/// Someone added by hand to a title TMDb doesn't have.
struct CustomCredit: Hashable, Sendable {
    enum Job: String, CaseIterable, Sendable {
        case director = "Director", creator = "Creator", writer = "Writer", producer = "Producer",
             composer = "Composer", cinematographer = "Cinematographer", editor = "Editor"

        var department: String {
            switch self {
            case .director: "Directing"
            case .creator, .writer: "Writing"
            case .producer: "Production"
            case .composer: "Sound"
            case .cinematographer: "Camera"
            case .editor: "Editing"
            }
        }
    }

    var name: String
    /// The character for cast, the job for crew.
    var role: String
    var isCast: Bool
    /// Set when picked from TMDb, so their page opens.
    var personID: Int?
    var photo: String?

    init(name: String, role: String, isCast: Bool, personID: Int? = nil, photo: String? = nil) {
        self.name = name
        self.role = role
        self.isCast = isCast
        self.personID = personID
        self.photo = photo
    }

    init?(_ value: JSONValue) {
        guard let o = value.object, let name = o["name"]?.string, !name.isEmpty else { return nil }
        self.name = name
        role = o["role"]?.string ?? ""
        isCast = o["cast"]?.bool ?? true
        personID = o["personId"]?.int
        photo = o["photo"]?.string
    }

    var json: JSONValue {
        var o: [String: JSONValue] = ["name": .string(name), "role": .string(role), "cast": .bool(isCast)]
        if let personID { o["personId"] = .number(Double(personID)) }
        if let photo { o["photo"] = .string(photo) }
        return .object(o)
    }

    var department: String { isCast ? "Acting" : Job(rawValue: role)?.department ?? "Crew" }
}

struct Item: JSONRecord {
    var raw: [String: JSONValue]

    init(raw: [String: JSONValue]) { self.raw = raw }

    /// A new item with every field present, as synced documents have them.
    init(title: String, type: ItemType) {
        raw = [
            "title": .string(title), "type": .string(type.rawValue),
            "tmdbId": nil, "status": "planned", "posterUrl": nil, "tmdbRating": nil, "watchLink": nil,
            "streamingProvider": nil, "streamingLogo": nil, "rating": nil, "genres": [], "favorite": false,
            "year": nil, "runtime": nil, "seasons": nil, "episodes": nil, "showRuntime": nil,
            "openTarget": nil, "collectionIds": [], "completedAt": nil, "notes": "",
        ]
    }

    var title: String {
        get { string("title") ?? "" }
        set { set("title", .string(newValue)) }
    }

    var type: ItemType {
        get { ItemType(rawValue: string("type") ?? "") ?? .movie }
        set { set("type", .string(newValue.rawValue)) }
    }

    var status: WatchStatus {
        get { WatchStatus(rawValue: string("status") ?? "") ?? .planned }
        set { set("status", .string(newValue.rawValue)) }
    }

    var isShow: Bool { type == .show }
    var isCompleted: Bool { status == .completed }

    var favorite: Bool {
        get { raw["favorite"]?.bool ?? false }
        set { set("favorite", .bool(newValue)) }
    }

    var posterUrl: String? {
        get { string("posterUrl").flatMap { $0.isEmpty ? nil : $0 } }
        set { set("posterUrl", JSONValue(newValue)) }
    }

    var tmdbId: Int? {
        get { int("tmdbId") }
        set { set("tmdbId", JSONValue(newValue)) }
    }

    var tmdbRating: Double? {
        get { double("tmdbRating") }
        set { set("tmdbRating", JSONValue(newValue)) }
    }

    /// Your rating, 0.5–10 in half steps.
    var rating: Double? {
        get { double("rating") }
        set { set("rating", JSONValue(newValue)) }
    }

    var year: Int? {
        get { int("year") }
        set { set("year", JSONValue(newValue)) }
    }

    /// Minutes, for movies.
    var runtime: Int? {
        get { int("runtime") }
        set { set("runtime", JSONValue(newValue)) }
    }

    var seasons: Int? {
        get { int("seasons") }
        set { set("seasons", JSONValue(newValue)) }
    }

    var episodes: Int? {
        get { int("episodes") }
        set { set("episodes", JSONValue(newValue)) }
    }

    /// Total minutes for the whole show.
    var showRuntime: Int? {
        get { int("showRuntime") }
        set { set("showRuntime", JSONValue(newValue)) }
    }

    var genres: [String] {
        get { strings("genres") }
        set { set("genres", JSONValue(newValue)) }
    }

    var collectionIds: [String] {
        get { strings("collectionIds") }
        set { set("collectionIds", JSONValue(newValue)) }
    }

    var watchLink: String? {
        get { string("watchLink").flatMap { $0.isEmpty ? nil : $0 } }
        set { set("watchLink", JSONValue(newValue)) }
    }

    var streamingProvider: String? {
        get { string("streamingProvider") }
        set { set("streamingProvider", JSONValue(newValue)) }
    }

    var streamingLogo: String? {
        get { string("streamingLogo") }
        set { set("streamingLogo", JSONValue(newValue)) }
    }

    var notes: String {
        get { string("notes") ?? "" }
        set { set("notes", .string(newValue)) }
    }

    /// A description written by hand, for titles TMDb doesn't have.
    var overview: String {
        get { string("overview") ?? "" }
        set { set("overview", newValue.isEmpty ? .null : .string(newValue)) }
    }

    /// A YouTube link pasted by hand, for titles TMDb doesn't have.
    var trailerUrl: String? {
        get { string("trailerUrl").flatMap { $0.isEmpty ? nil : $0 } }
        set { set("trailerUrl", JSONValue(newValue.flatMap { $0.isEmpty ? nil : $0 })) }
    }

    /// Cast and crew entered by hand, for titles TMDb doesn't have.
    var customCredits: [CustomCredit] {
        get { raw["customCredits"]?.array?.compactMap(CustomCredit.init) ?? [] }
        set { set("customCredits", newValue.isEmpty ? .null : .array(newValue.map(\.json))) }
    }

    var openTarget: OpenTarget? {
        get { OpenTarget(raw["openTarget"]) }
        set { set("openTarget", newValue?.json ?? .null) }
    }

    /// The plugin source the title came from, e.g. `kitsu-anime`; nil for TMDb and typed-in titles.
    var source: String? {
        get { string("source").flatMap { $0.isEmpty ? nil : $0 } }
        set { set("source", JSONValue(newValue)) }
    }

    /// The last page the in-app browser was on, video or not.
    var lastPage: String? {
        get { string("lastPage").flatMap { $0.isEmpty ? nil : $0 } }
        set { set("lastPage", JSONValue(newValue)) }
    }

    /// When the browser last saved a video position for this title; what "Jump back in" sorts by.
    var lastWatchedAt: String? { string("lastWatchedAt") }

    var playback: Playback? {
        get { Playback(raw["playback"]) }
        set { set("playback", newValue?.json ?? .null) }
    }

    var seasonProgress: [SeasonProgress]? {
        get { raw["seasonProgress"]?.array.map { $0.compactMap(SeasonProgress.init) } }
        set { set("seasonProgress", newValue.map { .array($0.map(\.json)) } ?? .null) }
    }

    var completedAt: String? { string("completedAt") }
    var dateAdded: String? { string("dateAdded") ?? createdAt }

    func isIn(_ collectionID: String) -> Bool { collectionIds.contains(collectionID) }
}

struct WatchCollection: JSONRecord {
    var raw: [String: JSONValue]

    init(raw: [String: JSONValue]) { self.raw = raw }

    init(name: String) {
        raw = [
            "name": .string(name), "description": "", "coverUrl": nil, "coverItemIds": [],
            "coverCount": 4, "kind": "manual", "position": 0,
        ]
    }

    var name: String {
        get { string("name") ?? "" }
        set { set("name", .string(newValue)) }
    }

    var details: String {
        get { string("description") ?? "" }
        set { set("description", .string(newValue)) }
    }

    var coverUrl: String? {
        get { string("coverUrl").flatMap { $0.isEmpty ? nil : $0 } }
        set { set("coverUrl", JSONValue(newValue)) }
    }

    var coverItemIds: [String] {
        get { strings("coverItemIds") }
        set { set("coverItemIds", JSONValue(newValue)) }
    }

    var coverCount: Int {
        get { min(8, max(1, int("coverCount") ?? 4)) }
        set { set("coverCount", .number(Double(min(8, max(1, newValue))))) }
    }

    var position: Double { double("position") ?? 0 }

    var itemOrder: [String] {
        get { strings("itemOrder") }
        set { set("itemOrder", JSONValue(newValue)) }
    }
}

/// The settings part of the document; they sync with the rest.
struct WatchlistSettings: Codable, Hashable {
    var raw: [String: JSONValue]

    static let empty = WatchlistSettings(raw: [
        "openDefaults": nil, "searchSources": ["tmdb"], "pluginPlacements": [:], "tmdbApiKey": "", "updatedAt": nil,
    ])

    init(raw: [String: JSONValue]) { self.raw = raw }
    init(from decoder: Decoder) throws { raw = try [String: JSONValue](from: decoder) }
    func encode(to encoder: Encoder) throws { try raw.encode(to: encoder) }

    var updatedAt: String? {
        get { raw["updatedAt"]?.string }
        set { raw["updatedAt"] = JSONValue(newValue) }
    }

    var tmdbApiKey: String {
        get { raw["tmdbApiKey"]?.string ?? "" }
        set { raw["tmdbApiKey"] = .string(newValue) }
    }

    var searchSources: [String] {
        get { raw["searchSources"]?.array?.compactMap(\.string) ?? ["tmdb"] }
        set { raw["searchSources"] = JSONValue(newValue) }
    }

    func openDefault(for type: ItemType) -> OpenTarget? {
        OpenTarget(raw["openDefaults"]?.object?[type.rawValue])
    }

    mutating func setOpenDefaults(movie: OpenTarget, show: OpenTarget) {
        raw["openDefaults"] = ["movie": movie.json, "show": show.json]
    }
}
