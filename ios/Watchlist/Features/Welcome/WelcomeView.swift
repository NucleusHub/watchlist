import NucleusUI
import SwiftUI

struct WelcomeView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(NucleusID.self) private var auth
    @Environment(\.dismiss) private var dismiss
    /// Opens the tour once Welcome is gone; skipping and signing in don't.
    var onTour: () -> Void = {}

    var body: some View {
        NucleusWelcome(
            title: "Watchlist",
            subtitle: "Everything you want to watch, in one place.",
            points: [
                WelcomePoint("iphone", tint: .indigo, title: "Lives on your phone", message: "No account needed. Your list stays on this device."),
                WelcomePoint("square.and.arrow.up", tint: .teal, title: "Back it up", message: "Export to a file and bring it to another device any time."),
                WelcomePoint("arrow.triangle.2.circlepath", tint: .violet, title: "Or sync it", message: "Sign in with Nucleus ID to keep all your devices in step."),
            ],
            primary: "Show me around",
            onStart: {
                onTour()
                finish()
            },
            hero: {
                Image("Splash").resizable().scaledToFit().frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: Nucleus.accent.opacity(0.4), radius: 30)
            },
            footer: {
                Button("Skip the tour", action: finish)
                    .buttonStyle(NucleusSecondaryButtonStyle())
                Button("Sync with Nucleus ID") {
                    finish()
                    Task { await auth.signIn(mode: .keep) }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Nucleus.accent)
            }
        )
        .background(NucleusBackground())
    }

    private func finish() {
        Haptics.tap()
        preferences.hasSeenWelcome = true
        dismiss()
    }
}
