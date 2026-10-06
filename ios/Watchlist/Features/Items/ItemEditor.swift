import NucleusPlugins
import NucleusUI
import PhotosUI
import SwiftUI

/// Add or edit a title. Typing a title searches the chosen sources; picking a result fills in the rest.
struct ItemEditor: View {
    let itemID: String?
    var collectionID: String? = nil
    @Environment(WatchlistStore.self) private var store
    @Environment(PluginRegistry.self) private var registry
    @Environment(AppHost.self) private var host
    @Environment(\.dismiss) private var dismiss

    @State private var draft = Item(title: "", type: .movie)
    @State private var loaded = false
    @State private var results: [SourceHit] = []
    @State private var searchError: String?
    @State private var searching = false
    @State private var filling = false
    @State private var picked = false
    @FocusState private var titleFocused: Bool
    @State private var photo: PhotosPickerItem?
    @State private var showCamera = false
    @State private var askingURL = false
    @State private var posterURLText = ""
    @State private var genreText = ""
    @State private var collections: Set<String> = []
    @State private var confirmingDelete = false
    @State private var addedCount = 0
    @State private var extras: TMDb.Extras?
    @State private var trailers = TrailerPlayer()
    @Environment(\.openURL) private var openURL

    private var isNew: Bool { itemID == nil }
    private var canSave: Bool { !draft.title.trimmingCharacters(in: .whitespaces).isEmpty && !filling }
    private var catalog: SourceCatalog { SourceCatalog(registry: registry, settings: store.settings) }

    var body: some View {
        NucleusSheetPage(isNew ? "Add title" : "Edit title", confirmTitle: isNew ? "Add" : "Save", canConfirm: canSave,
                         onCancel: { dismiss() }, onConfirm: { save(another: false) }) {
            if addedCount > 0 {
                Label("Added \(addedCount)", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Nucleus.success)
                    .padding(.bottom, 12)
            }
            titleSection
            if isNew, picked, draft.tmdbId != nil { aboutSection }
            posterSection
            detailsSection
            ratingSection
            genresSection
            NucleusSection("Collections") { CollectionSelect(selection: $collections) }
            if draft.tmdbId == nil {
                customAboutSection
                // Cast belongs to the Cast & Crew plugin; with it off there's nowhere to show it.
                if host.canOpenPeople {
                    CustomCreditsSection(credits: Binding(get: { draft.customCredits }, set: { draft.customCredits = $0 }))
                }
            }
            linksSection
            NucleusSection("Notes") {
                TextField("Anything to remember", text: Binding(get: { draft.notes }, set: { draft.notes = $0 }), axis: .vertical)
                    .lineLimit(3...10)
                    .padding(16)
            }
            if isNew {
                Button { save(another: true) } label: { Label("Add and start another", systemImage: "plus") }
                    .buttonStyle(NucleusSecondaryButtonStyle())
                    .disabled(!canSave)
                    .padding(.bottom, 16)
            } else {
                NucleusSection {
                    Button { confirmingDelete = true } label: { NucleusRow("Delete title", titleColor: Nucleus.danger) }
                        .buttonStyle(NucleusRowButtonStyle())
                }
            }
        }
        .interactiveDismissDisabled(!isNew && hasChanges)
        .onAppear(perform: load)
        .task(id: searchKey) { await search() }
        .task(id: isNew && picked ? draft.tmdbId : nil) { await loadExtras() }
        .background {
            TrailerPlayerHost(player: trailers).frame(width: 2, height: 2).opacity(0.01).accessibilityHidden(true)
        }
        .onAppear {
            trailers.onFailure = { key in
                if let url = URL(string: "https://www.youtube.com/watch?v=\(key)") { openURL(url) }
            }
        }
        .onChange(of: photo) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                draft.posterUrl = Images.dataURL(data)
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in draft.posterUrl = Images.dataURL(image) }.ignoresSafeArea()
        }
        .alert("Poster URL", isPresented: $askingURL) {
            TextField("https://", text: $posterURLText).keyboardType(.URL).textInputAutocapitalization(.never)
            Button("Use") {
                let url = posterURLText.trimmingCharacters(in: .whitespaces)
                if URL(string: url)?.scheme?.hasPrefix("http") == true { draft.posterUrl = url }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(Text("Delete “\(draft.title)”?"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let itemID { store.deleteItem(itemID) }
                Haptics.warning()
                dismiss()
            }
        }
    }

    // MARK: Sections

    private var titleSection: some View {
        NucleusSection(footer: searchFooter) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Nucleus.secondaryText)
                TextField(onlyTMDb ? LocalizedStringKey("Title, or search TMDb") : LocalizedStringKey("Title, or search"), text: Binding(get: { draft.title }, set: { draft.title = $0; picked = false }))
                    .font(.system(size: 17, weight: .medium))
                    .focused($titleFocused)
                    .submitLabel(.done)
                if searching || filling { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 16).frame(minHeight: 54)

            if !picked {
                ForEach(results) { r in
                    Button { pick(r) } label: {
                        HStack(spacing: 12) {
                            AsyncImage(url: r.thumbnail) { $0.resizable().scaledToFill() } placeholder: { Nucleus.well }
                                .frame(width: 36, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: r.title).font(.system(size: 15, weight: .medium)).foregroundStyle(Nucleus.primaryText).lineLimit(2)
                                HStack(spacing: 4) {
                                    Text(r.type.title)
                                    if !r.detail.isEmpty { Text(verbatim: "· \(r.detail)") }
                                    if catalog.active.count > 1 { Text(verbatim: "· \(r.sourceName)") }
                                }
                                .font(.system(size: 12)).foregroundStyle(Nucleus.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(Nucleus.accent)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8).contentShape(Rectangle())
                    }
                    .buttonStyle(NucleusRowButtonStyle())
                }
            }
        }
    }

    /// What the picked TMDb title is about, so it's easy to tell it's the right one before adding it.
    @ViewBuilder
    private var aboutSection: some View {
        if let extras {
            if !extras.overview.isEmpty {
                NucleusSection("Overview") {
                    Text(verbatim: extras.overview)
                        .font(.system(size: 15))
                        .foregroundStyle(Nucleus.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            }
            if !extras.videos.isEmpty {
                TrailersSection(videos: extras.videos, loadingKey: trailers.loadingKey) { video in
                    Haptics.tap()
                    trailers.play(video.key)
                }
            }
            if let tmdbID = draft.tmdbId {
                PluginItemSections(type: draft.type, tmdbID: tmdbID, title: draft.title, canNavigate: false)
            }
        }
    }

    /// Titles TMDb doesn't have get their description and trailer by hand.
    private var customAboutSection: some View {
        let link = draft.trailerUrl ?? ""
        let badLink = !link.isEmpty && TMDb.Video.youTubeKey(link) == nil
        return NucleusSection("Description & trailer", footer: badLink ? Text("That doesn't look like a YouTube link.").foregroundStyle(Nucleus.danger) : nil) {
            TextField("Description", text: Binding(get: { draft.overview }, set: { draft.overview = $0 }), axis: .vertical)
                .lineLimit(3...10)
                .padding(16)
            HStack {
                Text("Trailer").foregroundStyle(Nucleus.secondaryText)
                TextField("YouTube link", text: Binding(get: { draft.trailerUrl ?? "" }, set: { draft.trailerUrl = $0 }))
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 16).frame(minHeight: 50)
        }
    }

    private func loadExtras() async {
        let key = store.settings.tmdbApiKey
        guard isNew, picked, let id = draft.tmdbId, !key.isEmpty else { extras = nil; return }
        extras = try? await TMDbExtrasCache.shared.extras(id, type: draft.type, apiKey: key)
        if let first = extras?.videos.first { trailers.prepare(first.key) }
    }

    private var searchFooter: Text? {
        if let searchError { return Text(verbatim: searchError) }
        if catalog.active.isEmpty, store.settings.searchSources.contains(TMDbSource.id) {
            return Text("Add a TMDb API key in Settings to search and fill in details automatically.")
        }
        return nil
    }

    private var onlyTMDb: Bool { catalog.active.map(\.id) == [TMDbSource.id] || catalog.active.isEmpty }

    private var posterSection: some View {
        NucleusSection("Poster") {
            HStack(alignment: .top, spacing: 16) {
                Poster(url: draft.posterUrl, type: draft.type, cornerRadius: 12)
                    .frame(width: 92, height: 138)
                VStack(alignment: .leading, spacing: 4) {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Choose photo", systemImage: "photo").frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 36)
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showCamera = true } label: {
                            Label("Take photo", systemImage: "camera").frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 36)
                        }
                    }
                    Button { posterURLText = ""; askingURL = true } label: {
                        Label("Paste URL", systemImage: "link").frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 36)
                    }
                    if draft.posterUrl != nil {
                        Button(role: .destructive) { draft.posterUrl = nil } label: {
                            Label("Remove", systemImage: "trash").frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 36)
                        }
                        .foregroundStyle(Nucleus.danger)
                    }
                }
                .font(.system(size: 15))
            }
            .padding(16)
        }
    }

    private var detailsSection: some View {
        NucleusSection("Details") {
            NucleusSegmented(selection: Binding(get: { draft.type }, set: { draft.type = $0 }),
                             items: [(.movie, "Movie"), (.show, "Show")], fill: true)
                .padding(12)
            NucleusSegmented(selection: Binding(get: { draft.status }, set: { draft.status = $0 }),
                             items: [(.planned, "Planned"), (.watching, "Watching"), (.completed, "Completed")], fill: true)
                .padding(12)
            numberField("Year", value: Binding(get: { draft.year }, set: { draft.year = $0 }), range: 1888...2100)
            if draft.type == .movie {
                numberField("Runtime (minutes)", value: Binding(get: { draft.runtime }, set: { draft.runtime = $0 }))
            } else {
                numberField("Seasons", value: Binding(get: { draft.seasons }, set: { draft.seasons = $0 }))
                numberField("Episodes", value: Binding(get: { draft.episodes }, set: { draft.episodes = $0 }))
                numberField("Total runtime (minutes)", value: Binding(get: { draft.showRuntime }, set: { draft.showRuntime = $0 }))
            }
        }
    }

    private var ratingSection: some View {
        NucleusSection("Rating", footer: draft.tmdbRating.map { Text("TMDb rates it \(String(format: "%.1f", $0)).") }) {
            RatingControl(rating: Binding(get: { draft.rating }, set: { draft.rating = $0 }))
                .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            Toggle(isOn: Binding(get: { draft.favorite }, set: { draft.favorite = $0 })) {
                Label { Text("Favorite") } icon: { IconTile("heart.fill", tint: .rose) }
            }
            .tint(Color(hex: 0x34C759))
            .padding(.horizontal, 16).frame(minHeight: 52)
        }
    }

    private var genresSection: some View {
        NucleusSection("Genres") {
            if !draft.genres.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(draft.genres, id: \.self) { g in
                        Button { draft.genres.removeAll { $0 == g } } label: {
                            HStack(spacing: 4) {
                                Text(verbatim: g)
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).frame(height: 28)
                            .background(Capsule().fill(GenrePalette.color(g)))
                        }
                        .buttonStyle(NucleusPressStyle())
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            TextField("Add a genre", text: $genreText)
                .onSubmit(addGenre)
                .onChange(of: genreText) { _, text in if text.hasSuffix(",") { addGenre() } }
                .submitLabel(.done)
                .padding(.horizontal, 16).frame(minHeight: 50)
        }
    }

    private var linksSection: some View {
        NucleusSection("Links", footer: Text("Where “Open” takes this title. Default uses the choice in Settings.")) {
            HStack {
                Text("Where to watch").foregroundStyle(Nucleus.secondaryText)
                TextField("https://", text: Binding(get: { draft.watchLink ?? "" }, set: { draft.watchLink = $0.isEmpty ? nil : $0 }))
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 16).frame(minHeight: 50)
            Picker("Open on", selection: Binding(get: { draft.openTarget?.type }, set: { kind in
                if let kind { var t = draft.openTarget ?? OpenTarget(); t.type = kind; draft.openTarget = t } else { draft.openTarget = nil }
            })) {
                Text("Default").tag(OpenTarget.Kind?.none)
                ForEach(OpenTarget.Kind.allCases, id: \.self) { Text(verbatim: $0 == .custom ? String(localized: "Custom") : $0.label).tag(OpenTarget.Kind?.some($0)) }
            }
            .padding(.horizontal, 16).frame(minHeight: 50)
            if draft.openTarget?.type == .custom {
                TextField("https://example.com/search?q={title}", text: Binding(
                    get: { draft.openTarget?.customUrl ?? "" },
                    set: { var t = draft.openTarget ?? OpenTarget(type: .custom); t.customUrl = $0; draft.openTarget = t }))
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.system(size: 14, design: .monospaced))
                    .padding(.horizontal, 16).frame(minHeight: 50)
                Picker("Title format", selection: Binding(
                    get: { draft.openTarget?.titleFormat ?? .raw },
                    set: { var t = draft.openTarget ?? OpenTarget(type: .custom); t.titleFormat = $0; draft.openTarget = t })) {
                    ForEach(OpenTarget.TitleFormat.allCases, id: \.self) { Text(verbatim: OpenLinks.format("The Matrix", $0)).tag($0) }
                }
                .padding(.horizontal, 16).frame(minHeight: 50)
            }
        }
    }

    private func numberField(_ title: LocalizedStringKey, value: Binding<Int?>, range: ClosedRange<Int>? = nil) -> some View {
        HStack {
            Text(title).foregroundStyle(Nucleus.primaryText)
            Spacer()
            TextField("—", text: Binding(
                get: { value.wrappedValue.map(String.init) ?? "" },
                set: { text in
                    let digits = text.filter(\.isNumber)
                    guard let n = Int(digits) else { value.wrappedValue = nil; return }
                    value.wrappedValue = range.map { min(max(n, $0.lowerBound), $0.upperBound) } ?? n
                }))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
        }
        .padding(.horizontal, 16).frame(minHeight: 50)
    }

    // MARK: Behaviour

    private var searchKey: String { picked ? "" : draft.title.trimmingCharacters(in: .whitespaces) }

    private func search() async {
        let q = searchKey
        let sources = catalog.active
        guard q.count >= 2, !sources.isEmpty, titleFocused || isNew else {
            results = []
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        // One source failing (no network, a bad key) shouldn't hide what the others found.
        let outcomes = await withTaskGroup(of: (Int, Result<[SourceHit], Error>).self) { group in
            for (i, source) in sources.enumerated() {
                group.addTask {
                    do { return (i, .success(try await source.search(q))) } catch { return (i, .failure(error)) }
                }
            }
            var all: [(Int, Result<[SourceHit], Error>)] = []
            for await outcome in group { all.append(outcome) }
            return all.sorted { $0.0 < $1.0 }
        }
        guard !Task.isCancelled else { return }
        let perSource = sources.count > 1 ? 5 : 7
        results = outcomes.flatMap { (try? $0.1.get().prefix(perSource)).map(Array.init) ?? [] }
        let failure = outcomes.compactMap { outcome -> Error? in
            if case .failure(let error) = outcome.1, (error as? URLError)?.code != .cancelled, !(error is CancellationError) { return error }
            return nil
        }.first
        searchError = results.isEmpty ? failure?.localizedDescription : nil
    }

    private func pick(_ hit: SourceHit) {
        Haptics.tap()
        picked = true
        titleFocused = false
        results = []
        filling = true
        let source = catalog.source(hit.sourceID)
        Task {
            var next = draft
            do {
                guard let source else { throw URLError(.unsupportedURL) }
                try await source.fill(&next, from: hit)
                draft = next
            } catch {
                draft.title = hit.title
                draft.type = hit.type
                searchError = error.localizedDescription
            }
            filling = false
        }
    }

    private func addGenre() {
        let names = genreText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        draft.genres = WatchlistStore.cleanGenres(draft.genres + names)
        genreText = ""
    }

    private var hasChanges: Bool {
        guard let itemID, let saved = store.item(itemID) else { return false }
        return saved.raw != draft.raw || Set(saved.collectionIds) != collections
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let itemID, let existing = store.item(itemID) {
            draft = existing
            collections = Set(existing.collectionIds)
            picked = true
        } else {
            collections = collectionID.map { [$0] } ?? []
            titleFocused = true
        }
    }

    private func save(another: Bool) {
        if !genreText.isEmpty { addGenre() }
        var item = draft
        item.collectionIds = store.collections.map(\.id).filter(collections.contains)
        if let itemID {
            store.updateItem(itemID) { $0.raw = item.raw }
        } else {
            store.createItem(item)
        }
        Haptics.success()
        if another {
            addedCount += 1
            draft = Item(title: "", type: draft.type)
            extras = nil
            results = []
            picked = false
            titleFocused = true
        } else {
            dismiss()
        }
    }
}

/// The camera, for photographing a poster or a box.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
