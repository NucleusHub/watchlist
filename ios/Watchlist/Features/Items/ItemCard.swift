import NucleusUI
import SwiftUI
import WatchlistPluginKit

/// A title as a poster card (grid layouts).
struct ItemCard: View {
    let item: Item
    var compact = false
    var collectionID: String? = nil
    @Environment(Navigator.self) private var navigator
    @State private var confirmingDelete = false

    var body: some View {
        SwipeSafeButton { navigator.open(.item(item.id)) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Poster(url: item.posterUrl, type: item.type, cornerRadius: compact ? 14 : 18)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .overlay(alignment: .topLeading) { WatchedButton(item: item, size: compact ? 26 : 30).padding(compact ? 6 : 8) }
                    .overlay(alignment: .topTrailing) {
                        if item.favorite || !compact { FavoriteButton(item: item, size: compact ? 26 : 30).padding(compact ? 6 : 8) }
                    }
                    .overlay(alignment: .bottom) { progressBar }
                    .bakedShadow(cornerRadius: compact ? 14 : 18, radius: 10, y: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: compact ? 13 : 15, weight: .semibold))
                        .foregroundStyle(item.isCompleted ? Nucleus.secondaryText : Nucleus.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !item.metaLine.isEmpty {
                        Text(item.metaLine)
                            .font(.system(size: compact ? 11 : 12))
                            .foregroundStyle(Nucleus.secondaryText)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(NucleusPressStyle(scale: 0.97))
        .contextMenu {
            ItemMenu(item: item, collectionID: collectionID) { confirmingDelete = true }
        }
        .modifier(DeleteItemDialog(item: item, isPresented: $confirmingDelete))
    }

    @ViewBuilder
    private var progressBar: some View {
        let fraction = item.watchedFraction
        if item.isShow, fraction > 0, fraction < 1 {
            GeometryReader { geo in
                Capsule().fill(.white.opacity(0.25))
                    .overlay(alignment: .leading) {
                        Capsule().fill(WatchStatus.watching.color).frame(width: geo.size.width * fraction)
                    }
            }
            .frame(height: 4)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
    }
}

/// A title as a list row, with native swipe actions.
struct ItemRow: View {
    let item: Item
    var collectionID: String? = nil
    @Environment(Navigator.self) private var navigator
    @Environment(WatchlistStore.self) private var store
    @State private var confirmingDelete = false

    var body: some View {
        Button { navigator.open(.item(item.id)) } label: {
            HStack(spacing: 12) {
                Poster(url: item.posterUrl, type: item.type, cornerRadius: 8)
                    .frame(width: 52, height: 78)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(item.isCompleted ? Nucleus.secondaryText : Nucleus.primaryText)
                        .lineLimit(2)
                    if !item.metaLine.isEmpty {
                        Text(item.metaLine).font(.system(size: 13)).foregroundStyle(Nucleus.secondaryText).lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Tag(text: Text(item.status.title), color: item.status.color)
                        if let g = item.genres.first { Tag(text: Text(verbatim: g)) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 8) {
                    WatchedButton(item: item, size: 28)
                    FavoriteButton(item: item, size: 28, onPoster: false)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(NucleusRowButtonStyle())
        .contextMenu {
            ItemMenu(item: item, collectionID: collectionID) { confirmingDelete = true }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if item.isCompleted {
                Button { store.toggleFavorite(item.id) } label: { Label("Favorite", systemImage: item.favorite ? "heart.slash" : "heart.fill") }
                    .tint(Color(hex: 0xF43F5E))
            } else {
                Button { Haptics.success(); store.markWatched(item.id) } label: { Label("Watched", systemImage: "checkmark") }
                    .tint(WatchStatus.completed.color)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { confirmingDelete = true } label: { Label("Delete", systemImage: "trash") }
                .tint(.red)
        }
        .modifier(DeleteItemDialog(item: item, isPresented: $confirmingDelete))
    }
}

/// Titles in the chosen layout: a native list (swipe actions) or a poster grid.
struct ItemGrid<Header: View>: View {
    let items: [Item]
    let style: GridStyle
    var collectionID: String? = nil
    @ViewBuilder var header: Header

    var body: some View {
        if style == .list {
            List {
                header
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                ForEach(items) { item in
                    ItemRow(item: item, collectionID: collectionID)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear.nucleusGlass(cornerRadius: 20).padding(.horizontal, 16).padding(.vertical, 6))
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: style == .small ? 12 : 16, alignment: .top),
                                             count: style == .small ? 3 : 2),
                              spacing: style == .small ? 16 : 20) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ItemCard(item: item, compact: style == .small, collectionID: collectionID)
                                .nucleusAppear(min(index, 12))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
    }
}
