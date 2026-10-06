import NucleusPlugins
import NucleusUI
import SwiftUI
import WatchlistPluginKit

struct ItemDetailView: View {
    let itemID: String
    @Environment(WatchlistStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @Environment(Preferences.self) private var preferences
    @Environment(PluginRegistry.self) private var registry
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var confirmingReset = false
    @State private var extras: TMDb.Extras?
    @State private var trailers = TrailerPlayer()

    var body: some View {
        if let item = store.item(itemID) {
            NucleusPage(actions: {
                GlassCircleButton("pencil") { navigator.present(.editItem(itemID)) }.accessibilityLabel("Edit")
                Menu {
                    ItemMenu(item: item) { confirmingDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Nucleus.glyph)
                        .frame(width: 40, height: 40)
                        .nucleusGlass(in: Circle(), interactive: true)
                }
                .accessibilityLabel("More")
            }) {
                content(item)
            }
            .modifier(DeleteItemDialog(item: item, isPresented: $confirmingDelete))
            .modifier(ResetProgressDialog(item: item, isPresented: $confirmingReset))
            .task(id: "\(item.type.rawValue):\(item.tmdbId ?? 0):\(store.settings.tmdbApiKey):\(item.trailerUrl ?? "")") { await loadExtras(item) }
            .background {
                TrailerPlayerHost(player: trailers).frame(width: 2, height: 2).opacity(0.01).accessibilityHidden(true)
            }
            .onAppear {
                trailers.onFailure = { key in
                    if let url = URL(string: "https://www.youtube.com/watch?v=\(key)") { openURL(url) }
                }
            }
        } else {
            NucleusPage {
                NucleusEmptyState("film", title: "Title not found", message: "It may have been deleted on another device.")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            }
        }
    }

    @ViewBuilder
    private func content(_ item: Item) -> some View {
        VStack(spacing: 14) {
            Poster(url: item.posterUrl, type: item.type, cornerRadius: 22)
                .aspectRatio(2 / 3, contentMode: .fit)
                .frame(maxWidth: 220)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
                .onTapGesture { if let url = OpenLinks.url(for: item, settings: store.settings) { open(url, item) } }
            Text(verbatim: item.title)
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.4)
                .multilineTextAlignment(.center)
                .foregroundStyle(Nucleus.primaryText)
            if !item.metaLine.isEmpty {
                Text(item.metaLine).font(.system(size: 15)).foregroundStyle(Nucleus.secondaryText)
            }
            HStack(spacing: 6) {
                Tag(text: Text(item.type.title))
                Menu {
                    ForEach(WatchStatus.allCases, id: \.self) { status in
                        Button(status.title) { Haptics.selection(); store.updateItem(itemID) { $0.status = status } }
                    }
                } label: { Tag(text: Text(item.status.title), color: item.status.color) }
                if let tmdb = item.tmdbRating, tmdb > 0 {
                    Tag(text: Text(verbatim: "TMDb ★ \(String(format: "%.1f", tmdb))"))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)

        HStack(spacing: 10) {
            if item.isCompleted {
                Label("Watched", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WatchStatus.completed.color)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .nucleusGlass(in: Capsule())
            } else {
                Button {
                    Haptics.success()
                    withAnimation(NucleusMotion.quick) { store.markWatched(itemID) }
                } label: { Label("Mark as watched", systemImage: "checkmark") }
                    .buttonStyle(NucleusPrimaryButtonStyle())
            }
            if store.movieDNASettings.enabled { InterestedButton(item: item) }
            FavoriteButton(item: item, size: 52, onPoster: false)
        }
        .padding(.bottom, store.interestCount(item) > 0 ? 10 : 24)

        if store.movieDNASettings.enabled, store.interestCount(item) > 0 {
            interestNote(item)
        }

        if item.isShow {
            showProgress(item)
        }

        if let overview = Self.overview(item, extras), !overview.isEmpty {
            NucleusSection("Overview") {
                Text(verbatim: overview)
                    .font(.system(size: 15))
                    .foregroundStyle(Nucleus.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }

        if case let videos = Self.videos(item, extras), !videos.isEmpty {
            TrailersSection(videos: videos, loadingKey: trailers.loadingKey) { video in
                Haptics.tap()
                trailers.play(video.key)
            }
        }

        NucleusSection("Your rating") {
            RatingControl(rating: Binding(get: { item.rating }, set: { value in store.updateItem(itemID) { $0.rating = value } }))
                .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        }

        if let provider = item.streamingProvider, !provider.isEmpty {
            NucleusSection("Where to watch") {
                Button {
                    if let link = item.watchLink, let url = URL(string: link) { openURL(url) }
                } label: {
                    HStack(spacing: 12) {
                        AsyncImage(url: TMDb.logoURL(item.streamingLogo)) { $0.resizable() } placeholder: { Nucleus.well }
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text(verbatim: provider).font(.system(size: 16)).foregroundStyle(Nucleus.primaryText)
                        Spacer()
                        if item.watchLink != nil { Image(systemName: "arrow.up.right").foregroundStyle(Nucleus.secondaryText) }
                    }
                    .padding(.horizontal, 16).frame(minHeight: 52).contentShape(Rectangle())
                }
                .buttonStyle(NucleusRowButtonStyle())
            }
        }

        if !item.genres.isEmpty {
            NucleusSection("Genres") {
                FlowLayout(spacing: 6) {
                    ForEach(item.genres, id: \.self) { g in
                        Text(verbatim: g)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).frame(height: 28)
                            .background(Capsule().fill(GenrePalette.color(g)))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        if let tmdbID = item.tmdbId, !store.settings.tmdbApiKey.isEmpty {
            PluginItemSections(type: item.type, tmdbID: tmdbID, title: item.title)
        } else if item.tmdbId == nil, !item.customCredits.isEmpty {
            PluginItemSections(type: item.type, tmdbID: nil, title: item.title, credits: item.customCredits)
        }

        let collections = store.collections.filter { item.isIn($0.id) }
        NucleusSection("Collections") {
            ForEach(collections) { col in
                Button { navigator.open(.collection(col.id)) } label: {
                    NucleusRow(verbatim: col.name, icon: IconTile("folder.fill", tint: .violet)) { Chevron() }
                }
                .buttonStyle(NucleusRowButtonStyle())
            }
            Button { navigator.present(.manageCollections(itemID)) } label: {
                NucleusRow(collections.isEmpty ? "Add to a collection" : "Change collections", icon: IconTile("plus", tint: .indigo))
            }
            .buttonStyle(NucleusRowButtonStyle())
        }

        if !item.notes.isEmpty {
            NucleusSection("Notes") {
                Text(verbatim: item.notes)
                    .font(.system(size: 15))
                    .foregroundStyle(Nucleus.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }

        NucleusSection {
            if let page = item.lastPage ?? item.playback?.url, let url = URL(string: page), preferences.inAppBrowser {
                Button { navigator.browse(url, item: item) } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Continue watching").font(.system(size: 16)).foregroundStyle(Nucleus.primaryText)
                            Spacer()
                            if let playback = item.playback {
                                Text(verbatim: "\(PlaybackTime.clock(playback.position)) / \(PlaybackTime.clock(playback.duration))")
                                    .font(.system(size: 14).monospacedDigit()).foregroundStyle(Nucleus.secondaryText)
                            } else {
                                Text(verbatim: url.host?.replacingOccurrences(of: "www.", with: "") ?? "")
                                    .font(.system(size: 14)).foregroundStyle(Nucleus.secondaryText)
                            }
                        }
                        if let playback = item.playback { ProgressView(value: playback.fraction).tint(WatchStatus.watching.color) }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14).contentShape(Rectangle())
                }
                .buttonStyle(NucleusRowButtonStyle())
            }
            if let url = OpenLinks.url(for: item, settings: store.settings) {
                Button { open(url, item) } label: {
                    NucleusRow("Open on \(OpenLinks.target(for: item, settings: store.settings).type.label)",
                               icon: IconTile("arrow.up.right.square", tint: .sky))
                }
                .buttonStyle(NucleusRowButtonStyle())
            }
            if item.hasProgress {
                Button { confirmingReset = true } label: {
                    NucleusRow("Reset progress", icon: IconTile("arrow.counterclockwise", tint: .amber))
                }
                .buttonStyle(NucleusRowButtonStyle())
            }
            Button { confirmingDelete = true } label: { NucleusRow("Delete", titleColor: Nucleus.danger) }
                .buttonStyle(NucleusRowButtonStyle())
        }
    }

    /// What the presses did, and a heads-up while no plugin uses MovieDNA, so the button doesn't look broken.
    private func interestNote(_ item: Item) -> some View {
        Button { navigator.open(.movieDNA) } label: {
            HStack(spacing: 6) {
                Image(systemName: registry.contributions(to: .movieDNAUses).isEmpty ? "info.circle" : "flame.fill")
                if registry.contributions(to: .movieDNAUses).isEmpty {
                    Text("Boosted \(store.interestCount(item))× in your MovieDNA. No plugin uses it yet.")
                } else {
                    Text("Boosted \(store.interestCount(item))× in your MovieDNA")
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(Nucleus.secondaryText)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 24)
    }

    /// Trailers and credits from TMDb; nothing without a TMDb id or key.
    private func loadExtras(_ item: Item) async {
        #if DEBUG
        if let key = DebugLaunch.playTrailer {
            extras = TMDb.Extras(videos: [TMDb.Video(key: key, name: "Debug trailer", kind: "Trailer", official: true, publishedAt: nil)])
            trailers.prepare(key)
            try? await Task.sleep(for: .seconds(6))
            trailers.play(key)
            return
        }
        #endif
        let key = store.settings.tmdbApiKey
        guard let id = item.tmdbId, !key.isEmpty else {
            extras = nil
            if let first = Self.videos(item, nil).first { trailers.prepare(first.key) }
            return
        }
        extras = TMDbExtrasCache.shared.cached(id, type: item.type)
        if extras == nil { extras = try? await TMDbExtrasCache.shared.extras(id, type: item.type, apiKey: key) }
        // Ready before the tap, so the trailer opens straight in the full-screen player.
        if let first = Self.videos(item, extras).first { trailers.prepare(first.key) }
    }

    /// TMDb's description, or the one written by hand for titles TMDb doesn't have.
    static func overview(_ item: Item, _ extras: TMDb.Extras?) -> String? {
        if let tmdb = extras?.overview, !tmdb.isEmpty { return tmdb }
        return item.overview.isEmpty ? nil : item.overview
    }

    /// A pasted trailer goes first; it's the one the person picked.
    static func videos(_ item: Item, _ extras: TMDb.Extras?) -> [TMDb.Video] {
        let own = item.trailerUrl.flatMap(TMDb.Video.youTubeKey).map {
            TMDb.Video(key: $0, name: String(localized: "Trailer"), kind: "Trailer", official: false, publishedAt: nil)
        }
        let tmdb = extras?.videos ?? []
        return (own.map { [$0] } ?? []) + tmdb.filter { $0.key != own?.key }
    }

    private func open(_ url: URL, _ item: Item) {
        if preferences.inAppBrowser { navigator.browse(url, item: item) } else { openURL(url) }
    }

    @ViewBuilder
    private func showProgress(_ item: Item) -> some View {
        let totals = item.episodeTotals
        NucleusSection("Progress") {
            Button { navigator.present(.seasons(itemID)) } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        if totals.tracked {
                            Text("\(totals.watched) of \(totals.total) episodes")
                                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Nucleus.primaryText)
                        } else {
                            Text("Track episodes").font(.system(size: 16, weight: .semibold)).foregroundStyle(Nucleus.primaryText)
                        }
                        Spacer()
                        if item.remainingMinutes > 0, item.watchedFraction > 0 {
                            Text("\(RuntimeText.short(item.remainingMinutes)) left").font(.system(size: 13)).foregroundStyle(Nucleus.secondaryText)
                        }
                        Chevron()
                    }
                    if totals.tracked {
                        ProgressView(value: item.watchedFraction)
                            .tint(item.isCompleted ? WatchStatus.completed.color : WatchStatus.watching.color)
                    }
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(NucleusRowButtonStyle())
        }
    }
}

extension OpenTarget.Kind {
    var label: String {
        switch self {
        case .tmdb: "TMDb"
        case .csfd: "ČSFD"
        case .google: "Google"
        case .custom: String(localized: "your link")
        }
    }
}

/// Wraps chips onto as many lines as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { y += line + spacing; x = 0; line = 0 }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { y += line + spacing; x = bounds.minX; line = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
