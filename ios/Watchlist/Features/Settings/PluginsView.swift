import NucleusPlugins
import NucleusUI
import SwiftUI

/// The plugins the app has installed, each with an on/off switch.
struct PluginsView: View {
    @Environment(PluginRegistry.self) private var registry

    var body: some View {
        NucleusPage("Plugins") {
            if registry.plugins.isEmpty {
                NucleusEmptyState("puzzlepiece.extension", title: "No plugins", message: "Plugins you install show up here.")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else {
                NucleusSection(footer: Text("Turning a plugin off hides what it adds. Nothing it saved is deleted.")) {
                    ForEach(registry.plugins) { plugin in row(plugin) }
                }
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
        [String(localized: "Version \(plugin.manifest.version)"), plugin.manifest.author].compactMap { $0 }.joined(separator: " · ")
    }
}
