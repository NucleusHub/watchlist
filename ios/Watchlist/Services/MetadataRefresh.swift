import Foundation
import Observation

/// Fills in missing details for every title from TMDb, one at a time.
@MainActor
@Observable
final class MetadataRefresh {
    private(set) var running = false
    private(set) var done = 0
    private(set) var total = 0
    private(set) var updated = 0
    private(set) var notFound = 0
    private(set) var finished = false
    @ObservationIgnored private var task: Task<Void, Never>?

    func start(store: WatchlistStore) {
        guard !running else { return }
        let tmdb = TMDb(apiKey: store.settings.tmdbApiKey)
        let ids = store.items.map(\.id)
        running = true
        finished = false
        done = 0
        updated = 0
        notFound = 0
        total = ids.count
        task = Task {
            for id in ids {
                if Task.isCancelled { break }
                if var item = store.item(id) {
                    let before = item.raw
                    do {
                        if try await tmdb.refresh(&item) {
                            if item.raw != before {
                                let raw = item.raw
                                store.updateItem(id) { $0.raw = raw }
                                updated += 1
                            }
                        } else {
                            notFound += 1
                        }
                    } catch {
                        notFound += 1
                    }
                }
                done += 1
                // Gentle on TMDb's rate limit.
                try? await Task.sleep(for: .milliseconds(300))
            }
            running = false
            finished = true
        }
    }

    func cancel() {
        task?.cancel()
        running = false
        finished = true
    }
}
