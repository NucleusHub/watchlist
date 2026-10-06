import Foundation

/// MovieDNA edits. They all go through `updateSettings`, so they sync like the rest of the settings.
extension WatchlistStore {
    var movieDNASettings: MovieDNASettings { settings.movieDNA }

    /// Worked out from the library, once per change; empty while MovieDNA is off.
    var movieDNA: MovieDNA {
        // Reading the document registers the view for changes even when the cache answers.
        let items = document.items
        if let cache = movieDNACache, cache.revision == revision { return cache.dna }
        let dna = MovieDNAEngine.profile(items: items, settings: settings.movieDNA)
        movieDNACache = (revision, dna)
        return dna
    }

    func setMovieDNAEnabled(_ enabled: Bool) {
        updateSettings { $0.movieDNA.enabled = enabled }
    }

    /// One Interested press: boosts the title and its genres. It can be pressed again for more, and it fades.
    func markInterested(_ item: Item) {
        guard movieDNASettings.enabled else { return }
        updateSettings { settings in
            settings.movieDNA.edit(DNAKey.title(item), kind: .title, name: item.title) { entry in
                entry.hidden = false
                entry.genres = item.genres
                entry.poster = Self.syncablePoster(item.posterUrl)
                entry.boosts = Array((entry.boosts + [Timestamp.now()]).suffix(MovieDNAEngine.maxBoosts))
            }
        }
    }

    func interestCount(_ item: Item) -> Int {
        movieDNASettings.entries[DNAKey.title(item)]?.boosts.count ?? 0
    }

    /// Sets a strength by hand; nil goes back to what the library says.
    func setDNAStrength(_ strength: Double?, for trait: DNATrait) {
        updateSettings { settings in
            settings.movieDNA.edit(trait.key, kind: trait.kind, name: trait.name) { $0.strength = strength.map { max(-100, min(100, $0.rounded())) } }
        }
    }

    func addToDNA(kind: DNAKind, key: String, name: String, poster: String? = nil, strength: Double) {
        updateSettings { settings in
            settings.movieDNA.edit(key, kind: kind, name: name) { entry in
                entry.hidden = false
                if let poster = Self.syncablePoster(poster) { entry.poster = poster }
                entry.strength = max(-100, min(100, strength.rounded()))
            }
        }
    }

    /// Keeps a title out of suggestions for good; its genres count a little against it.
    func markNotInterested(key: String, name: String, genres: [String]) {
        updateSettings { settings in
            settings.movieDNA.notInterested[key] = NotInterested(name: name, genres: genres, at: Timestamp.now())
        }
    }

    func clearNotInterested(_ key: String) {
        updateSettings { $0.movieDNA.notInterested[key] = nil }
    }

    /// Follows work with MovieDNA off too; they only count once it's on.
    func setFollowing(_ following: Bool, personID: Int, name: String, photo: String?) {
        updateSettings { settings in
            settings.movieDNA.edit(DNAKey.person(personID), kind: .person, name: name) { entry in
                entry.followed = following
                entry.hidden = false
                if following, let photo = Self.syncablePoster(photo) { entry.poster = photo }
            }
        }
    }

    /// Inlined custom images would bloat the synced settings; the library item still has them.
    nonisolated static func syncablePoster(_ url: String?) -> String? {
        url.flatMap { $0.hasPrefix("data:") ? nil : $0 }
    }

    /// Takes a trait out until the next rebuild; for a person it also unfollows.
    func removeFromDNA(_ trait: DNATrait) {
        updateSettings { settings in
            settings.movieDNA.edit(trait.key, kind: trait.kind, name: trait.name) { entry in
                entry = DNAEntry(kind: trait.kind, name: trait.name)
                // Something learned from the library would come straight back, so it's hidden instead.
                entry.hidden = trait.learned != nil && !trait.followed
            }
        }
    }

    /// Starts over from the library: drops hand edits, removals and Interested presses. Follows and
    /// Not interested stay, they're choices rather than tuning.
    func rebuildMovieDNA() {
        updateSettings { settings in
            var dna = settings.movieDNA
            dna.entries = dna.entries.compactMapValues { entry in
                guard entry.followed else { return nil }
                var kept = DNAEntry(kind: entry.kind, name: entry.name)
                kept.followed = true
                return kept
            }
            settings.movieDNA = dna
        }
    }
}
