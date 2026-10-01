import NucleusUI
import SwiftUI

/// How far into each season you are. Saving sets the status from the progress.
struct SeasonProgressSheet: View {
    let itemID: String
    @Environment(WatchlistStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var seasons: [SeasonProgress] = []
    @State private var loading = true
    @State private var failure: String?

    private var total: Int { seasons.reduce(0) { $0 + $1.episodeCount } }
    private var watched: Int { seasons.reduce(0) { $0 + min($1.watched, $1.episodeCount) } }

    var body: some View {
        NucleusSheetPage("Progress", onCancel: { dismiss() }, onConfirm: seasons.isEmpty ? nil : save) {
            if let item = store.item(itemID) {
                Text(verbatim: item.title).font(.system(size: 15)).foregroundStyle(Nucleus.secondaryText).padding(.bottom, 16)
            }
            if loading {
                ProgressView().padding(.top, 40)
            } else if seasons.isEmpty {
                NucleusEmptyState("list.bullet", title: "No episode data", message: LocalizedStringKey(failure ?? String(localized: "Add the number of episodes when editing the show, or a TMDb key in Settings.")))
                    .padding(.top, 24)
            } else {
                summary
                NucleusSection {
                    ForEach($seasons) { $season in
                        row($season)
                    }
                }
                HStack(spacing: 10) {
                    Button("Reset all") { Haptics.selection(); setAll(false) }.buttonStyle(NucleusSecondaryButtonStyle())
                    Button("Mark all") { Haptics.selection(); setAll(true) }.buttonStyle(NucleusSecondaryButtonStyle())
                }
            }
        }
        .task { await load() }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(watched) of \(total) episodes").font(.system(size: 17, weight: .semibold)).foregroundStyle(Nucleus.primaryText)
                Spacer()
                if let item = store.item(itemID), item.showRuntime ?? 0 > 0 {
                    let left = Int(Double(item.showRuntime ?? 0) * (1 - (total > 0 ? Double(watched) / Double(total) : 0)))
                    Text(watched >= total ? String(localized: "All watched") : String(localized: "\(RuntimeText.short(left)) left"))
                        .font(.system(size: 13)).foregroundStyle(Nucleus.secondaryText)
                }
            }
            ProgressView(value: total > 0 ? Double(watched) / Double(total) : 0)
                .tint(watched >= total ? WatchStatus.completed.color : WatchStatus.watching.color)
        }
        .padding(16)
        .nucleusGlass(cornerRadius: 22)
        .padding(.bottom, 20)
    }

    private func row(_ season: Binding<SeasonProgress>) -> some View {
        let s = season.wrappedValue
        let done = s.watched >= s.episodeCount
        return HStack(spacing: 12) {
            Button {
                Haptics.selection()
                season.wrappedValue.watched = done ? 0 : s.episodeCount
            } label: {
                ZStack {
                    Circle().strokeBorder(Nucleus.separator, lineWidth: 3)
                    Circle().trim(from: 0, to: s.episodeCount > 0 ? CGFloat(s.watched) / CGFloat(s.episodeCount) : 0)
                        .stroke(done ? WatchStatus.completed.color : WatchStatus.watching.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if done { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(WatchStatus.completed.color) }
                }
                .frame(width: 30, height: 30)
            }
            .buttonStyle(NucleusPressStyle())
            .accessibilityLabel(done ? "Mark season unwatched" : "Mark season watched")
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: s.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Nucleus.primaryText)
                Text("\(s.watched) / \(s.episodeCount)").font(.system(size: 12).monospacedDigit()).foregroundStyle(Nucleus.secondaryText)
            }
            Spacer()
            Stepper("", value: season.watched, in: 0...max(0, s.episodeCount))
                .labelsHidden()
                .onChange(of: s.watched) { _, _ in Haptics.selection() }
        }
        .padding(.horizontal, 16).frame(minHeight: 60)
    }

    private func setAll(_ on: Bool) {
        for i in seasons.indices { seasons[i].watched = on ? seasons[i].episodeCount : 0 }
    }

    private func load() async {
        defer { loading = false }
        guard let item = store.item(itemID) else { return }
        if let sp = item.seasonProgress, !sp.isEmpty {
            seasons = sp
            return
        }
        let tmdb = TMDb(apiKey: store.settings.tmdbApiKey)
        if !store.settings.tmdbApiKey.isEmpty {
            do {
                var id = item.tmdbId
                if id == nil {
                    let tv = try await tmdb.searchMulti(item.title).filter { $0.object?["media_type"]?.string == "tv" }.compactMap(\.object)
                    let match = item.year.flatMap { y in tv.first { String(($0["first_air_date"]?.string ?? "").prefix(4)) == String(y) } } ?? tv.first
                    id = match?["id"]?.int
                }
                if let id {
                    seasons = TMDb.seasonProgress(try await tmdb.detail(id, type: .show), existing: nil)
                    if !seasons.isEmpty { return }
                }
            } catch {
                failure = error.localizedDescription
            }
        }
        if let episodes = item.episodes, episodes > 0 {
            seasons = [SeasonProgress(seasonNumber: 1, name: String(localized: "All episodes"), episodeCount: episodes, watched: 0)]
        }
    }

    private func save() {
        let progress = seasons
        let w = watched, t = total
        store.updateItem(itemID) {
            $0.seasonProgress = progress
            $0.seasons = progress.count
            $0.episodes = t
            $0.status = Item.status(watched: w, total: t)
        }
        Haptics.success()
        dismiss()
    }
}
