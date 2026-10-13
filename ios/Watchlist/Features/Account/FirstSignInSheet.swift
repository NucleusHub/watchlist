import NucleusUI
import SwiftUI

/// Shown once per sign-in when this iPhone and the account both have data: how to combine them.
/// Nothing is applied before a backup of this iPhone is written.
struct FirstSignInSheet: View {
    @Environment(CloudSync.self) private var sync
    @Environment(\.dismiss) private var dismiss
    let choice: FirstSyncChoice
    @State private var confirming: Confirmation?
    @State private var busy = false
    @State private var problem: String?

    private enum Confirmation: Identifiable {
        case keepWeb, keepDevice, startEmpty
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summary("This iPhone", choice.local.items.count, choice.local.collections.count)
                    summary("Watchlist account", choice.server.items.count, choice.server.collections.count)
                } footer: {
                    Text("Both have data. Choose how to combine them. A backup of this iPhone is saved first, whatever you pick.")
                }
                Section {
                    option("Merge", "Keep everything. The newest edit of each title wins. Nothing is deleted.", recommended: true) { run(.merge) }
                    option("Keep web", "Replace this iPhone's data with the account's. Nothing is uploaded.") { confirming = .keepWeb }
                    option("Keep this iPhone", "Replace the account's data with this iPhone's. Deletes what is only on the account.") { confirming = .keepDevice }
                    NavigationLink {
                        PickItemsView(choice: choice) { run(.pick($0)) }
                    } label: {
                        optionLabel("Choose items", "Pick titles and collections from both sides. Unchecked ones stay as they are.")
                    }
                    option("Start empty", "Clear this iPhone. The account's data stays on the server and can be fetched later in Settings. To erase the server too, use Keep this iPhone with an empty iPhone.") { confirming = .startEmpty }
                }
                if let problem { Section { Text(verbatim: problem).foregroundStyle(Nucleus.danger) } }
            }
            .navigationTitle("Combine your data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Not now") { sync.deferChoice(); dismiss() }.disabled(busy) } }
            .disabled(busy)
            .overlay { if busy { ProgressView() } }
            .alert(item: $confirming) { which in
                switch which {
                case .keepWeb:
                    Alert(title: Text("Replace this iPhone's data?"),
                          message: Text("Everything only on this iPhone is removed from it. A backup is saved first."),
                          primaryButton: .destructive(Text("Keep web")) { run(.keepWeb) }, secondaryButton: .cancel())
                case .keepDevice:
                    Alert(title: Text("Replace the account's data?"),
                          message: Text("\(choice.deletions.items) titles and \(choice.deletions.collections) collections on the server will be deleted. Backups of both sides are saved first."),
                          primaryButton: .destructive(Text("Keep this iPhone")) { run(.keepDevice) }, secondaryButton: .cancel())
                case .startEmpty:
                    Alert(title: Text("Clear this iPhone?"),
                          message: Text("A backup is saved first. Nothing is deleted on the server: its \(choice.server.items.count) titles and \(choice.server.collections.count) collections stay and can be fetched later."),
                          primaryButton: .destructive(Text("Start empty")) { run(.startEmpty) }, secondaryButton: .cancel())
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func summary(_ title: LocalizedStringKey, _ items: Int, _ collections: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(items) titles, \(collections) collections").foregroundStyle(Nucleus.secondaryText)
        }
    }

    private func option(_ title: LocalizedStringKey, _ caption: LocalizedStringKey, recommended: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { optionLabel(title, caption, recommended: recommended) }
    }

    private func optionLabel(_ title: LocalizedStringKey, _ caption: LocalizedStringKey, recommended: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.headline)
                if recommended { Text("Recommended").font(.caption).foregroundStyle(Nucleus.secondaryText) }
            }
            Text(caption).font(.footnote).foregroundStyle(Nucleus.secondaryText)
        }
    }

    private func run(_ option: FirstSignInOption) {
        busy = true
        problem = nil
        Task {
            let message = await sync.resolve(option)
            busy = false
            problem = message
        }
    }
}

/// The differences between the two sides with a checkbox each; the checked ones are combined, the rest left alone.
private struct PickItemsView: View {
    let choice: FirstSyncChoice
    let apply: (Set<String>) -> Void
    @State private var selected: Set<String>

    init(choice: FirstSyncChoice, apply: @escaping (Set<String>) -> Void) {
        self.choice = choice
        self.apply = apply
        _selected = State(initialValue: choice.defaultSelection)
    }

    var body: some View {
        List {
            ForEach(choice.rows) { row in
                Button {
                    if !selected.insert(row.id).inserted { selected.remove(row.id) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selected.contains(row.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(row.id) ? Nucleus.glyph : Nucleus.secondaryText)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: row.title.isEmpty ? "—" : row.title)
                            side(row)
                        }
                    }
                }
            }
        }
        .navigationTitle("Choose items")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button { apply(selected) } label: { Text("Combine \(selected.count) selected").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                .padding()
        }
    }

    @ViewBuilder
    private func side(_ row: WatchlistAPI.PickRow) -> some View {
        Group {
            switch row.side {
            case .device: Text("Only on this iPhone")
            case .web: Text("Only on the account")
            case .both: Text("On both, edited differently")
            case .deletedOnDevice: Text("Deleted on this iPhone. Check to delete it on the account too.")
            }
        }
        .font(.footnote).foregroundStyle(Nucleus.secondaryText)
    }
}
