import NucleusUI
import SwiftUI
import WebKit

/// The in-app browser: opens a title's link, follows the video and saves where you stopped.
struct BrowserView: View {
    let request: BrowserRequest
    @Environment(WatchlistStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = BrowserModel()

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack(alignment: .bottom) {
                WebContainer(webView: model.webView)
                if model.progress < 1 {
                    ProgressView(value: model.progress).tint(Nucleus.accent)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                if model.failed { failure }
                overlays
            }
            bottomBar
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            OrientationLock.allowLandscape(true)
            model.start(request, store: store)
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.flush() } }
        .onDisappear {
            model.stop()
            OrientationLock.allowLandscape(false)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            GlassCircleButton("xmark") { dismiss() }.accessibilityLabel("Close")
            Text(verbatim: model.host)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            if let item = store.item(request.itemID ?? ""), item.isShow, let next = item.nextEpisode {
                Button {
                    Haptics.success()
                    model.markEpisode()
                } label: {
                    HStack(spacing: 5) {
                        if model.pageMarked {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                            Text("Watched").font(.system(size: 14, weight: .semibold))
                        } else {
                            Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                            Text(verbatim: "S\(next.season) E\(next.episode)").font(.system(size: 14, weight: .semibold).monospacedDigit())
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).frame(height: 40)
                    .nucleusGlass(in: Capsule(), interactive: !model.pageMarked)
                    .opacity(model.pageMarked ? 0.55 : 1)
                }
                .disabled(model.pageMarked)
                .accessibilityLabel("Mark episode watched")
            }
            Menu {
                Button { model.reload() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                Button { model.goHome() } label: { Label("Go to start page", systemImage: "house") }
                if let url = model.currentURL {
                    Button { openURL(url) } label: { Label("Open in Safari", systemImage: "safari") }
                }
                if model.hasPlayback {
                    Divider()
                    Button(role: .destructive) { model.forgetPosition() } label: { DestructiveLabel("Forget saved position", systemImage: "arrow.counterclockwise") }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .nucleusGlass(in: Circle(), interactive: true)
            }
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var bottomBar: some View {
        HStack(spacing: 28) {
            Button { model.webView.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!model.canGoBack).accessibilityLabel("Back")
            Button { model.webView.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!model.canGoForward).accessibilityLabel("Forward")
        }
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity).frame(height: 44)
    }

    private var failure: some View {
        VStack(spacing: 14) {
            Text("Couldn't load the page").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            Button("Try again") { model.reload() }.buttonStyle(NucleusPrimaryButtonStyle()).frame(maxWidth: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var overlays: some View {
        VStack(spacing: 10) {
            if let notice = model.notice {
                HStack(spacing: 12) {
                    Text(verbatim: notice).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                    if model.canUndo {
                        Button("Undo") { model.undo() }.font(.system(size: 14, weight: .semibold))
                    }
                }
                .padding(.horizontal, 14).frame(height: 34)
                .nucleusGlass(in: Capsule())
                .transition(.opacity)
            }
            if model.offerMovie {
                HStack(spacing: 12) {
                    Text("Finished watching?").font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                    Spacer(minLength: 0)
                    Button("Mark as watched") {
                        Haptics.success()
                        model.markMovieWatched()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    Button { model.dismissOffer() } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)) }
                        .foregroundStyle(.white.opacity(0.7)).accessibilityLabel("Dismiss")
                }
                .padding(.horizontal, 16).frame(height: 52)
                .nucleusGlass(in: Capsule())
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 12)
        .animation(NucleusMotion.quick, value: model.offerMovie)
        .animation(NucleusMotion.quick, value: model.notice)
    }
}

private struct WebContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

/// The app is portrait, except while the browser is open so videos can go landscape.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

@MainActor
enum OrientationLock {
    nonisolated(unsafe) fileprivate(set) static var mask: UIInterfaceOrientationMask = .portrait

    static func allowLandscape(_ allowed: Bool) {
        mask = allowed ? .allButUpsideDown : .portrait
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        scene?.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        if !allowed { scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) }
    }
}
