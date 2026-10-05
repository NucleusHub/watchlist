import NucleusPlugins
import NucleusUI
import SwiftUI

/// Which sources the add and edit screen searches. TMDb plus whatever plugins contribute.
struct SearchSourcesView: View {
    @Environment(WatchlistStore.self) private var store
    @Environment(PluginRegistry.self) private var registry

    private var catalog: SourceCatalog { SourceCatalog(registry: registry, settings: store.settings) }
    private var chosen: Set<String> { Set(store.settings.searchSources) }

    var body: some View {
        NucleusPage("Search sources") {
            NucleusSection(footer: Text("Results from every source you turn on are listed together when you add a title.")) {
                ForEach(catalog.available, id: \.id) { source in
                    let on = chosen.contains(source.id)
                    Toggle(isOn: Binding(get: { on }, set: { set(source.id, $0) })) {
                        NucleusRow(verbatim: source.name, subtitle: subtitle(source),
                                   icon: IconTile(source.id == TMDbSource.id ? "film" : "puzzlepiece.extension.fill", tint: source.id == TMDbSource.id ? .teal : .violet))
                    }
                    .tint(Color(hex: 0x34C759))
                    .padding(.horizontal, 16)
                    // The last source stays on so there's always something to search.
                    .disabled(on && chosen.count == 1)
                }
            }
        }
    }

    private func subtitle(_ source: any ItemSource) -> Text? {
        if source.id == TMDbSource.id { return store.settings.tmdbApiKey.isEmpty ? Text("Needs an API key") : nil }
        return registry.contributions(to: .searchSources).first { $0.id == source.id }
            .flatMap { c in registry.plugins.first { $0.id == c.pluginID } }
            .map { Text(verbatim: $0.manifest.name) }
    }

    private func set(_ id: String, _ on: Bool) {
        Haptics.selection()
        store.updateSettings { settings in
            var ids = settings.searchSources.filter { $0 != id }
            if on { ids.append(id) }
            settings.searchSources = catalog.available.map(\.id).filter { ids.contains($0) } + ids.filter { x in !catalog.available.contains { $0.id == x } }
        }
    }
}
