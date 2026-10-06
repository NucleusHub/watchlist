import NucleusUI
import SwiftUI

/// A TMDb title that isn't in the library yet: what it is, its trailers and plugin sections, and a way to add it.
struct TitlePreviewView: View {
    let type: ItemType
    let tmdbID: Int
    @Environment(WatchlistStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @State private var draft: Item?
    @State private var overview = ""
    @State private var failed = false
    @State private var extras: TMDb.Extras?
    @State private var trailers = TrailerPlayer()

    var body: some View {
        NucleusPage {
            if let draft {
                content(draft)
            } else if failed {
                NucleusEmptyState("wifi.exclamationmark", title: "Couldn't load this title", message: "Check your connection and TMDb key.")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 120)
            }
        }
        .task(id: tmdbID) { await load() }
        .trailerHost(trailers)
    }

    @ViewBuilder
    private func content(_ item: Item) -> some View {
        VStack(spacing: 14) {
            Poster(url: item.posterUrl, type: item.type, cornerRadius: 22)
                .aspectRatio(2 / 3, contentMode: .fit)
                .frame(maxWidth: 200)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
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
                if let tmdb = item.tmdbRating, tmdb > 0 {
                    Tag(text: Text(verbatim: "TMDb ★ \(String(format: "%.1f", tmdb))"))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)

        Button(action: add) { Label("Add to watchlist", systemImage: "plus") }
            .buttonStyle(NucleusPrimaryButtonStyle())
            .padding(.bottom, 24)

        if !overview.isEmpty {
            OverviewSection(text: overview)
        }

        if let extras, !extras.videos.isEmpty {
            TrailersSection(videos: extras.videos, loadingKey: trailers.loadingKey) { video in
                Haptics.tap()
                trailers.play(video.key)
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

        PluginItemSections(type: type, tmdbID: tmdbID, title: item.title)
    }

    private func load() async {
        let key = store.settings.tmdbApiKey
        do {
            let (item, overview) = try await TMDb(apiKey: key).draft(tmdbID, type: type)
            self.overview = overview
            draft = item
        } catch {
            failed = true
            return
        }
        extras = try? await TMDbExtrasCache.shared.extras(tmdbID, type: type, apiKey: key)
        if let first = extras?.videos.first { trailers.prepare(first.key) }
    }

    /// Adds it and swaps this preview for the title's own page.
    private func add() {
        guard let draft, let created = store.createItem(draft) else { return }
        Haptics.success()
        if !navigator.path.isEmpty { navigator.path.removeLast() }
        navigator.open(.item(created.id))
    }
}
