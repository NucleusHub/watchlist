import AVFoundation
import Observation
import WebKit

/// One browsing session: the web view, its state, and the playback it saves for the title.
@MainActor
@Observable
final class BrowserModel: NSObject {
    @ObservationIgnored let webView: WKWebView
    private(set) var host = ""
    private(set) var progress = 0.0
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var failed = false
    private(set) var notice: String?
    private(set) var canUndo = false
    /// The page on screen already counted an episode, so the button waits for another page.
    private(set) var pageMarked = false
    private(set) var offerMovie = false
    private(set) var hasPlayback = false

    /// Credits and next-episode overlays start well before the file ends.
    private static let episodeDone = 0.9

    @ObservationIgnored private var store: WatchlistStore?
    @ObservationIgnored private var itemID: String?
    @ObservationIgnored private var home: URL?
    @ObservationIgnored private var resume: Playback?
    @ObservationIgnored private var latest: Playback?
    @ObservationIgnored private var savedAt = Date.distantPast
    @ObservationIgnored private var offered = Set<String>()
    @ObservationIgnored private var finished = Set<String>()
    @ObservationIgnored private var undoState: (seasons: [SeasonProgress]?, status: WatchStatus, playback: Playback?)?
    @ObservationIgnored private var noticeID = 0
    @ObservationIgnored private var pageTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSKeyValueObservation] = []

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.preferences.isElementFullscreenEnabled = true
        // Without this some players take the page for a desktop browser and refuse to start.
        config.applicationNameForUserAgent = "Version/17.0 Mobile/15E148 Safari/604.1"
        let script = WKUserScript(source: VideoTracker.source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(script)
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        config.userContentController.addScriptMessageHandler(WeakHandler(self), contentWorld: .page, name: VideoTracker.handlerName)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        observers = [
            webView.observe(\.estimatedProgress) { [weak self] web, _ in MainActor.assumeIsolated { self?.progress = web.estimatedProgress } },
            webView.observe(\.canGoBack) { [weak self] web, _ in MainActor.assumeIsolated { self?.canGoBack = web.canGoBack } },
            webView.observe(\.canGoForward) { [weak self] web, _ in MainActor.assumeIsolated { self?.canGoForward = web.canGoForward } },
            webView.observe(\.url) { [weak self] web, _ in
                MainActor.assumeIsolated {
                    self?.host = web.url?.host?.replacingOccurrences(of: "www.", with: "") ?? ""
                    self?.refreshPageMarked()
                    self?.schedulePageSave()
                }
            },
        ]
    }

    func start(_ request: BrowserRequest, store: WatchlistStore) {
        guard self.store == nil else { return }
        self.store = store
        itemID = request.itemID
        home = request.home
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        resume = item?.playback
        hasPlayback = resume != nil
        let first = (item?.lastPage ?? resume?.url).flatMap { URL(string: $0) } ?? request.home
        webView.load(URLRequest(url: first))
    }

    func flush() {
        savePage()
        save(force: true)
    }

    func stop() {
        flush()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: VideoTracker.handlerName, contentWorld: .page)
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private var item: Item? { itemID.flatMap { store?.item($0) } }

    // MARK: Actions

    var currentURL: URL? { webView.url }

    func goHome() { if let home { webView.load(URLRequest(url: home)) } }
    func reload() { failed = false; webView.reload() }

    func forgetPosition() {
        guard let itemID else { return }
        latest = nil
        resume = nil
        hasPlayback = false
        pageTask?.cancel()
        store?.updateItem(itemID) {
            $0.playback = nil
            $0.lastPage = nil
        }
    }

    func markMovieWatched() {
        guard let itemID else { return }
        latest = nil
        hasPlayback = false
        store?.markWatched(itemID)
        offerMovie = false
    }

    func dismissOffer() { offerMovie = false }

    /// Counts the next episode of a tracked show as watched; `undo()` takes it back.
    func markEpisode() {
        guard let itemID, let store, let item, item.isShow, let next = item.nextEpisode, !pageMarked else { return }
        undoState = (item.seasonProgress, item.status, item.playback)
        latest = nil
        hasPlayback = false
        if let url = webView.url?.absoluteString { finished.insert(url) }
        refreshPageMarked()
        store.markEpisodeWatched(itemID)
        show(String(localized: "Marked S\(next.season) E\(next.episode) as watched"), undoable: true, seconds: 6)
    }

    func undo() {
        guard let state = undoState, let itemID else { return }
        undoState = nil
        if let url = webView.url?.absoluteString { finished.remove(url) }
        refreshPageMarked()
        hasPlayback = state.playback != nil
        store?.updateItem(itemID) { item in
            item.seasonProgress = state.seasons
            item.status = state.status
            item.playback = state.playback
        }
        notice = nil
        canUndo = false
    }

    /// Remembers where you are shortly after the page settles, so a video isn't needed to pick up later.
    private func schedulePageSave() {
        pageTask?.cancel()
        pageTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            savePage()
        }
    }

    private func savePage() {
        pageTask?.cancel()
        guard let itemID, let store, let url = webView.url, ["http", "https"].contains(url.scheme),
              store.item(itemID)?.lastPage != url.absoluteString else { return }
        store.updateItem(itemID) { $0.lastPage = url.absoluteString }
    }

    private func refreshPageMarked() {
        pageMarked = webView.url.map { finished.contains($0.absoluteString) } ?? false
    }

    private func show(_ text: String, undoable: Bool = false, seconds: Double = 3) {
        noticeID += 1
        let id = noticeID
        notice = text
        canUndo = undoable
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard id == noticeID else { return }
            notice = nil
            canUndo = false
        }
    }

    // MARK: Playback

    fileprivate func handle(_ body: [String: Any], reply: (Any?, String?) -> Void) {
        let kind = body["kind"] as? String
        if kind == "attach" {
            reply(takeResume(duration: (body["duration"] as? NSNumber)?.doubleValue ?? 0), nil)
            return
        }
        reply(nil, nil)
        guard let position = (body["position"] as? NSNumber)?.doubleValue,
              let duration = (body["duration"] as? NSNumber)?.doubleValue,
              duration > 0, let url = webView.url?.absoluteString else { return }
        let fraction = position / duration
        if finished.contains(url) {
            // The episode is already counted; only rewinding it makes it count again.
            guard fraction < Self.episodeDone - 0.05 else { return }
            finished.remove(url)
            refreshPageMarked()
        }
        latest = Playback(url: url, position: position, duration: duration)
        save(force: kind != "progress")
        guard let item, !item.isCompleted else { return }
        if item.type == .movie {
            if fraction >= 0.9, offered.insert(url).inserted { offerMovie = true }
        } else if item.nextEpisode != nil, kind == "ended" || fraction >= Self.episodeDone {
            markEpisode()
        }
    }

    /// Where the video starts: the saved spot, once, on the page it was saved on and only in a video of the
    /// same length. A page can switch hosts, and each host's copy has its own cut and ads.
    private func takeResume(duration: Double) -> Double? {
        guard let saved = resume, saved.url == webView.url?.absoluteString,
              saved.position > 5, saved.position < saved.duration - 30,
              abs(duration - saved.duration) <= max(20, saved.duration * 0.03) else { return nil }
        resume = nil
        show(String(localized: "Resumed at \(PlaybackTime.clock(saved.position))"))
        return saved.position
    }

    private func save(force: Bool) {
        guard let latest, let itemID, let store, force || Date().timeIntervalSince(savedAt) >= 20 else { return }
        savedAt = Date()
        hasPlayback = true
        store.updateItem(itemID) { item in
            item.playback = latest
            item.set("lastWatchedAt", .string(Timestamp.now()))
            if item.status == .planned { item.status = .watching }
        }
    }
}

extension BrowserModel: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        // Ads like to bounce into apps and the App Store.
        guard let scheme = action.request.url?.scheme?.lowercased() else { return .cancel }
        return ["http", "https", "about", "blob", "data"].contains(scheme) ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { failed = false }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { failed = true }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Links the user tapped open in place; other popups are ads.
        if action.navigationType == .linkActivated { webView.load(action.request) }
        return nil
    }
}

extension BrowserModel {
    /// The content controller holds its handlers strongly; this keeps it from holding the model.
    final class WeakHandler: NSObject, WKScriptMessageHandlerWithReply {
        private weak var model: BrowserModel?
        init(_ model: BrowserModel) { self.model = model }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                                   replyHandler: @escaping @MainActor (Any?, String?) -> Void) {
            guard let body = message.body as? [String: Any] else { return replyHandler(nil, nil) }
            Task { @MainActor in
                guard let model else { return replyHandler(nil, nil) }
                model.handle(body, reply: replyHandler)
            }
        }
    }
}
