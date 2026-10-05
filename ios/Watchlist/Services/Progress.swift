import Foundation

/// Watching progress and time.
extension Item {
    var episodeTotals: (total: Int, watched: Int, tracked: Bool) {
        if let sp = seasonProgress, !sp.isEmpty {
            let total = sp.reduce(0) { $0 + max(0, $1.episodeCount) }
            let watched = sp.reduce(0) { $0 + min(max(0, $1.watched), max(0, $1.episodeCount)) }
            return (total, watched, true)
        }
        return (episodes ?? 0, 0, false)
    }

    var watchedFraction: Double {
        if isCompleted { return 1 }
        if type == .movie { return 0 }
        let t = episodeTotals
        return t.tracked && t.total > 0 ? Double(t.watched) / Double(t.total) : 0
    }

    var totalMinutes: Int { (type == .movie ? runtime : showRuntime) ?? 0 }
    var watchedMinutes: Int { Int((Double(totalMinutes) * watchedFraction).rounded()) }
    var remainingMinutes: Int { totalMinutes - watchedMinutes }

    /// The season being watched: the first one not finished, or the last once all are.
    var currentSeasonIndex: Int? {
        guard let seasons = seasonProgress, !seasons.isEmpty else { return nil }
        return seasons.firstIndex { $0.watched < $0.episodeCount } ?? seasons.count - 1
    }

    /// Anything a reset would clear: saved time, a remembered page, or watched episodes.
    var hasProgress: Bool {
        playback != nil || lastPage != nil || lastWatchedAt != nil || episodeTotals.watched > 0
    }

    /// Forgets where you were: the saved time, the page, and the spot in "Jump back in".
    mutating func clearWatchHistory() {
        playback = nil
        lastPage = nil
        set("lastWatchedAt", .null)
    }

    /// The episode a tracked show is on next: the first one not watched yet.
    var nextEpisode: (season: Int, episode: Int)? {
        guard let s = seasonProgress?.first(where: { $0.watched < $0.episodeCount }) else { return nil }
        return (s.seasonNumber, s.watched + 1)
    }

    /// Counts one more episode as watched, in the first season that isn't finished.
    mutating func watchNextEpisode() {
        guard var progress = seasonProgress, let i = progress.firstIndex(where: { $0.watched < $0.episodeCount }) else { return }
        progress[i].watched += 1
        seasonProgress = progress
        let t = episodeTotals
        status = Item.status(watched: t.watched, total: t.total)
    }

    static func status(watched: Int, total: Int) -> WatchStatus {
        if total > 0, watched >= total { return .completed }
        return watched > 0 ? .watching : .planned
    }
}

enum PlaybackTime {
    /// "23:41", or "1:52:10" past an hour.
    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

enum RuntimeText {
    /// "2d 4h", "3h 20m", "45m"; an em dash for nothing.
    static func short(_ minutes: Int) -> String {
        guard minutes > 0 else { return "—" }
        let d = minutes / 1440, h = (minutes % 1440) / 60, m = minutes % 60
        if d > 0 { return h > 0 ? "\(d)d \(h)h" : "\(d)d" }
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }
}
