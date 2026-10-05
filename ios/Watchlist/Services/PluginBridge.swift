import Foundation
import NucleusPlugins
import SwiftUI
import WatchlistPluginKit

extension Item {
    /// Where "Jump back in" takes you: the saved page, or the page of the saved video.
    var jumpURL: URL? { (lastPage ?? playback?.url).flatMap { URL(string: $0) } }

    /// What plugins see of this title.
    var pluginTitle: PluginTitle {
        // Positions saved before `lastWatchedAt` existed fall back to when the title last changed.
        let watched = (lastWatchedAt ?? (playback != nil ? updatedAt : nil)).flatMap(Timestamp.millis).map { Date(timeIntervalSince1970: $0 / 1000) }
        return PluginTitle(
            id: id, title: title, kind: type == .movie ? .movie : .show, posterURL: posterUrl.flatMap { URL(string: $0) },
            isCompleted: isCompleted, lastWatchedAt: watched,
            resume: playback.map { .init(position: $0.position, duration: $0.duration) },
            nextEpisode: isShow ? nextEpisode.map { .init(season: $0.season, episode: $0.episode) } : nil,
            resumeHost: jumpURL?.host?.replacingOccurrences(of: "www.", with: "")
        )
    }
}

/// The sections plugins put at the top of the Watchlist.
struct HomeSections: View {
    @Environment(WatchlistStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(PluginRegistry.self) private var registry
    @Environment(Navigator.self) private var navigator

    var body: some View {
        let sections = registry.contributions(to: .homeSections)
        if !sections.isEmpty {
            let context = HomeSectionContext(titles: store.items.map(\.pluginTitle), canResume: preferences.inAppBrowser) { id in
                guard let item = store.item(id), let page = item.jumpURL else { return }
                navigator.browse(OpenLinks.url(for: item, settings: store.settings) ?? page, item: item)
            }
            ForEach(Array(sections.enumerated()), id: \.offset) { $0.element.value.view(context) }
        }
    }
}
