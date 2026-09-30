import SwiftUI
import WatchKit

struct ItemDetailView: View {
    @EnvironmentObject private var store: WatchStore
    let itemId: String

    var body: some View {
        // Read live from the store so the buttons reflect the tap straight away.
        if let item = store.item(itemId) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Poster(url: item.posterURL, isShow: item.isShow)
                        .aspectRatio(2 / 3, contentMode: .fit)
                        .frame(maxWidth: 110)
                        .frame(maxWidth: .infinity)

                    Text(item.title).font(.headline)

                    if !facts(item).isEmpty {
                        Text(facts(item)).font(.footnote).foregroundStyle(.secondary)
                    }
                    if !item.genres.isEmpty {
                        Text(item.genres.joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary)
                    }

                    Button {
                        store.toggleCompleted(item)
                        WKInterfaceDevice.current().play(item.isCompleted ? .click : .success)
                    } label: {
                        Label(item.isCompleted ? "Watched" : "Mark as watched",
                              systemImage: item.isCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                    }
                    .tint(item.isCompleted ? .green : nil)

                    Button {
                        store.toggleFavorite(item)
                        WKInterfaceDevice.current().play(.click)
                    } label: {
                        Label(item.favorite ? "Favorite" : "Add to favorites",
                              systemImage: item.favorite ? "heart.fill" : "heart")
                    }
                    .tint(item.favorite ? .favorite : nil)
                }
            }
            .navigationTitle(item.isShow ? "Show" : "Movie")
        } else {
            EmptyState(text: "This item is no longer on your watchlist.")
        }
    }

    private func facts(_ item: WatchItem) -> String {
        var parts: [String] = []
        if let year = item.year { parts.append(String(Int(year))) }
        if item.isShow, let seasons = item.seasons, seasons > 0 {
            parts.append(String(localized: "\(Int(seasons)) seasons"))
        }
        if let minutes = item.isShow ? item.showRuntime : item.runtime, minutes > 0 {
            let m = Int(minutes)
            parts.append(m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min")
        }
        if let score = item.tmdbRating, score > 0 { parts.append("★ " + String(format: "%.1f", score)) }
        return parts.joined(separator: " · ")
    }
}
