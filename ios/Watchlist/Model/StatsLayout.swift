import Foundation
import NucleusUI

/// One card on the statistics page.
enum StatsCard: String, Codable, CaseIterable, Identifiable {
    case watched, inProgress, planned, total, ratings, byType, availableOn, topYears

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .watched: "Watched"
        case .inProgress: "In progress"
        case .planned: "Planned"
        case .total: "Total"
        case .ratings: "Ratings"
        case .byType: "By type"
        case .availableOn: "Available on"
        case .topYears: "Top years"
        }
    }

    var icon: String {
        switch self {
        case .watched: "checkmark.circle.fill"
        case .inProgress: "play.circle.fill"
        case .planned: "bookmark.fill"
        case .total: "film.stack.fill"
        case .ratings: "star.fill"
        case .byType: "square.split.2x1.fill"
        case .availableOn: "tv.fill"
        case .topYears: "calendar"
        }
    }

    var tint: NucleusTint {
        switch self {
        case .watched: .emerald
        case .inProgress: .blue
        case .planned: .orange
        case .total: .indigo
        case .ratings: .amber
        case .byType: .teal
        case .availableOn: .violet
        case .topYears: .rose
        }
    }
}

/// The statistics page as the person arranged it: order, what's shown, and how big. Kept per device.
struct StatsLayout: Codable, Equatable {
    enum Size: String, Codable { case small, large }

    struct Entry: Codable, Equatable, Identifiable {
        var card: StatsCard
        var visible = true
        var size: Size
        var id: String { card.rawValue }
    }

    var entries: [Entry]

    static let standard = StatsLayout(entries: [
        .init(card: .watched, size: .large),
        .init(card: .inProgress, size: .small), .init(card: .planned, size: .small),
        .init(card: .total, size: .small), .init(card: .ratings, size: .small),
        .init(card: .byType, size: .large),
        .init(card: .availableOn, size: .large),
        .init(card: .topYears, size: .large),
    ])

    /// Cards added in later versions show up at the end, so an older saved layout never hides them.
    func completed() -> StatsLayout {
        var seen = Set<StatsCard>()
        var out = StatsLayout(entries: entries.filter { seen.insert($0.card).inserted })
        for entry in Self.standard.entries where !seen.contains(entry.card) {
            out.entries.append(entry)
        }
        return out
    }

    /// Visible cards in rows: two small ones side by side, a large one (or a lone small one) alone.
    /// Cards outside `available` (nothing to show yet) are skipped.
    func rows(available: Set<StatsCard> = Set(StatsCard.allCases)) -> [[Entry]] {
        var rows: [[Entry]] = []
        var pending: Entry?
        for e in entries where e.visible && available.contains(e.card) {
            if e.size == .small {
                if let p = pending { rows.append([p, e]); pending = nil } else { pending = e }
            } else {
                if let p = pending { rows.append([p]); pending = nil }
                rows.append([e])
            }
        }
        if let p = pending { rows.append([p]) }
        return rows
    }

    static func load(_ defaults: UserDefaults = .standard) -> StatsLayout {
        // An unknown card (from a newer version) fails the decode; fall back rather than crash.
        defaults.data(forKey: "statsLayout").flatMap { try? JSONDecoder().decode(StatsLayout.self, from: $0) }?.completed() ?? .standard
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: "statsLayout") }
    }
}
