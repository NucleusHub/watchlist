import Foundation

/// Credits and videos of a title, fetched in one request.
extension TMDb {
    struct Credit: Identifiable, Hashable, Sendable {
        let personID: Int
        let name: String
        /// The character for cast, the job for crew.
        let role: String
        /// "Acting", "Directing", "Writing", "Production", ...
        let department: String
        let profilePath: String?
        /// TMDb's billing order; crew sort after cast.
        let order: Int

        var id: String { "\(personID)-\(department)-\(role)" }
        var photoURL: URL? { profilePath.flatMap { URL(string: "https://image.tmdb.org/t/p/w185\($0)") } }
    }

    struct Video: Identifiable, Hashable, Sendable {
        let key: String
        let name: String
        /// "Trailer", "Teaser", "Clip", "Featurette", ...
        let kind: String
        let official: Bool
        let publishedAt: String?

        var id: String { key }
        var url: URL? { URL(string: "https://www.youtube.com/watch?v=\(key)") }
        var thumbnailURL: URL? { URL(string: "https://img.youtube.com/vi/\(key)/hqdefault.jpg") }

        /// The video id in a YouTube link: `watch?v=`, `youtu.be/`, `/embed/`, `/shorts/` or `/live/`.
        static func youTubeKey(_ link: String) -> String? {
            guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)), let host = url.host?.lowercased() else { return nil }
            let key: String?
            if host.hasSuffix("youtu.be") {
                key = url.pathComponents.dropFirst().first
            } else if host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com") {
                let parts = url.pathComponents
                if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value {
                    key = v
                } else if parts.count >= 3, ["embed", "shorts", "live", "v"].contains(parts[1]) {
                    key = parts[2]
                } else {
                    key = nil
                }
            } else {
                key = nil
            }
            guard let key, key.count >= 6, key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
            return key
        }
    }

    struct Extras: Hashable, Sendable {
        /// TMDb's description of the title.
        var overview = ""
        var cast: [Credit] = []
        var crew: [Credit] = []
        /// Trailers first, official before fan uploads, newest first within each.
        var videos: [Video] = []
    }

    /// Shows use `aggregate_credits`, which covers every season rather than only the latest.
    func extras(_ id: Int, type: ItemType) async throws -> Extras {
        let credits = type == .movie ? "credits" : "aggregate_credits"
        let path = type == .movie ? "/movie/\(id)" : "/tv/\(id)"
        let data = try await get(path, ["append_to_response": "\(credits),videos", "include_video_language": "en,null"])
        return Self.extras(data.object ?? [:], creditsKey: credits)
    }

    static func extras(_ detail: [String: JSONValue], creditsKey: String) -> Extras {
        let credits = detail[creditsKey]?.object ?? [:]
        let cast = (credits["cast"]?.array ?? []).compactMap(\.object).compactMap { c -> Credit? in
            guard let id = c["id"]?.int, let name = c["name"]?.string else { return nil }
            // Aggregate credits list roles per season; the one with most episodes names the part.
            let role = c["character"]?.string
                ?? c["roles"]?.array?.compactMap(\.object).max { ($0["episode_count"]?.int ?? 0) < ($1["episode_count"]?.int ?? 0) }?["character"]?.string
            return Credit(personID: id, name: name, role: role ?? "", department: "Acting",
                          profilePath: c["profile_path"]?.string, order: c["order"]?.int ?? 999)
        }
        let crew = (credits["crew"]?.array ?? []).compactMap(\.object).compactMap { c -> Credit? in
            guard let id = c["id"]?.int, let name = c["name"]?.string else { return nil }
            let job = c["job"]?.string ?? c["jobs"]?.array?.first?.object?["job"]?.string ?? ""
            let department = c["department"]?.string ?? ""
            return Credit(personID: id, name: name, role: job, department: department,
                          profilePath: c["profile_path"]?.string, order: crewRank(job) * 1000)
        }
        let videos = (detail["videos"]?.object?["results"]?.array ?? []).compactMap(\.object).compactMap { v -> Video? in
            guard v["site"]?.string == "YouTube", let key = v["key"]?.string, !key.isEmpty else { return nil }
            return Video(key: key, name: v["name"]?.string ?? "", kind: v["type"]?.string ?? "",
                         official: v["official"]?.bool ?? false, publishedAt: v["published_at"]?.string)
        }
        return Extras(
            overview: detail["overview"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            cast: cast.sorted { $0.order < $1.order },
            crew: dedupe(crew).sorted { ($0.order, $0.name) < ($1.order, $1.name) },
            videos: videos.sorted(by: videoBefore)
        )
    }

    /// The jobs people look for first; the rest keep TMDb's order after them.
    private static func crewRank(_ job: String) -> Int {
        ["Director", "Creator", "Screenplay", "Writer", "Novel", "Producer", "Executive Producer",
         "Original Music Composer", "Director of Photography", "Editor"].firstIndex(of: job) ?? 99
    }

    /// One row per person and job; TMDb repeats crew across departments and seasons.
    private static func dedupe(_ credits: [Credit]) -> [Credit] {
        var seen = Set<String>()
        return credits.filter { seen.insert("\($0.personID)|\($0.role)").inserted }
    }

    private static func videoBefore(_ a: Video, _ b: Video) -> Bool {
        let rank = ["Trailer": 0, "Teaser": 1, "Clip": 2, "Featurette": 3]
        let ra = rank[a.kind] ?? 9, rb = rank[b.kind] ?? 9
        if ra != rb { return ra < rb }
        if a.official != b.official { return a.official }
        return (a.publishedAt ?? "") > (b.publishedAt ?? "")
    }
}

extension TMDb {
    struct PersonResult: Identifiable, Hashable, Sendable {
        let id: Int
        let name: String
        let knownFor: String
        let photoURL: URL?
    }

    func searchPeople(_ query: String) async throws -> [PersonResult] {
        let data = try await get("/search/person", ["query": query, "include_adult": "false"])
        return (data.object?["results"]?.array ?? []).prefix(8).compactMap(\.object).compactMap { p in
            guard let id = p["id"]?.int, let name = p["name"]?.string else { return nil }
            return PersonResult(id: id, name: name, knownFor: p["known_for_department"]?.string ?? "",
                                photoURL: p["profile_path"]?.string.flatMap { URL(string: "https://image.tmdb.org/t/p/w185\($0)") })
        }
    }
}

/// Extras already fetched this session, so going back to a title doesn't ask TMDb again.
@MainActor
final class TMDbExtrasCache {
    static let shared = TMDbExtrasCache()
    private var store: [String: TMDb.Extras] = [:]
    private var running: [String: Task<TMDb.Extras, Error>] = [:]

    func extras(_ id: Int, type: ItemType, apiKey: String) async throws -> TMDb.Extras {
        let key = "\(type.rawValue):\(id)"
        if let hit = store[key] { return hit }
        if let task = running[key] { return try await task.value }
        let task = Task { try await TMDb(apiKey: apiKey).extras(id, type: type) }
        running[key] = task
        defer { running[key] = nil }
        let value = try await task.value
        store[key] = value
        return value
    }

    func cached(_ id: Int, type: ItemType) -> TMDb.Extras? { store["\(type.rawValue):\(id)"] }
}
