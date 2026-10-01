import NucleusUI
import PhotosUI
import SwiftUI

/// New or edit collection: name, description and how its cover is made.
struct CollectionEditor: View {
    let collectionID: String?
    @Environment(WatchlistStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    enum CoverMode: Hashable { case auto, image, titles }

    @State private var name = ""
    @State private var details = ""
    @State private var mode: CoverMode = .auto
    @State private var coverCount = 4
    @State private var coverUrl: String?
    @State private var coverItemIds: [String] = []
    @State private var newItemIds: Set<String> = []
    @State private var photo: PhotosPickerItem?
    @State private var loaded = false

    private var existing: WatchCollection? { collectionID.flatMap(store.collection) }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private var preview: WatchCollection {
        var c = existing ?? WatchCollection(name: name)
        c.name = name
        c.coverUrl = mode == .image ? coverUrl : nil
        c.coverItemIds = mode == .titles ? coverItemIds : []
        c.coverCount = coverCount
        return c
    }

    private var memberPool: [Item] {
        if let existing { return store.members(of: existing.id) }
        return store.items.filter { newItemIds.contains($0.id) }
    }

    private var previewPosters: [String] {
        switch mode {
        case .image: return []
        case .titles:
            let byID = Dictionary(store.document.items.map { ($0.id, $0.posterUrl) }, uniquingKeysWith: { a, _ in a })
            return coverItemIds.compactMap { byID[$0] ?? nil }
        case .auto:
            return Array(memberPool.compactMap(\.posterUrl).prefix(coverCount))
        }
    }

    var body: some View {
        NucleusSheetPage(existing == nil ? "New collection" : "Edit collection", canConfirm: canSave, onCancel: { dismiss() }, onConfirm: save) {
            CollectionCover(collection: preview, posters: previewPosters)
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.bottom, 24)

            NucleusSection {
                NucleusField("Name", text: $name, prompt: String(localized: "Weekend picks"))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Description").font(.system(size: 13)).foregroundStyle(Nucleus.secondaryText)
                    TextField("Optional", text: $details, axis: .vertical).lineLimit(2...5)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }

            NucleusSection("Cover") {
                NucleusSegmented(selection: $mode, items: [(.auto, "Automatic"), (.image, "Image"), (.titles, "Pick titles")], fill: true)
                    .padding(12)
                switch mode {
                case .auto:
                    Stepper(value: $coverCount, in: 1...8) {
                        Text("Posters: \(coverCount)")
                    }
                    .padding(.horizontal, 16).frame(minHeight: 52)
                case .image:
                    PhotosPicker(selection: $photo, matching: .images) {
                        NucleusRow(coverUrl == nil ? "Choose a photo" : "Replace photo", icon: IconTile("photo", tint: .violet)) { Chevron() }
                    }
                    .buttonStyle(NucleusRowButtonStyle())
                    if coverUrl != nil {
                        Button { coverUrl = nil } label: { NucleusRow("Remove photo", titleColor: Nucleus.danger) }
                            .buttonStyle(NucleusRowButtonStyle())
                    }
                case .titles:
                    if memberPool.isEmpty {
                        Text("Add titles to the collection first.")
                            .font(.system(size: 14)).foregroundStyle(Nucleus.secondaryText)
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(memberPool) { item in
                                    let on = coverItemIds.contains(item.id)
                                    Button {
                                        Haptics.selection()
                                        if on { coverItemIds.removeAll { $0 == item.id } } else if coverItemIds.count < 8 { coverItemIds.append(item.id) }
                                    } label: {
                                        Poster(url: item.posterUrl, type: item.type, cornerRadius: 8)
                                            .frame(width: 60, height: 90)
                                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? Nucleus.accent : .clear, lineWidth: 3))
                                            .overlay(alignment: .topTrailing) {
                                                if on {
                                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, Nucleus.accent).padding(4)
                                                }
                                            }
                                    }
                                    .buttonStyle(NucleusPressStyle())
                                }
                            }
                            .padding(12)
                        }
                    }
                }
            }

            if existing == nil {
                NucleusSection("Titles", footer: Text("You can add more later.")) {
                    ItemPickerList(selection: $newItemIds, excluding: [])
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: photo) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                coverUrl = Images.dataURL(data, maxEdge: 720)
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let c = existing else { return }
        name = c.name
        details = c.details
        coverCount = c.coverCount
        coverUrl = c.coverUrl
        coverItemIds = c.coverItemIds.filter { id in store.item(id)?.isIn(c.id) == true }
        mode = c.coverUrl != nil ? .image : (!c.coverItemIds.isEmpty ? .titles : .auto)
    }

    private func save() {
        let url = mode == .image ? coverUrl : nil
        let picked = mode == .titles ? coverItemIds : []
        if let existing {
            store.updateCollection(existing.id) {
                $0.name = name
                $0.details = details
                $0.coverUrl = url
                $0.coverItemIds = picked
                $0.coverCount = coverCount
            }
        } else if let created = store.createCollection(name: name, description: details, coverUrl: url, coverItemIds: picked, coverCount: coverCount) {
            store.addItems(Array(newItemIds), to: created.id)
        }
        Haptics.success()
        dismiss()
    }
}

/// Titles with a checkbox each, filtered by a search field.
struct ItemPickerList: View {
    @Binding var selection: Set<String>
    let excluding: Set<String>
    @Environment(WatchlistStore.self) private var store
    @State private var query = ""

    var body: some View {
        let pool = store.items.filter { !excluding.contains($0.id) }
        let shown = pool.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Nucleus.secondaryText)
            TextField("Search titles", text: $query).autocorrectionDisabled()
        }
        .padding(.horizontal, 16).frame(minHeight: 48)
        if pool.isEmpty {
            Text(store.items.isEmpty ? "Your watchlist is empty." : "Every title is already here.")
                .font(.system(size: 14)).foregroundStyle(Nucleus.secondaryText)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
        ForEach(shown) { item in
            let on = selection.contains(item.id)
            Button {
                Haptics.selection()
                if on { selection.remove(item.id) } else { selection.insert(item.id) }
            } label: {
                HStack(spacing: 12) {
                    Poster(url: item.posterUrl, type: item.type, cornerRadius: 6).frame(width: 34, height: 51)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: item.title).font(.system(size: 15, weight: .medium)).foregroundStyle(Nucleus.primaryText).lineLimit(1)
                        Text(item.metaLine).font(.system(size: 12)).foregroundStyle(Nucleus.secondaryText)
                    }
                    Spacer()
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(on ? Nucleus.accent : Nucleus.secondaryText)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(NucleusRowButtonStyle())
        }
    }
}

struct AddItemsSheet: View {
    let collectionID: String
    @Environment(WatchlistStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<String> = []

    var body: some View {
        NucleusSheetPage("Add titles", confirmTitle: selection.isEmpty ? "Add" : "Add \(selection.count)", canConfirm: !selection.isEmpty,
                         onCancel: { dismiss() }, onConfirm: {
                             Haptics.success()
                             store.addItems(Array(selection), to: collectionID)
                             dismiss()
                         }) {
            NucleusSection {
                ItemPickerList(selection: $selection, excluding: Set(store.members(of: collectionID).map(\.id)))
            }
        }
    }
}

/// Which collections one title is in, with a quick way to make a new one.
struct ManageCollectionsSheet: View {
    let itemID: String
    @Environment(WatchlistStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<String> = []
    @State private var loaded = false

    var body: some View {
        NucleusSheetPage("Collections", onCancel: { dismiss() }, onConfirm: {
            Haptics.success()
            store.setCollections(store.collections.map(\.id).filter(selection.contains), for: itemID)
            dismiss()
        }) {
            if let item = store.item(itemID) {
                Text(verbatim: item.title).font(.system(size: 15)).foregroundStyle(Nucleus.secondaryText).padding(.bottom, 12)
            }
            NucleusSection {
                CollectionSelect(selection: $selection)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            selection = Set(store.item(itemID)?.collectionIds ?? [])
        }
    }
}

/// Collections with a checkbox each; typing a new name offers to create it.
struct CollectionSelect: View {
    @Binding var selection: Set<String>
    @Environment(WatchlistStore.self) private var store
    @State private var query = ""

    var body: some View {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let shown = store.collections.filter { needle.isEmpty || $0.name.localizedCaseInsensitiveContains(needle) }
        let exact = store.collections.contains { $0.name.compare(needle, options: .caseInsensitive) == .orderedSame }
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Nucleus.secondaryText)
            TextField("Search or create", text: $query).onSubmit(create)
        }
        .padding(.horizontal, 16).frame(minHeight: 48)
        if !needle.isEmpty && !exact {
            Button(action: create) {
                NucleusRow(verbatim: String(localized: "Create “\(needle)”"), icon: IconTile("plus", tint: .emerald))
            }
            .buttonStyle(NucleusRowButtonStyle())
        }
        if store.collections.isEmpty && needle.isEmpty {
            Text("No collections yet. Type a name to create one.")
                .font(.system(size: 14)).foregroundStyle(Nucleus.secondaryText)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
        ForEach(shown) { col in
            let on = selection.contains(col.id)
            Button {
                Haptics.selection()
                if on { selection.remove(col.id) } else { selection.insert(col.id) }
            } label: {
                NucleusRow(verbatim: col.name, subtitle: Text("\(store.members(of: col.id).count) titles")) {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(on ? Nucleus.accent : Nucleus.secondaryText)
                }
            }
            .buttonStyle(NucleusRowButtonStyle())
        }
    }

    private func create() {
        let name = query.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if let existing = store.collections.first(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }) {
            selection.insert(existing.id)
        } else if let created = store.createCollection(name: name) {
            Haptics.success()
            selection.insert(created.id)
        }
        query = ""
    }
}
