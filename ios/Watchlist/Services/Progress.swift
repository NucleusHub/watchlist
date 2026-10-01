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

    static func status(watched: Int, total: Int) -> WatchStatus {
        if total > 0, watched >= total { return .completed }
        return watched > 0 ? .watching : .planned
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
