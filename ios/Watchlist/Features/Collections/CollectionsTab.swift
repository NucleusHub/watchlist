import NucleusUI
import SwiftUI
import WatchlistPluginKit

struct CollectionsTab: View {
    @Environment(WatchlistStore.self) private var store
    @Environment(Navigator.self) private var navigator

    var body: some View {
        if store.collections.isEmpty {
            ScrollView {
                VStack(spacing: 20) {
                    NucleusEmptyState("folder", title: "No collections yet", message: "Group titles into lists like “Weekend picks” or “Christmas”.")
                    Button("New collection") { navigator.present(.newCollection) }
                        .buttonStyle(NucleusPrimaryButtonStyle())
                        .frame(maxWidth: 280)
                }
                .padding(.top, 60)
                .frame(maxWidth: .infinity)
                .nucleusAppear()
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(Array(store.collections.enumerated()), id: \.element.id) { index, col in
                        CollectionCard(collection: col).nucleusAppear(min(index, 8))
                    }
                    SwipeSafeButton { navigator.present(.newCollection) } label: {
                        Label("New collection", systemImage: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Nucleus.accent)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .strokeBorder(Nucleus.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(NucleusPressStyle())
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
    }
}

/// A collection as one big poster: its cover, with the name and count on it.
struct CollectionCard: View {
    let collection: WatchCollection
    @Environment(WatchlistStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @State private var confirmingDelete = false

    var body: some View {
        SwipeSafeButton { navigator.open(.collection(collection.id)) } label: {
            CollectionCover(collection: collection)
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: collection.name)
                            .font(.system(size: 22, weight: .bold))
                            .tracking(-0.3)
                            .lineLimit(2)
                        Text("\(store.members(of: collection.id).count) titles")
                            .font(.system(size: 13, weight: .medium))
                            .opacity(0.8)
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                    // The text and its shadow as one bitmap, so the shadow isn't redrawn while the page moves.
                    .drawingGroup()
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .bakedShadow(cornerRadius: 26, color: .black.opacity(0.3), radius: 14, y: 8)
                .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(NucleusPressStyle(scale: 0.98))
        .contextMenu {
            Button { navigator.present(.editCollection(collection.id)) } label: { Label("Edit", systemImage: "pencil") }
            Button { navigator.present(.addItems(collection.id)) } label: { Label("Add titles", systemImage: "plus") }
            Divider()
            Button(role: .destructive) { confirmingDelete = true } label: { DestructiveLabel("Delete", systemImage: "trash") }
        }
        .modifier(DeleteCollectionDialog(collection: collection, isPresented: $confirmingDelete))
    }
}

struct DeleteCollectionDialog: ViewModifier {
    let collection: WatchCollection
    @Binding var isPresented: Bool
    var onDeleted: () -> Void = {}
    @Environment(WatchlistStore.self) private var store

    func body(content: Content) -> some View {
        content.confirmationDialog(Text("Delete “\(collection.name)”?"), isPresented: $isPresented, titleVisibility: .visible) {
            Button("Delete collection", role: .destructive) {
                Haptics.warning()
                withAnimation(NucleusMotion.quick) { store.deleteCollection(collection.id) }
                onDeleted()
            }
        } message: {
            Text("The titles stay on your watchlist.")
        }
    }
}
