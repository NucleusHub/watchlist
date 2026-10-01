import NucleusUI
import SwiftUI

/// Where tapping "Open" takes movies and shows, unless a title sets its own.
struct OpenDefaultsView: View {
    @Environment(WatchlistStore.self) private var store
    @State private var kind: ItemType = .movie

    private var target: OpenTarget { store.settings.openDefault(for: kind) ?? OpenTarget() }

    var body: some View {
        NucleusPage("Open on click") {
            NucleusSegmented(selection: $kind, items: [(.movie, "Movies"), (.show, "Shows")], fill: true)
                .padding(.bottom, 20)
            NucleusSection(footer: Text("Each title can override this when you edit it.")) {
                ForEach(OpenTarget.Kind.allCases, id: \.self) { option in
                    Button { Haptics.selection(); update { $0.type = option } } label: {
                        NucleusRow(verbatim: option == .custom ? String(localized: "Custom link") : option.label,
                                   icon: IconTile(icon(option), tint: tint(option))) {
                            if target.type == option { Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Nucleus.accent) }
                        }
                    }
                    .buttonStyle(NucleusRowButtonStyle())
                }
            }
            if target.type == .custom {
                NucleusSection("Custom link", footer: preview) {
                    TextField("https://example.com/search?q={title}", text: Binding(get: { target.customUrl }, set: { v in update { $0.customUrl = v } }))
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.system(size: 14, design: .monospaced))
                        .padding(.horizontal, 16).frame(minHeight: 52)
                    Picker("Title format", selection: Binding(get: { target.titleFormat }, set: { v in update { $0.titleFormat = v } })) {
                        ForEach(OpenTarget.TitleFormat.allCases, id: \.self) { Text(verbatim: OpenLinks.format("The Matrix", $0)).tag($0) }
                    }
                    .padding(.horizontal, 16).frame(minHeight: 52)
                }
            }
        }
    }

    private var preview: Text {
        if let url = OpenLinks.url(target, title: "The Matrix", year: 1999) {
            return Text("Use {title} and {year}. The Matrix (1999) opens \(url.absoluteString)")
        }
        return Text("Use {title} and {year} in the link.")
    }

    private func update(_ change: (inout OpenTarget) -> Void) {
        var movie = store.settings.openDefault(for: .movie) ?? OpenTarget()
        var show = store.settings.openDefault(for: .show) ?? OpenTarget()
        if kind == .movie { change(&movie) } else { change(&show) }
        store.updateSettings { $0.setOpenDefaults(movie: movie, show: show) }
    }

    private func icon(_ k: OpenTarget.Kind) -> String {
        switch k {
        case .tmdb: "film"
        case .csfd: "star.square"
        case .google: "magnifyingglass"
        case .custom: "link"
        }
    }

    private func tint(_ k: OpenTarget.Kind) -> NucleusTint {
        switch k {
        case .tmdb: .teal
        case .csfd: .rose
        case .google: .blue
        case .custom: .slate
        }
    }
}
