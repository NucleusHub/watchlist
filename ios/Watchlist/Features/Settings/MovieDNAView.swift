import NucleusPlugins
import NucleusUI
import SwiftUI
import WatchlistPluginKit

/// What MovieDNA has learned, with a switch to turn it off and ways to tune it by hand.
struct MovieDNAView: View {
    @Environment(WatchlistStore.self) private var store
    @Environment(PluginRegistry.self) private var registry
    @Environment(Navigator.self) private var navigator
    @Environment(AppHost.self) private var host
    @State private var editing: DNATrait?
    @State private var adding = false
    @State private var askingRebuild = false
    @State private var showingAllTitles = false

    private static let titleLimit = 15

    var body: some View {
        let enabled = store.movieDNASettings.enabled
        let dna = store.movieDNA
        let uses = registry.contributions(to: .movieDNAUses)
        NucleusPage("MovieDNA") {
            if enabled, uses.isEmpty {
                NucleusSection {
                    Button { navigator.open(.plugins) } label: {
                        NucleusRow("Nothing uses your MovieDNA yet", subtitle: Text("It's learning, but it changes nothing until you turn on a plugin that uses it, such as Discover or News."),
                                   icon: IconTile("info.circle.fill", tint: .amber)) { Chevron() }
                    }
                    .buttonStyle(NucleusRowButtonStyle())
                }
            }

            NucleusSection(footer: enabled ? Text("Learned from your ratings, favorites, watchlist and Interested presses. It syncs with your Nucleus ID account.")
                                           : Text("Nothing is learned or used while it's off. What you set by hand is kept for when you turn it back on.")) {
                Toggle(isOn: Binding(get: { enabled }, set: { Haptics.selection(); store.setMovieDNAEnabled($0) })) {
                    Label { Text("Build my MovieDNA") } icon: { DNATile() }
                }
                .tint(Color(hex: 0x34C759))
                .padding(.horizontal, 16).frame(minHeight: 52)
            }

            if enabled {
                if !uses.isEmpty { usedBy(uses) }
                howItWorks
                if dna.traits.isEmpty {
                    DNAEmptyState()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
                traitSection("Genres", dna.traits(.genre))
                let titles = dna.traits(.title)
                traitSection("Titles", showingAllTitles ? titles : Array(titles.prefix(Self.titleLimit)), more: titles.count - Self.titleLimit)
                traitSection("People", dna.traits(.person))
                notInterestedSection
                NucleusSection(footer: Text("Starting over forgets your edits, removals and Interested presses, and learns again from your library. People you follow and titles you're not interested in stay.")) {
                    Button { adding = true } label: {
                        NucleusRow("Add a genre or title", icon: IconTile("plus", tint: .indigo))
                    }
                    .buttonStyle(NucleusRowButtonStyle())
                    Button { askingRebuild = true } label: {
                        NucleusRow("Start over from my library", icon: IconTile("arrow.counterclockwise", tint: .amber))
                    }
                    .buttonStyle(NucleusRowButtonStyle())
                }
            }
        }
        .sheet(item: $editing) { trait in
            DNATraitSheet(trait: trait).presentationDetents([.medium])
        }
        .sheet(isPresented: $adding) { DNAAddSheet() }
        .confirmationDialog("Start over from your library?", isPresented: $askingRebuild, titleVisibility: .visible) {
            Button("Start over", role: .destructive) { Haptics.warning(); store.rebuildMovieDNA() }
        } message: {
            Text("Your edits, removals and Interested presses are forgotten. People you follow stay.")
        }
    }

    /// People open their page when Cast & Crew is on; everything else opens the editor.
    private func open(_ trait: DNATrait) {
        if let id = personID(trait), host.canOpenPeople { host.open(.person(id)) } else { editing = trait }
    }

    private func personID(_ trait: DNATrait) -> Int? {
        trait.kind == .person ? Int(trait.key.dropFirst("person:".count)) : nil
    }

    /// What each plugin that reads MovieDNA does with it.
    private func usedBy(_ uses: [PluginContribution<MovieDNAUse>]) -> some View {
        NucleusSection("Used by") {
            ForEach(uses, id: \.id) { use in
                Label { Text(verbatim: use.value.purpose) } icon: { Image(systemName: "sparkles").foregroundStyle(Color.interest) }
                    .font(.system(size: 15))
                    .foregroundStyle(Nucleus.primaryText)
                    .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var notInterestedSection: some View {
        let hidden = store.movieDNASettings.notInterested.sorted { $0.value.at > $1.value.at }
        if !hidden.isEmpty {
            NucleusSection("Not interested", footer: Text("Hidden from suggestions for good, and their genres count a little against them.")) {
                ForEach(hidden, id: \.key) { key, title in
                    HStack(spacing: 12) {
                        Text(verbatim: title.name).font(.system(size: 16)).foregroundStyle(Nucleus.primaryText).lineLimit(1)
                        Spacer()
                        Button("Show again") {
                            Haptics.selection()
                            withAnimation { store.clearNotInterested(key) }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Nucleus.accent)
                    }
                    .padding(.horizontal, 16).frame(minHeight: 50)
                }
            }
        }
    }

    private var howItWorks: some View {
        NucleusSection("How it learns") {
            VStack(alignment: .leading, spacing: 10) {
                bullet("star.fill", "Rating a title high pulls it and its genres up; rating it low pushes them down.")
                bullet("heart.fill", "Favorites count for a lot, for as long as they stay favorites.")
                bullet("flame.fill", "Interested on a title's page gives it a boost. Press it again to boost more. Boosts fade over a few months, unlike favorites.")
                bullet("list.bullet", "What's on your watchlist counts a little.")
                bullet("person.fill", "People you follow are part of it too.")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func bullet(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Nucleus.secondaryText).frame(width: 18)
            Text(text).font(.system(size: 14)).foregroundStyle(Nucleus.glyph)
        }
    }

    @ViewBuilder
    private func traitSection(_ title: LocalizedStringKey, _ traits: [DNATrait], more: Int = 0) -> some View {
        if !traits.isEmpty {
            NucleusSection(title) {
                ForEach(traits) { trait in
                    Button { open(trait) } label: { DNATraitRow(trait: trait) }
                        .buttonStyle(NucleusRowButtonStyle())
                        .contextMenu {
                            Button("Edit") { editing = trait }
                            if let id = personID(trait), host.canOpenPeople {
                                Button("Open page") { host.open(.person(id)) }
                            }
                            Button("Remove from MovieDNA", role: .destructive) { Haptics.warning(); store.removeFromDNA(trait) }
                        }
                }
                if more > 0 {
                    Button { withAnimation { showingAllTitles.toggle() } } label: {
                        NucleusRow(showingAllTitles ? "Show fewer" : "Show all \(more + Self.titleLimit)")
                    }
                    .buttonStyle(NucleusRowButtonStyle())
                }
            }
        }
    }
}

/// A trait's name, how strong it is and where that came from.
struct DNATraitRow: View {
    let trait: DNATrait

    var body: some View {
        HStack(spacing: 12) {
            if trait.kind == .title {
                Poster(url: trait.poster, type: trait.itemType, cornerRadius: 6).frame(width: 34, height: 51)
            } else if trait.kind == .person {
                Poster(url: trait.poster, cornerRadius: 22).frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: trait.name).font(.system(size: 16)).foregroundStyle(Nucleus.primaryText).lineLimit(1)
                StrengthBar(strength: trait.strength)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: "\(Int(trait.strength))").font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(Nucleus.primaryText)
                if let note = note { note.font(.system(size: 12)).foregroundStyle(Nucleus.secondaryText) }
            }
            .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, trait.kind == .title ? 8 : 12)
        .contentShape(Rectangle())
    }

    private var note: Text? {
        if trait.isManual { return Text("Set by you") }
        if trait.followed { return Text("Following") }
        if trait.boosts > 0 { return Text("Boosted \(trait.boosts)×") }
        return nil
    }
}

/// -100…100 as a bar growing left (avoid) or right (into it) from a mark in the middle.
struct StrengthBar: View {
    let strength: Double

    var body: some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            let width = half * min(1, abs(strength) / 100)
            ZStack(alignment: .leading) {
                Capsule().fill(Nucleus.well).frame(height: 6)
                Capsule()
                    .fill(strength >= 0 ? Color.interest : Color(hex: 0x64748B))
                    .frame(width: max(4, width), height: 6)
                    .offset(x: strength >= 0 ? half : half - width)
                Capsule().fill(Nucleus.secondaryText.opacity(0.6)).frame(width: 2, height: 10).offset(x: half - 1)
            }
            .frame(height: geo.size.height)
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

/// Set a trait's strength by hand, go back to the learned value, or remove it.
struct DNATraitSheet: View {
    let trait: DNATrait
    @Environment(WatchlistStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var strength: Double = 0

    var body: some View {
        NucleusSheetPage(LocalizedStringKey(trait.name), confirmTitle: "Save", onCancel: { dismiss() }, onConfirm: save) {
            NucleusSection(footer: Text("-100 means keep it away from me, 100 means more of this, please.")) {
                VStack(spacing: 10) {
                    HStack {
                        Text("Strength").font(.system(size: 16)).foregroundStyle(Nucleus.primaryText)
                        Spacer()
                        Text(verbatim: "\(Int(strength))").font(.system(size: 16, weight: .semibold).monospacedDigit()).foregroundStyle(Nucleus.primaryText)
                    }
                    Slider(value: $strength, in: -100...100, step: 5).tint(Color.interest)
                }
                .padding(16)
            }
            NucleusSection {
                if trait.isManual, let learned = trait.learned {
                    Button {
                        store.setDNAStrength(nil, for: trait)
                        dismiss()
                    } label: { NucleusRow("Use the learned value (\(Int(learned)))", icon: IconTile("wand.and.stars", tint: .violet)) }
                    .buttonStyle(NucleusRowButtonStyle())
                }
                Button {
                    Haptics.warning()
                    store.removeFromDNA(trait)
                    dismiss()
                } label: { NucleusRow("Remove from MovieDNA", titleColor: Nucleus.danger) }
                .buttonStyle(NucleusRowButtonStyle())
            }
        }
        .onAppear { strength = trait.strength }
    }

    private func save() {
        store.setDNAStrength(strength, for: trait)
        Haptics.success()
        dismiss()
    }
}

/// Add a genre or a title to MovieDNA by hand.
struct DNAAddSheet: View {
    enum Kind: Hashable { case genre, title }

    private struct Candidate: Identifiable, Hashable {
        let key: String
        let kind: DNAKind
        let name: String
        let detail: String?
        var poster: String?
        var type: ItemType = .movie
        var id: String { key }
    }

    @Environment(WatchlistStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind = .genre
    @State private var query = ""
    @State private var picked: Candidate?
    @State private var strength: Double = 60
    @State private var tmdbResults: [TMDb.SearchResult] = []
    // Taken once when the sheet opens, so typing only filters instead of re-reading the whole library.
    @State private var genres: [String] = []
    @State private var library: [Candidate] = []
    @State private var existing: Set<String> = []

    /// TMDb's movie and TV genre names, so a genre can be added before any title has it.
    private static let commonGenres = [
        "Action", "Adventure", "Animation", "Comedy", "Crime", "Documentary", "Drama", "Family", "Fantasy", "History",
        "Horror", "Music", "Mystery", "Romance", "Science Fiction", "Thriller", "War", "Western", "Sci-Fi & Fantasy",
        "Action & Adventure", "Kids", "Reality", "Soap", "Talk", "War & Politics",
    ]

    var body: some View {
        NucleusSheetPage("Add to MovieDNA", confirmTitle: "Add", canConfirm: picked != nil, onCancel: { dismiss() }, onConfirm: add) {
            NucleusSegmented(selection: $kind, items: [(Kind.genre, "Genre"), (Kind.title, "Title")], fill: true)
                .padding(.bottom, 4)
                .onChange(of: kind) { _, _ in picked = nil; query = "" }
            NucleusSection {
                TextField(kind == .genre ? "Genre" : "Search titles", text: $query)
                    .font(.system(size: 16))
                    .autocorrectionDisabled()
                    .padding(.horizontal, 16).frame(minHeight: 52)
            }
            NucleusSection {
                ForEach(candidates) { c in
                    Button { Haptics.selection(); picked = c } label: { row(c) }
                        .buttonStyle(NucleusRowButtonStyle())
                }
            }
            if picked != nil {
                NucleusSection {
                    VStack(spacing: 10) {
                        HStack {
                            Text("Strength").font(.system(size: 16)).foregroundStyle(Nucleus.primaryText)
                            Spacer()
                            Text(verbatim: "\(Int(strength))").font(.system(size: 16, weight: .semibold).monospacedDigit())
                        }
                        Slider(value: $strength, in: -100...100, step: 5).tint(Color.interest)
                    }
                    .padding(16)
                }
            }
        }
        .onAppear(perform: load)
        .task(id: kind == .title ? query : "") { await searchTMDb() }
    }

    @ViewBuilder
    private func row(_ c: Candidate) -> some View {
        HStack(spacing: 12) {
            if c.kind == .title {
                Poster(url: c.poster, type: c.type, cornerRadius: 6).frame(width: 34, height: 51)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: c.name).font(.system(size: 16)).foregroundStyle(Nucleus.primaryText).lineLimit(1)
                if let detail = c.detail { Text(verbatim: detail).font(.system(size: 13)).foregroundStyle(Nucleus.secondaryText) }
            }
            Spacer()
            if picked == c { Image(systemName: "checkmark").foregroundStyle(Nucleus.accent) }
        }
        .padding(.horizontal, 16).padding(.vertical, c.kind == .title ? 8 : 0).frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private func load() {
        existing = Set(store.movieDNA.traits.map(\.key))
        var seen = Set<String>()
        genres = (store.document.items.flatMap(\.genres) + Self.commonGenres).filter { seen.insert(DNAKey.genre($0)).inserted }
        let inWatchlist = String(localized: "In your watchlist")
        library = store.document.items.map {
            Candidate(key: DNAKey.title($0), kind: .title, name: $0.title, detail: inWatchlist, poster: $0.posterUrl, type: $0.type)
        }
    }

    private func add() {
        guard let picked else { return }
        store.addToDNA(kind: picked.kind, key: picked.key, name: picked.name, poster: picked.poster, strength: strength)
        Haptics.success()
        dismiss()
    }

    private var needle: String { query.trimmingCharacters(in: .whitespaces) }

    private var candidates: [Candidate] {
        switch kind {
        case .genre:
            var out = genres.filter { needle.isEmpty || $0.localizedCaseInsensitiveContains(needle) }
                .map { Candidate(key: DNAKey.genre($0), kind: .genre, name: $0, detail: nil) }
            if !needle.isEmpty, !genres.contains(where: { DNAKey.genre($0) == DNAKey.genre(needle) }) {
                out.insert(Candidate(key: DNAKey.genre(needle), kind: .genre, name: needle, detail: nil), at: 0)
            }
            return Array(out.filter { !existing.contains($0.key) }.prefix(30))
        case .title:
            guard !needle.isEmpty else { return [] }
            let matches = library.filter { $0.name.localizedCaseInsensitiveContains(needle) }
            let keys = Set(matches.map(\.key))
            let remote = tmdbResults.map {
                Candidate(key: DNAKey.title(type: $0.type, tmdbID: $0.id), kind: .title, name: $0.title,
                          detail: [$0.year, "TMDb"].filter { !$0.isEmpty }.joined(separator: " · "), poster: $0.posterURL, type: $0.type)
            }.filter { !keys.contains($0.key) }
            return Array((matches + remote).filter { !existing.contains($0.key) }.prefix(20))
        }
    }

    private func searchTMDb() async {
        guard kind == .title, needle.count >= 2, !store.settings.tmdbApiKey.isEmpty else { tmdbResults = []; return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        tmdbResults = (try? await TMDb(apiKey: store.settings.tmdbApiKey).search(needle)) ?? []
    }
}

/// `NucleusEmptyState` with the DNA glyph, which isn't an SF Symbol.
private struct DNAEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            DNAGlyph()
                .foregroundStyle(Nucleus.accent)
                .frame(width: 32, height: 32)
                .frame(width: 68, height: 68)
                .nucleusGlass(in: Circle())
            Text("Nothing learned yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Nucleus.primaryText)
            Text("Rate titles, mark favorites or press Interested and your MovieDNA fills in.")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(Nucleus.secondaryText)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}
