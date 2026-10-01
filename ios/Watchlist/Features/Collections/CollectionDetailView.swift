import NucleusUI
import SwiftUI

struct CollectionDetailView: View {
    let collectionID: String
    @Environment(WatchlistStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(Navigator.self) private var navigator
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ItemFilter()
    @State private var text = ""
    @State private var confirmingDelete = false

    var body: some View {
        if let collection = store.collection(collectionID) {
            let all = store.orderedMembers(of: collection)
            let shown = all.filter { filter.matches($0) && (text.isEmpty || $0.title.localizedCaseInsensitiveContains(text) || $0.notes.localizedCaseInsensitiveContains(text)) }
            ZStack {
                NucleusBackground()
                ItemGrid(items: shown, style: preferences.gridStyle, collectionID: collectionID) {
                    header(collection, count: all.count)
                    if all.isEmpty {
                        VStack(spacing: 16) {
                            NucleusEmptyState("tray", title: "Nothing here yet", message: "Add titles from your watchlist.")
                            Button("Add titles") { navigator.present(.addItems(collectionID)) }
                                .buttonStyle(NucleusPrimaryButtonStyle())
                                .frame(maxWidth: 260)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    } else if shown.isEmpty {
                        VStack(spacing: 12) {
                            NucleusEmptyState("line.3.horizontal.decrease.circle", title: "No matches", message: "Nothing fits these filters.")
                            Button("Clear filters") { filter = ItemFilter(); text = "" }.buttonStyle(NucleusSecondaryButtonStyle())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .modifier(DeleteCollectionDialog(collection: collection, isPresented: $confirmingDelete) { dismiss() })
        } else {
            NucleusPage {
                NucleusEmptyState("folder.badge.questionmark", title: "Collection not found", message: "It may have been deleted on another device.")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            }
        }
    }

    private func header(_ collection: WatchCollection, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                GlassCircleButton("chevron.left") { dismiss() }.accessibilityLabel("Back")
                Spacer()
                GlassCircleButton("plus") { navigator.present(.addItems(collectionID)) }.accessibilityLabel("Add titles")
                Menu {
                    Button { navigator.present(.editCollection(collectionID)) } label: { Label("Edit", systemImage: "pencil") }
                    if count > 1 {
                        Button { navigator.present(.reorder(collectionID)) } label: { Label("Reorder", systemImage: "arrow.up.arrow.down") }
                    }
                    Divider()
                    Button(role: .destructive) { confirmingDelete = true } label: { DestructiveLabel("Delete collection", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Nucleus.glyph)
                        .frame(width: 40, height: 40)
                        .nucleusGlass(in: Circle(), interactive: true)
                }
                .accessibilityLabel("More")
            }
            .frame(height: 40)

            Text(verbatim: collection.name)
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(Nucleus.primaryText)
                .padding(.top, 16)
            Text("\(count) titles")
                .font(.system(size: 14))
                .foregroundStyle(Nucleus.secondaryText)
                .padding(.top, 2)
            if !collection.details.isEmpty {
                Text(verbatim: collection.details)
                    .font(.system(size: 15))
                    .foregroundStyle(Nucleus.glyph)
                    .padding(.top, 8)
            }

            if count > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    NucleusSegmented(selection: $filter.status, items: [
                        (nil, "All"), (.planned, "Planned"), (.watching, "Watching"), (.completed, "Watched"),
                    ], fill: true)
                    HStack(spacing: 8) {
                        NucleusSegmented(selection: $filter.type, items: [(nil, "All"), (.movie, "Movies"), (.show, "Shows")]).fixedSize()
                        Spacer(minLength: 0)
                        Button {
                            Haptics.selection()
                            filter.favoritesOnly.toggle()
                        } label: {
                            Image(systemName: filter.favoritesOnly ? "heart.fill" : "heart")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(filter.favoritesOnly ? Nucleus.accent : Nucleus.glyph)
                                .frame(width: 40, height: 40)
                                .nucleusGlass(in: Circle(), interactive: true)
                        }
                        .buttonStyle(NucleusPressStyle())
                        .accessibilityLabel("Favorites only")
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Nucleus.secondaryText)
                        TextField("Filter this collection", text: $text)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !text.isEmpty {
                            Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Nucleus.secondaryText) }
                        }
                    }
                    .font(.system(size: 15))
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .nucleusGlass(in: Capsule())
                }
                .padding(.top, 20)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }
}

/// Drag titles into the order the collection shows them in.
struct ReorderSheet: View {
    let collectionID: String
    @Environment(WatchlistStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var order: [Item] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(order) { item in
                    HStack(spacing: 12) {
                        Poster(url: item.posterUrl, type: item.type, cornerRadius: 6).frame(width: 34, height: 51)
                        Text(verbatim: item.title).lineLimit(1)
                    }
                }
                .onMove { order.move(fromOffsets: $0, toOffset: $1) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Haptics.success()
                        store.saveOrder(order.map(\.id), in: collectionID)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            if let col = store.collection(collectionID) { order = store.orderedMembers(of: col) }
        }
    }
}
