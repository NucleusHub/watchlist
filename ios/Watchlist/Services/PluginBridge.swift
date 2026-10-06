import Foundation
import NucleusPlugins
import NucleusUI
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

extension Item {
    /// The ways to take back progress on this title, named for the person.
    var resetActions: [TitleAction] {
        guard hasProgress else { return [] }
        guard isShow else { return [TitleAction(id: ProgressReset.current.rawValue, title: String(localized: "Reset progress"))] }
        var actions = [TitleAction(id: ProgressReset.current.rawValue, title: String(localized: "Reset this episode"))]
        if seasonProgress?.isEmpty == false {
            actions.append(TitleAction(id: ProgressReset.season.rawValue, title: String(localized: "Reset this season"), isDestructive: true))
        }
        actions.append(TitleAction(id: ProgressReset.show.rawValue, title: String(localized: "Reset the whole show"), isDestructive: true))
        return actions
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
            } resetActions: { id in
                store.item(id)?.resetActions ?? []
            } perform: { id, action in
                Haptics.warning()
                store.resetProgress(id, ProgressReset(rawValue: action) ?? .current)
            }
            ForEach(Array(sections.enumerated()), id: \.offset) { $0.element.value.view(context) }
        }
    }
}

/// The sections plugins add to a TMDb title's page (cast and crew, ...).
struct PluginItemSections: View {
    let type: ItemType
    let tmdbID: Int?
    let title: String
    /// Hand-entered people, for titles TMDb doesn't have.
    var credits: [CustomCredit] = []
    var canNavigate = true
    @Environment(PluginRegistry.self) private var registry
    @Environment(AppHost.self) private var host

    var body: some View {
        let given = tmdbID == nil ? PluginCredits(custom: credits) : nil
        let context = ItemSectionContext(kind: type.mediaKind, tmdbID: tmdbID, title: title, host: host, canNavigate: canNavigate, credits: given)
        ForEach(registry.contributions(to: .itemSections), id: \.id) { $0.value.view(context) }
    }
}

/// A page a plugin contributed; says so when the plugin was turned off while it was open.
struct PluginPageView: View {
    let id: String
    let argument: String
    @Environment(PluginRegistry.self) private var registry
    @Environment(AppHost.self) private var host

    var body: some View {
        if let page = registry.contributions(to: .pages).first(where: { $0.id == id }) {
            page.value.view(argument: argument, host: host)
        } else {
            NucleusPage {
                NucleusEmptyState("puzzlepiece.extension", title: "Plugin turned off", message: "Turn it back on in Settings → Plugins to see this page.")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            }
        }
    }
}

extension PluginCredits {
    init(custom: [CustomCredit]) {
        func credit(_ c: CustomCredit) -> PluginCredit {
            PluginCredit(personID: c.personID ?? 0, name: c.name, role: c.role, department: c.department,
                         photoURL: c.photo.flatMap { URL(string: $0) })
        }
        self.init(cast: custom.filter(\.isCast).map(credit), crew: custom.filter { !$0.isCast }.map(credit))
    }
}
