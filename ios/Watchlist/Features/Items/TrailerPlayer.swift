import Observation
import SwiftUI
import WebKit

/// An invisible YouTube player, loaded when a title opens so a trailer starts the moment it's tapped.
/// It can't play inline, so starting it takes the video straight into the iOS full-screen player.
@MainActor
@Observable
final class TrailerPlayer {
    /// YouTube refuses embeds without a referring site, so the page claims the app's own.
    static let origin = "https://nucleus-home.dev"

    private(set) var webView: WKWebView?
    /// The trailer tapped and not playing yet, so its card can show it's on the way.
    private(set) var loadingKey: String?
    /// Called with a tapped video's key when YouTube won't play it here (removed, region-locked, embedding off).
    @ObservationIgnored var onFailure: (String) -> Void = { _ in }
    /// Videos that already failed while preloading; tapping them goes straight to the fallback.
    @ObservationIgnored private var failed = Set<String>()
    @ObservationIgnored private var timeout: Task<Void, Never>?

    /// Loads the player with the first trailer, ahead of any tap.
    func prepare(_ key: String) {
        guard webView == nil, let id = Self.clean(key) else { return }
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = false
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(MessageProxy(self), name: "trailer")
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 180), configuration: config)
        web.isOpaque = false
        web.scrollView.isScrollEnabled = false
        web.loadHTMLString(Self.page(first: id), baseURL: URL(string: Self.origin))
        webView = web
    }

    func play(_ key: String) {
        guard let id = Self.clean(key) else { return }
        if failed.contains(id) { onFailure(id); return }
        prepare(id)
        loadingKey = id
        OrientationLock.allowLandscape(true)
        webView?.evaluateJavaScript("play('\(id)')")
        // A player that never answers (offline, YouTube down) shouldn't spin forever.
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self, self.loadingKey == id else { return }
            self.finish(failedKey: id)
        }
    }

    private func finish(failedKey: String? = nil) {
        timeout?.cancel()
        let tapped = loadingKey
        loadingKey = nil
        guard let failedKey else { return }
        failed.insert(failedKey)
        OrientationLock.allowLandscape(false)
        // Only a tap leads to YouTube; a failure while preloading just waits for one.
        if tapped == failedKey { onFailure(failedKey) }
    }

    fileprivate func received(event: String, state: Int?, key: String?) {
        switch event {
        case "error":
            finish(failedKey: key.flatMap(Self.clean) ?? loadingKey)
        case "state" where state == 1:
            finish()
        case "state" where state == 0:
            finish()
            OrientationLock.allowLandscape(false)
        case "state" where state == 2:
            finish()
            // Leaving the full-screen player pauses the video; pausing inside it doesn't close it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if !Self.fullScreenVideoShowing { OrientationLock.allowLandscape(false) }
            }
        default: break
        }
    }

    private static var fullScreenVideoShowing: Bool {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).contains { window in
            var vc = window.rootViewController
            while let current = vc {
                if String(describing: type(of: current)).hasPrefix("AV") { return true }
                vc = current.presentedViewController
            }
            return false
        }
    }

    /// Keys only ever hold these characters; anything else would end up inside JavaScript.
    private static func clean(_ key: String) -> String? {
        let id = key.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        return id.isEmpty ? nil : id
    }

    private static func page(first id: String) -> String {
        """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body{margin:0;height:100%;background:#000}#p{width:100%;height:100%}</style>
        </head><body><div id="p"></div>
        <script>
        var player, ready = false, pending = null, current = '\(id)';
        function post(m) { window.webkit.messageHandlers.trailer.postMessage(m); }
        function play(k) {
          if (!ready) { pending = k; return; }
          if (k === current) { player.playVideo(); } else { current = k; player.loadVideoById(k); }
        }
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('p', {
            width: '100%', height: '100%', videoId: current,
            playerVars: { playsinline: 0, rel: 0, origin: '\(origin)' },
            events: {
              onReady: function () { ready = true; if (pending) { var k = pending; pending = null; play(k); } },
              onError: function (e) { post({ event: 'error', code: e.data, key: current }); },
              onStateChange: function (e) { post({ event: 'state', state: e.data }); }
            }
          });
        }
        </script>
        <script src="https://www.youtube.com/iframe_api"></script>
        </body></html>
        """
    }
}

extension View {
    /// Keeps `player` in the window, and sends videos YouTube won't play here to YouTube itself.
    func trailerHost(_ player: TrailerPlayer) -> some View { modifier(TrailerHostModifier(player: player)) }
}

private struct TrailerHostModifier: ViewModifier {
    let player: TrailerPlayer
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .background {
                TrailerPlayerHost(player: player).frame(width: 2, height: 2).opacity(0.01).accessibilityHidden(true)
            }
            .onAppear {
                player.onFailure = { key in
                    if let url = URL(string: "https://www.youtube.com/watch?v=\(key)") { openURL(url) }
                }
            }
    }
}

/// Keeps the hidden player in the window; WebKit only plays videos of web views that are on screen.
private struct TrailerPlayerHost: UIViewRepresentable {
    let player: TrailerPlayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        guard let web = player.webView, web.superview !== view else { return }
        view.subviews.forEach { $0.removeFromSuperview() }
        web.frame = view.bounds
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(web)
    }
}

/// The page's messages, passed on without the content controller keeping the player alive.
private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var player: TrailerPlayer?

    init(_ player: TrailerPlayer) { self.player = player }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let event = body["event"] as? String else { return }
        let state = (body["state"] as? NSNumber)?.intValue
        let key = body["key"] as? String
        MainActor.assumeIsolated { player?.received(event: event, state: state, key: key) }
    }
}
