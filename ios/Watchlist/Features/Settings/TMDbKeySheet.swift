import NucleusUI
import SwiftUI

/// Enter, check and save the TMDb API key. The key is checked with TMDb before it's kept.
struct TMDbKeySheet: View {
    @Environment(WatchlistStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var key = ""
    @State private var checking = false
    @State private var problem: LocalizedStringKey?
    @FocusState private var focused: Bool

    private var trimmed: String { String(key.trimmingCharacters(in: .whitespacesAndNewlines).prefix(256)) }

    var body: some View {
        NucleusSheetPage("TMDb API key", confirmTitle: "Save", canConfirm: !trimmed.isEmpty && !checking,
                         onCancel: { dismiss() }, onConfirm: save) {
            NucleusSection(footer: problem.map { Text($0).foregroundStyle(Nucleus.danger) }
                           ?? Text("The “API Key” from your TMDb account settings, not the read access token.")) {
                HStack(spacing: 10) {
                    TextField("Paste your key", text: $key)
                        .font(.system(size: 15, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.done)
                        .focused($focused)
                        .onSubmit(save)
                        .onChange(of: key) { _, _ in problem = nil }
                    if checking {
                        ProgressView().controlSize(.small)
                    } else if !key.isEmpty {
                        Button { key = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Nucleus.secondaryText) }
                            .accessibilityLabel("Clear")
                    } else {
                        PasteButton(payloadType: String.self) { strings in
                            if let first = strings.first { key = first }
                        }
                        .buttonBorderShape(.capsule)
                        .labelStyle(.titleOnly)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 16).frame(minHeight: 54)
            }
            NucleusSection {
                Button { openURL(URL(string: "https://www.themoviedb.org/settings/api")!) } label: {
                    NucleusRow("Get a free key", icon: IconTile("safari", tint: .blue)) {
                        Image(systemName: "arrow.up.right").foregroundStyle(Nucleus.secondaryText)
                    }
                }
                .buttonStyle(NucleusRowButtonStyle())
                if !store.settings.tmdbApiKey.isEmpty {
                    Button {
                        store.updateSettings { $0.tmdbApiKey = "" }
                        Haptics.warning()
                        dismiss()
                    } label: { NucleusRow("Remove key", titleColor: Nucleus.danger) }
                    .buttonStyle(NucleusRowButtonStyle())
                }
            }
        }
        .onAppear {
            key = store.settings.tmdbApiKey
            focused = key.isEmpty
        }
    }

    private func save() {
        let candidate = trimmed
        guard !candidate.isEmpty, !checking else { return }
        checking = true
        Task {
            defer { checking = false }
            do {
                guard try await TMDb(apiKey: candidate).verify() else {
                    Haptics.error()
                    problem = "TMDb didn't accept this key. Check you copied all of it."
                    return
                }
            } catch {
                // Offline: keep it anyway, it gets used as soon as there's a connection.
            }
            store.updateSettings { $0.tmdbApiKey = candidate }
            Haptics.success()
            dismiss()
        }
    }
}
