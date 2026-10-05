import NucleusPlugins
import NucleusUI
import SwiftUI

/// The plugins the app has installed, each with an on/off switch, and the marketplace's plugins it doesn't include.
struct PluginsView: View {
    @Environment(PluginRegistry.self) private var registry
    @State private var catalog: [MarketplaceItem]?
    @State private var catalogFailed = false

    private var missing: [MarketplaceItem] { catalog.map(registry.notBundled(in:)) ?? [] }

    var body: some View {
        NucleusPage("Plugins") {
            if registry.plugins.isEmpty, missing.isEmpty {
                NucleusEmptyState("puzzlepiece.extension", title: "No plugins", message: "Plugins you install show up here.")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            }
            if !registry.plugins.isEmpty {
                NucleusSection(footer: Text("Turning a plugin off hides what it adds. Nothing it saved is deleted.")) {
                    ForEach(registry.plugins) { plugin in row(plugin) }
                }
            }
            if !missing.isEmpty {
                NucleusSection("Not in this version") {
                    ForEach(missing) { item in
                        NucleusRow(verbatim: item.name, subtitle: Text("Not included in this version of the app. Update the app or contact the developer."),
                                   icon: IconTile("arrow.down.app.fill", tint: .slate)) {
                            Text(verbatim: item.version).font(.system(size: 14)).foregroundStyle(Nucleus.secondaryText)
                        }
                    }
                }
            }
            if catalogFailed {
                Text("Couldn't check the marketplace.")
                    .font(.system(size: 13))
                    .foregroundStyle(Nucleus.secondaryText)
                    .padding(.horizontal, 4)
            }
        }
        .task {
            do {
                catalog = try await MarketplaceClient().plugins(for: registry.app)
                catalogFailed = false
            } catch {
                catalogFailed = true
            }
        }
    }

    @ViewBuilder
    private func row(_ plugin: InstalledPlugin) -> some View {
        let icon = IconTile("puzzlepiece.extension.fill", tint: plugin.compatibility == .compatible ? .violet : .slate)
        switch plugin.compatibility {
        case .compatible:
            Toggle(isOn: Binding(get: { registry.isEnabled(plugin.id) }, set: { Haptics.selection(); registry.setEnabled($0, for: plugin.id) })) {
                NucleusRow(verbatim: plugin.manifest.name, subtitle: Text(verbatim: details(plugin)), icon: icon)
            }
            .tint(Color(hex: 0x34C759))
            .padding(.horizontal, 16)
        case .incompatible(let reason):
            NucleusRow(verbatim: plugin.manifest.name, subtitle: Text(verbatim: reason), icon: icon)
        case .invalid(let problems):
            NucleusRow(verbatim: plugin.manifest.name.isEmpty ? plugin.id : plugin.manifest.name, subtitle: Text(verbatim: problems.joined(separator: " ")), icon: icon)
        }
    }

    private func details(_ plugin: InstalledPlugin) -> String {
        var lines = [[String(localized: "Version \(plugin.manifest.version)"), plugin.manifest.author].compactMap { $0 }.joined(separator: " · ")]
        if let newer = catalog.flatMap({ registry.newerVersion(of: plugin.id, in: $0) }) {
            lines.append(String(localized: "Version \(newer) is out. Update the app to get it."))
        }
        return lines.joined(separator: "\n")
    }
}
