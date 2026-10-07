import NucleusUI
import SwiftUI

/// The signed-in Nucleus ID: who you are, and the theme your apps start with.
struct ProfileView: View {
    @Environment(WatchlistStore.self) private var store
    @Environment(NucleusID.self) private var auth
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    /// An account theme picked but not saved yet, while asking whether the apps take it too.
    @State private var pendingAccent: NucleusAccent?
    @State private var flash: String?

    var body: some View {
        NucleusPage("Profile") {
            if let user = auth.user {
                VStack(spacing: 10) {
                    Text(verbatim: String((user.name.isEmpty ? user.handle : user.name).prefix(1)).uppercased())
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 84, height: 84)
                        .background(Circle().fill(Nucleus.primaryGradient))
                    Text(verbatim: user.name)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Nucleus.primaryText)
                    Text(verbatim: "@\(user.handle)")
                        .font(.system(size: 15))
                        .foregroundStyle(Nucleus.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .nucleusGlass(cornerRadius: NucleusRadius.card)
                .padding(.bottom, 28)

                NucleusSection("Account theme", footer: Text(flash.map { LocalizedStringKey($0) } ?? "Apps you sign in to start with this theme. You can push it to the ones you already use too.")) {
                    NucleusAccentPicker("Theme", selection: Binding(
                        get: { pendingAccent ?? NucleusTheme.shared.account?.accent ?? .nucleus },
                        set: { pendingAccent = $0 }
                    ))
                    .confirmationDialog("Change the theme in your apps too?",
                                        isPresented: Binding(get: { pendingAccent != nil }, set: { if !$0 { pendingAccent = nil } }),
                                        titleVisibility: .visible, presenting: pendingAccent) { accent in
                        Button("Change in all apps") { save(accent, applyToApps: true) }
                        Button("Only new apps") { save(accent, applyToApps: false) }
                    } message: { _ in
                        Text("Apps you sign in to from now on start with this theme either way.")
                    }
                }

                NucleusSection("Nucleus ID", footer: Text("Opens nucleus-home.dev in your browser.")) {
                    if let email = user.email, !email.isEmpty {
                        NucleusRow("Email", icon: IconTile("envelope.fill", tint: .sky)) {
                            Text(verbatim: email).foregroundStyle(Nucleus.secondaryText).lineLimit(1)
                        }
                    }
                    link("Manage your account", icon: "person.crop.circle.fill", tint: .indigo, url: NucleusID.manageAccountURL())
                    link("Connected apps", icon: "app.connected.to.app.below.fill", tint: .teal, url: NucleusID.manageAccountURL(tab: "apps"))
                    Button { openURL(NucleusID.deleteAccountURL) } label: {
                        NucleusRow("Delete Nucleus ID account", titleColor: Nucleus.danger) { Image(systemName: "arrow.up.right").foregroundStyle(Nucleus.secondaryText) }
                    }
                    .buttonStyle(NucleusRowButtonStyle())
                }
            }
        }
        // Signed out (or expired) while here: nothing left to show.
        .onChange(of: auth.isSignedIn) { _, signedIn in if !signedIn { dismiss() } }
    }

    private func link(_ title: LocalizedStringKey, icon: String, tint: NucleusTint, url: URL) -> some View {
        Button { openURL(url) } label: {
            NucleusRow(title, icon: IconTile(icon, tint: tint)) {
                Image(systemName: "arrow.up.right").foregroundStyle(Nucleus.secondaryText)
            }
        }
        .buttonStyle(NucleusRowButtonStyle())
    }

    /// Saves the account theme; with `applyToApps` this app takes it straight away too.
    private func save(_ accent: NucleusAccent, applyToApps: Bool) {
        Task {
            do {
                try await auth.setAccountAccent(accent, applyToApps: applyToApps)
                if applyToApps { store.updateSettings { $0.accent = accent } }
                show(applyToApps ? String(localized: "Your apps switch to it the next time they open.")
                                 : String(localized: "Apps you sign in to from now on start with it."))
            } catch {
                Haptics.error()
                show(String(localized: "Couldn't save the theme to your account."))
            }
        }
    }

    private func show(_ message: String) {
        withAnimation { flash = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { withAnimation { flash = nil } }
    }
}
