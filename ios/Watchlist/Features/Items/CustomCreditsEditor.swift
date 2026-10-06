import NucleusUI
import SwiftUI

/// Cast and crew typed in for a title TMDb doesn't have, edited in place: one field adds people, rows set their part.
struct CustomCreditsSection: View {
    @Binding var credits: [CustomCredit]
    @Environment(WatchlistStore.self) private var store
    @State private var query = ""
    @State private var results: [TMDb.PersonResult] = []
    @FocusState private var adding: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasKey: Bool { !store.settings.tmdbApiKey.isEmpty }

    var body: some View {
        NucleusSection("Cast & crew", footer: Text(hasKey ? "Pick someone from TMDb to link their page, or press return to add the name as typed."
                                                         : "Press return to add a name. With a TMDb key you can also find people and link their pages.")) {
            ForEach(credits.indices, id: \.self) { index in
                CustomCreditRow(credit: $credits[index]) {
                    Haptics.selection()
                    withAnimation { _ = credits.remove(at: index) }
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "person.badge.plus").foregroundStyle(Nucleus.accent)
                TextField(hasKey ? "Add a person, or search TMDb" : "Add a person", text: $query)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($adding)
                    .onSubmit(addTyped)
                if !trimmed.isEmpty {
                    Button("Add", action: addTyped).font(.system(size: 15, weight: .semibold))
                }
            }
            .padding(.horizontal, 16).frame(minHeight: 52)
            ForEach(results) { person in
                Button { add(person) } label: {
                    HStack(spacing: 12) {
                        CreditPhoto(url: person.photoURL, name: person.name).frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: person.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Nucleus.primaryText)
                            if !person.knownFor.isEmpty {
                                Text(LocalizedStringKey(person.knownFor)).font(.system(size: 12)).foregroundStyle(Nucleus.secondaryText)
                            }
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(Nucleus.accent)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6).contentShape(Rectangle())
                }
                .buttonStyle(NucleusRowButtonStyle())
            }
        }
        .task(id: trimmed) { await search() }
    }

    private func search() async {
        let key = store.settings.tmdbApiKey
        guard trimmed.count >= 2, !key.isEmpty else { results = []; return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let found = (try? await TMDb(apiKey: key).searchPeople(trimmed)) ?? []
        guard !Task.isCancelled else { return }
        let added = Set(credits.compactMap(\.personID))
        results = Array(found.filter { !added.contains($0.id) }.prefix(5))
    }

    private func addTyped() {
        guard !trimmed.isEmpty else { return }
        append(CustomCredit(name: trimmed, role: "", isCast: true))
    }

    private func add(_ person: TMDb.PersonResult) {
        let job = CustomCredit.Job(department: person.knownFor)
        append(CustomCredit(name: person.name, role: job?.rawValue ?? "", isCast: job == nil,
                            personID: person.id, photo: person.photoURL?.absoluteString))
    }

    /// Clears the field and keeps it focused, so the next person can be typed right away.
    private func append(_ credit: CustomCredit) {
        Haptics.tap()
        withAnimation { credits.append(credit) }
        query = ""
        results = []
        adding = true
    }
}

/// One person: who, and their part — a character for cast, a job for crew — changed in place.
private struct CustomCreditRow: View {
    @Binding var credit: CustomCredit
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CreditPhoto(url: credit.photo.flatMap { URL(string: $0) }, name: credit.name).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(verbatim: credit.name).font(.system(size: 16)).foregroundStyle(Nucleus.primaryText).lineLimit(1)
                    if credit.personID != nil {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 11)).foregroundStyle(Nucleus.accent)
                            .accessibilityLabel("From TMDb")
                    }
                }
                if credit.isCast {
                    TextField("Character", text: $credit.role)
                        .font(.system(size: 14))
                        .foregroundStyle(Nucleus.secondaryText)
                }
            }
            Spacer(minLength: 8)
            Menu {
                Button { credit.isCast = true; credit.role = "" } label: { Label("Cast", systemImage: credit.isCast ? "checkmark" : "") }
                Section("Crew") {
                    ForEach(CustomCredit.Job.allCases, id: \.self) { job in
                        Button { credit.isCast = false; credit.role = job.rawValue } label: {
                            Label(LocalizedStringKey(job.rawValue), systemImage: !credit.isCast && credit.role == job.rawValue ? "checkmark" : "")
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(credit.isCast ? "Cast" : LocalizedStringKey(credit.role))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Nucleus.accent)
                .padding(.horizontal, 10).frame(height: 30)
                .background(Capsule().fill(Nucleus.well))
            }
            Button(action: remove) {
                Image(systemName: "minus.circle.fill").font(.system(size: 20)).foregroundStyle(Nucleus.danger)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(credit.name)")
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

extension CustomCredit.Job {
    /// The job someone known for a TMDb department most likely had; nil for actors.
    init?(department: String) {
        switch department {
        case "Directing": self = .director
        case "Writing": self = .writer
        case "Production": self = .producer
        case "Sound": self = .composer
        case "Camera": self = .cinematographer
        case "Editing": self = .editor
        default: return nil
        }
    }
}

/// A round photo, with initials when there's none.
struct CreditPhoto: View {
    let url: URL?
    let name: String

    var body: some View {
        Circle()
            .fill(Nucleus.well)
            .overlay {
                if let url {
                    AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { initials }
                } else {
                    initials
                }
            }
            .clipShape(Circle())
    }

    private var initials: some View {
        Text(verbatim: name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined())
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Nucleus.secondaryText)
    }
}
