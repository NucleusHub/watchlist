import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        NavigationStack {
            TabView {
                ItemListView(title: Text("Watchlist"), items: store.items, emptyText: "Add movies and shows on your iPhone.")
                CollectionListView()
            }
            .tabViewStyle(.verticalPage)
            .navigationDestination(for: WatchItem.self) { ItemDetailView(itemId: $0.id) }
            .navigationDestination(for: WatchCollection.self) { collection in
                ItemListView(title: Text(verbatim: collection.name), items: store.items(in: collection), emptyText: "Nothing in this collection yet.")
            }
        }
    }
}

struct ItemListView: View {
    @EnvironmentObject private var store: WatchStore
    let title: Text
    let items: [WatchItem]
    let emptyText: LocalizedStringKey

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyState(text: store.hasSynced ? emptyText : "Open Watchlist on your iPhone to sync.")
            } else {
                List(items) { item in
                    NavigationLink(value: item) { ItemRow(item: item) }
                        .swipeActions(edge: .leading) {
                            Button { store.toggleFavorite(item) } label: {
                                Image(systemName: item.favorite ? "heart.slash" : "heart.fill")
                            }
                            .tint(.favorite)
                        }
                        .swipeActions(edge: .trailing) {
                            Button { store.toggleCompleted(item) } label: {
                                Image(systemName: item.isCompleted ? "arrow.uturn.backward" : "checkmark")
                            }
                            .tint(.green)
                        }
                }
            }
        }
        .navigationTitle(title)
    }
}

struct CollectionListView: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        Group {
            if store.collections.isEmpty {
                EmptyState(text: "Create collections on your iPhone.")
            } else {
                List(store.collections) { collection in
                    NavigationLink(value: collection) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(collection.name).lineLimit(2)
                            Text("\(store.count(in: collection)) items")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Collections")
    }
}

struct ItemRow: View {
    let item: WatchItem

    var body: some View {
        HStack(spacing: 8) {
            Poster(url: item.posterURL, isShow: item.isShow)
                .frame(width: 32, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .lineLimit(2)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                HStack(spacing: 4) {
                    if item.isCompleted {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    if item.favorite {
                        Image(systemName: "heart.fill").foregroundStyle(Color.favorite)
                    }
                    if let year = item.year {
                        Text(String(Int(year))).foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)
            }
        }
    }
}

struct Poster: View {
    let url: URL?
    let isShow: Bool

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Color.brand.opacity(0.25)
                    Image(systemName: isShow ? "tv" : "film").foregroundStyle(.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct EmptyState: View {
    let text: LocalizedStringKey

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "popcorn").font(.title2).foregroundStyle(Color.brand)
            Text(text).font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .padding()
    }
}
