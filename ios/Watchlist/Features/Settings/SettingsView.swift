import NucleusPlugins
import NucleusUI
import SwiftUI
import UniformTypeIdentifiers
import WatchlistPluginKit

struct SettingsView: View {
    @Environment(WatchlistStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(NucleusID.self) private var auth
    @Environment(CloudSync.self) private var sync
    @Environment(Navigator.self) private var navigator
    @Environment(PluginRegistry.self) private var registry
    @Environment(\.openURL) private var openURL

    @State private var askingSignIn = false
    @State private var askingSignOut = false
    @State private var importing = false
    @State private var pendingImport: Backup.Preview?
    @State private var flash: String?
    @State private var editingKey = false
    @State private var refresh = MetadataRefresh()
    @State private var showingRefresh = false
    @State private var askingRefresh = false

    var body: some View {
        NucleusPage("Settings") {
            accountSection
            dataSection
            watchingSection
            NucleusSection("Appearance") {
                NucleusSegmented(selection: Binding(get: { preferences.appearance }, set: { preferences.appearance = $0 }),
                                 items: AppearanceMode.allCases.map { ($0, $0.title) }, fill: true)
                    .padding(12)
            }
            helpSection
            aboutSection
        }
        .sheet(isPresented: $editingKey) { TMDbKeySheet().presentationDetents([.medium]) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                pendingImport = try Backup.read(Data(contentsOf: url))
            } catch {
                Haptics.error()
                show(error.localizedDescription)
            }
        }
        .confirmationDialog(importTitle, isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
                            titleVisibility: .visible, presenting: pendingImport) { preview in
            Button("Merge with this device") { apply(preview, replace: false) }
            Button("Replace everything", role: .destructive) { apply(preview, replace: true) }
        } message: { preview in
            Text(importMessage(preview))
        }
        .confirmationDialog("Sign in to Nucleus ID", isPresented: $askingSignIn, titleVisibility: .visible) {
            Button("Keep and merge") { Task { await auth.signIn(mode: .keep) } }
            Button("Start clean", role: .destructive) { Task { await auth.signIn(mode: .clean) } }
        } message: {
            Text("This device has \(store.document.items.count) titles and \(store.document.collections.count) collections. Merge them into your account, or replace them with the account's copy?")
        }
        .confirmationDialog("Sign out?", isPresented: $askingSignOut, titleVisibility: .visible) {
            Button("Keep on this device") { Task { await auth.signOut(clean: false) } }
            Button("Remove from this device", role: .destructive) { Task { await auth.signOut(clean: true) } }
        } message: {
            Text("Your watchlist stays in your Nucleus ID account either way.")
        }
        .confirmationDialog("Refresh details from TMDb?", isPresented: $askingRefresh, titleVisibility: .visible) {
            Button("Refresh \(store.document.items.count) titles") { showingRefresh = true; refresh.start(store: store) }
        } message: {
            Text("Fills in missing posters, genres, runtimes and where to watch. Takes about \(max(1, store.document.items.count * 8 / 10)) seconds.")
        }
        .sheet(isPresented: $showingRefresh) {
            RefreshProgressSheet(refresh: refresh)
                .presentationDetents([.height(260)])
                .interactiveDismissDisabled(refresh.running)
        }
    }

    // MARK: Account

    private var accountSection: some View {
        NucleusSection("Account", footer: accountFooter) {
            if let user = auth.user {
                HStack(spacing: 12) {
                    Text(verbatim: String((user.name.isEmpty ? user.handle : user.name).prefix(1)).uppercased())
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Nucleus.primaryGradient))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: user.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Nucleus.primaryText)
                        Text(verbatim: "@\(user.handle) · Nucleus ID").font(.system(size: 13)).foregroundStyle(Nucleus.secondaryText)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                Button { Task { await sync.syncNow() } } label: {
                    NucleusRow("Sync now", subtitle: syncStatusText, icon: IconTile("arrow.triangle.2.circlepath", tint: .emerald)) {
                        if sync.status == .syncing { ProgressView().controlSize(.small) }
                    }
                }
                .buttonStyle(NucleusRowButtonStyle())
                .disabled(sync.status == .syncing)
                Button { askingSignOut = true } label: { NucleusRow("Sign out", titleColor: Nucleus.danger) }
                    .buttonStyle(NucleusRowButtonStyle())
            } else {
                HStack(spacing: 12) {
                    Image("NucleusMark").resizable().scaledToFit().frame(width: 40, height: 40)
                    Text("Sync your watchlist across your devices with a free Nucleus ID.")
                        .font(.system(size: 14)).foregroundStyle(Nucleus.glyph)
                }
                .padding(16)
                Button {
                    if store.document.isEmpty { Task { await auth.signIn(mode: .keep) } } else { askingSignIn = true }
                } label: {
                    NucleusRow("Sign in with Nucleus ID", icon: IconTile("person.crop.circle", tint: .indigo)) {
                        if auth.signingIn { ProgressView().controlSize(.small) } else { Chevron() }
                    }
                }
                .buttonStyle(NucleusRowButtonStyle())
                .disabled(auth.signingIn)
            }
        }
    }

    private var syncStatusText: Text {
        switch sync.status {
        case .syncing: Text("Syncing…")
        case .offline: Text("Offline. Changes sync when you're back.")
        case .tooLarge: Text("Too large to sync. Remove some custom images.")
        case .error(let message): Text(verbatim: message)
        case .idle:
            if let at = sync.lastSyncedAt { Text("Synced \(at, format: .relative(presentation: .named))") } else { Text("Not synced yet") }
        }
    }

    private var accountFooter: Text? {
        switch auth.error {
        case .expired: Text("You were signed out. Sign in again to keep syncing.")
        case .offline: Text("Couldn't reach Nucleus ID. Check your connection.")
        case .failed(let reason): Text("Sign-in failed: \(reason)")
        case .cancelled, nil: nil
        }
    }

    // MARK: Data

    private var dataSection: some View {
        NucleusSection("Data", footer: Text(flash.map { LocalizedStringKey($0) } ?? "\(store.document.items.count) titles and \(store.document.collections.count) collections on this device.")) {
            Button { navigator.open(.movieDNA) } label: {
                // NucleusRow only takes SF Symbol tiles; this sits where its tile would.
                NucleusRow("MovieDNA", subtitle: movieDNASummary) { Chevron() }
                    .padding(.leading, 42)
                    .overlay(alignment: .leading) { DNATile().padding(.leading, 16) }
            }
            .buttonStyle(NucleusRowButtonStyle())
            ShareLink(item: BackupFile(document: store.document), preview: SharePreview(Backup.fileName())) {
                NucleusRow("Export backup", icon: IconTile("square.and.arrow.up", tint: .sky)) { Chevron() }
            }
            .buttonStyle(NucleusRowButtonStyle())
            Button { importing = true } label: {
                NucleusRow("Import backup", icon: IconTile("square.and.arrow.down", tint: .teal)) { Chevron() }
            }
            .buttonStyle(NucleusRowButtonStyle())
            Button { askingRefresh = true } label: {
                NucleusRow("Refresh details from TMDb", icon: IconTile("sparkles", tint: .amber)) { Chevron() }
            }
            .buttonStyle(NucleusRowButtonStyle())
            .disabled(store.settings.tmdbApiKey.isEmpty || store.document.items.isEmpty)
        }
    }

    private var importTitle: Text {
        Text("Import backup")
    }

    private func importMessage(_ preview: Backup.Preview) -> String {
        var text = String(localized: "\(preview.document.items.count) titles and \(preview.document.collections.count) collections.")
        if let at = preview.exportedAt { text += " " + String(localized: "Exported \(at.formatted(date: .abbreviated, time: .shortened)).") }
        return text
    }

    private func apply(_ preview: Backup.Preview, replace: Bool) {
        let next = replace ? Backup.replace(store.document, with: preview.document) : Backup.merge(preview.document, into: store.document)
        store.replace(with: next)
        Haptics.success()
        show(String(localized: "Imported \(preview.document.items.count) titles."))
    }

    private func show(_ message: String) {
        withAnimation { flash = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { withAnimation { flash = nil } }
    }

    // MARK: Watching

    private var watchingSection: some View {
        NucleusSection("Titles", footer: Text("Searching TMDb needs a free API key from themoviedb.org.")) {
            Button { navigator.open(.openDefaults) } label: {
                NucleusRow("Open on click", subtitle: Text(verbatim: "\(OpenTarget.Kind.label(store.settings.openDefault(for: .movie))) · \(OpenTarget.Kind.label(store.settings.openDefault(for: .show)))"),
                           icon: IconTile("arrow.up.right.square", tint: .violet)) { Chevron() }
            }
            .buttonStyle(NucleusRowButtonStyle())
            Button { navigator.open(.searchSources) } label: {
                NucleusRow("Search sources", subtitle: Text(verbatim: searchSourcesSummary), icon: IconTile("magnifyingglass", tint: .blue)) { Chevron() }
            }
            .buttonStyle(NucleusRowButtonStyle())
            Button { navigator.open(.plugins) } label: {
                NucleusRow("Plugins", subtitle: Text("\(registry.plugins.count) installed"), icon: IconTile("puzzlepiece.extension.fill", tint: .indigo)) { Chevron() }
            }
            .buttonStyle(NucleusRowButtonStyle())
            Toggle(isOn: Binding(get: { preferences.inAppBrowser }, set: { preferences.inAppBrowser = $0 })) {
                Label { Text("Open links in the app") } icon: { IconTile("play.rectangle.fill", tint: .sky) }
            }
            .tint(Color(hex: 0x34C759))
            .padding(.horizontal, 16).frame(minHeight: 52)
            Button { editingKey = true } label: {
                NucleusRow("TMDb API key", subtitle: keySummary, icon: IconTile("key.fill", tint: .amber)) { Chevron() }
            }
            .buttonStyle(NucleusRowButtonStyle())
            Button { openURL(URL(string: "https://www.themoviedb.org/settings/api")!) } label: {
                NucleusRow("Get a TMDb key", icon: IconTile("safari", tint: .blue)) { Image(systemName: "arrow.up.right").foregroundStyle(Nucleus.secondaryText) }
            }
            .buttonStyle(NucleusRowButtonStyle())
        }
    }

    private var searchSourcesSummary: String {
        let chosen = Set(store.settings.searchSources)
        return SourceCatalog(registry: registry, settings: store.settings).available.filter { chosen.contains($0.id) }.map(\.name).joined(separator: " · ")
    }

    private var movieDNASummary: Text {
        guard store.movieDNASettings.enabled else { return Text("Off") }
        return registry.contributions(to: .movieDNAUses).isEmpty ? Text("Not used by any plugin") : Text("On")
    }

    private var keySummary: Text {
        let key = store.settings.tmdbApiKey
        return key.isEmpty ? Text("Not set") : Text(verbatim: "•••• \(key.suffix(4))")
    }

    // MARK: Help & about

    private var helpSection: some View {
        NucleusSection("Help") {
            Button { navigator.present(.tour) } label: {
                NucleusRow("Take the tour", icon: IconTile("map.fill", tint: .violet)) { Chevron() }
            }
            .buttonStyle(NucleusRowButtonStyle())
            Button { navigator.present(.report) } label: {
                NucleusRow("Report a problem", icon: IconTile("ladybug.fill", tint: .rose)) { Chevron() }
            }
            .buttonStyle(NucleusRowButtonStyle())
            Toggle(isOn: Binding(get: { preferences.shakeToReport }, set: { preferences.shakeToReport = $0 })) {
                Label { Text("Shake to report") } icon: { IconTile("iphone.radiowaves.left.and.right", tint: .orange) }
            }
            .tint(Color(hex: 0x34C759))
            .padding(.horizontal, 16).frame(minHeight: 52)
        }
    }

    private var aboutSection: some View {
        NucleusSection("About") {
            NucleusRow("Version") {
                Text(verbatim: Bundle.main.versionString).foregroundStyle(Nucleus.secondaryText)
            }
            Button { openURL(NucleusID.privacyURL) } label: {
                NucleusRow("Privacy policy") { Image(systemName: "arrow.up.right").foregroundStyle(Nucleus.secondaryText) }
            }
            .buttonStyle(NucleusRowButtonStyle())
            if auth.isSignedIn {
                Button { openURL(NucleusID.deleteAccountURL) } label: {
                    NucleusRow("Delete Nucleus ID account", titleColor: Nucleus.danger) { Image(systemName: "arrow.up.right").foregroundStyle(Nucleus.secondaryText) }
                }
                .buttonStyle(NucleusRowButtonStyle())
            }
            VStack(alignment: .leading, spacing: 8) {
                Image("TMDbLogo").resizable().scaledToFit().frame(height: 12)
                Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                    .font(.system(size: 12)).foregroundStyle(Nucleus.secondaryText)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension OpenTarget.Kind {
    static func label(_ target: OpenTarget?) -> String { (target?.type ?? .tmdb).label }
}

extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

struct RefreshProgressSheet: View {
    let refresh: MetadataRefresh
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text(refresh.finished ? "Done" : "Refreshing from TMDb")
                .font(.system(size: 17, weight: .semibold))
            ProgressView(value: refresh.total > 0 ? Double(refresh.done) / Double(refresh.total) : 0)
                .tint(Nucleus.accent)
            Text("\(refresh.done) of \(refresh.total)").font(.system(size: 14).monospacedDigit()).foregroundStyle(Nucleus.secondaryText)
            if refresh.finished {
                Text("Updated \(refresh.updated). \(refresh.notFound) not found on TMDb.")
                    .font(.system(size: 14)).foregroundStyle(Nucleus.glyph).multilineTextAlignment(.center)
            }
            Button(refresh.running ? "Stop" : "Close") {
                if refresh.running { refresh.cancel() } else { dismiss() }
            }
            .buttonStyle(NucleusSecondaryButtonStyle())
        }
        .padding(24)
    }
}
