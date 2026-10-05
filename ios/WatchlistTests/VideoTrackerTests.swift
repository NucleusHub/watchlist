import WebKit
import XCTest
@testable import Watchlist

@MainActor
final class VideoTrackerTests: XCTestCase {
    override func setUp() { VideoTracker.resumeGuardSeconds = 0.05 }
    override func tearDown() { VideoTracker.resumeGuardSeconds = 6 }

    /// Drives the injected script with a fake long video: it must resume once, then report progress.
    func testResumesSavedPositionThenSavesProgress() async throws {
        let store = WatchlistStore(fileURL: nil, document: WatchlistDocument())
        let id = try XCTUnwrap(store.createItem(Item(title: "A", type: .movie))).id
        store.updateItem(id) { $0.playback = Playback(url: "https://example.com/watch", position: 300, duration: 6000) }

        let model = BrowserModel()
        model.start(BrowserRequest(home: URL(string: "https://example.com/watch")!, itemID: id), store: store)
        model.webView.stopLoading()
        model.webView.loadHTMLString("<html><body></body></html>", baseURL: URL(string: "https://example.com/watch"))
        try await waitUntil { model.webView.url?.absoluteString == "https://example.com/watch" && !model.webView.isLoading }

        let js = """
        const v = document.createElement('video');
        let t = 0;
        Object.defineProperty(v, 'duration', { get: () => 6000 });
        Object.defineProperty(v, 'currentTime', { get: () => t, set: (x) => { t = x; } });
        document.body.appendChild(v);
        v.dispatchEvent(new Event('loadedmetadata'));
        await new Promise(r => setTimeout(r, 300));
        const resumed = t;
        t = 1500;
        v.dispatchEvent(new Event('pause'));
        await new Promise(r => setTimeout(r, 300));
        return resumed;
        """
        let resumed = try await model.webView.callAsyncJavaScript(js, contentWorld: .page) as? Double
        XCTAssertEqual(resumed, 300)
        try await waitUntil { store.item(id)?.playback?.position == 1500 }
        XCTAssertEqual(store.item(id)?.status, .watching)
        model.stop()
    }

    /// A player inside a shadow root, which document-level listeners can't see; seeking back to the start is saved too.
    func testTracksShadowDomPlayerAndSavesSeekToStart() async throws {
        let store = WatchlistStore(fileURL: nil, document: WatchlistDocument())
        let id = try XCTUnwrap(store.createItem(Item(title: "S", type: .show))).id
        store.updateItem(id) { $0.playback = Playback(url: "https://example.com/ep", position: 900, duration: 1500) }

        let model = BrowserModel()
        model.start(BrowserRequest(home: URL(string: "https://example.com/ep")!, itemID: id), store: store)
        model.webView.stopLoading()
        model.webView.loadHTMLString("<html><body><div id=host></div></body></html>", baseURL: URL(string: "https://example.com/ep"))
        try await waitUntil { model.webView.url?.absoluteString == "https://example.com/ep" && !model.webView.isLoading }

        let js = """
        const root = document.getElementById('host').attachShadow({ mode: 'open' });
        const v = document.createElement('video');
        let t = 0;
        Object.defineProperty(v, 'duration', { get: () => 1500 });
        Object.defineProperty(v, 'currentTime', { get: () => t, set: (x) => { t = x; } });
        root.appendChild(v);
        await new Promise(r => setTimeout(r, 2500));
        v.dispatchEvent(new Event('loadedmetadata'));
        await new Promise(r => setTimeout(r, 300));
        const resumed = t;
        t = 2;
        v.dispatchEvent(new Event('seeked'));
        await new Promise(r => setTimeout(r, 300));
        return resumed;
        """
        let resumed = try await model.webView.callAsyncJavaScript(js, contentWorld: .page) as? Double
        XCTAssertEqual(resumed, 900)
        try await waitUntil { store.item(id)?.playback?.position == 2 }
        model.stop()
    }

    /// A show counts an episode when its video nears the end, once, and Undo takes it back.
    func testShowEpisodeIsMarkedWhenVideoEndsAndCanBeUndone() async throws {
        let store = WatchlistStore(fileURL: nil, document: WatchlistDocument())
        var show = Item(title: "S", type: .show)
        show.seasonProgress = [SeasonProgress(seasonNumber: 1, name: "S1", episodeCount: 3, watched: 0)]
        let id = try XCTUnwrap(store.createItem(show)).id

        let model = BrowserModel()
        model.start(BrowserRequest(home: URL(string: "https://example.com/e1")!, itemID: id), store: store)
        model.webView.stopLoading()
        model.webView.loadHTMLString("<html><body></body></html>", baseURL: URL(string: "https://example.com/e1"))
        try await waitUntil { model.webView.url?.absoluteString == "https://example.com/e1" && !model.webView.isLoading }

        let js = """
        const v = document.createElement('video');
        let t = 0;
        Object.defineProperty(v, 'duration', { get: () => 1500 });
        Object.defineProperty(v, 'currentTime', { get: () => t, set: (x) => { t = x; } });
        document.body.appendChild(v);
        v.dispatchEvent(new Event('loadedmetadata'));
        await new Promise(r => setTimeout(r, 300));
        t = 1380;
        v.dispatchEvent(new Event('timeupdate'));
        await new Promise(r => setTimeout(r, 300));
        """
        _ = try await model.webView.callAsyncJavaScript(js, contentWorld: .page)
        try await waitUntil { store.item(id)?.seasonProgress?.first?.watched == 1 }
        XCTAssertNil(store.item(id)?.playback)
        XCTAssertTrue(model.canUndo)
        XCTAssertTrue(model.pageMarked)
        model.markEpisode()
        XCTAssertEqual(store.item(id)?.seasonProgress?.first?.watched, 1, "a page counts one episode")
        model.undo()
        XCTAssertFalse(model.pageMarked)
        XCTAssertEqual(store.item(id)?.seasonProgress?.first?.watched, 0)
        model.markEpisode()
        XCTAssertEqual(store.item(id)?.seasonProgress?.first?.watched, 1)
        model.webView.loadHTMLString("<html></html>", baseURL: URL(string: "https://example.com/e2"))
        try await waitUntil { model.webView.url?.absoluteString == "https://example.com/e2" && !model.pageMarked }
        model.stop()
    }

    /// A player that restores its own position after ours doesn't win, and a video of another length is left alone.
    func testResumeBeatsPlayerRestoreAndSkipsOtherLengths() async throws {
        VideoTracker.resumeGuardSeconds = 6
        let store = WatchlistStore(fileURL: nil, document: WatchlistDocument())
        let id = try XCTUnwrap(store.createItem(Item(title: "A", type: .movie))).id
        store.updateItem(id) { $0.playback = Playback(url: "https://example.com/w", position: 300, duration: 6000) }
        let model = BrowserModel()
        model.start(BrowserRequest(home: URL(string: "https://example.com/w")!, itemID: id), store: store)
        model.webView.stopLoading()
        model.webView.loadHTMLString("<html><body></body></html>", baseURL: URL(string: "https://example.com/w"))
        try await waitUntil { model.webView.url?.absoluteString == "https://example.com/w" && !model.webView.isLoading }

        let js = """
        const make = (d) => {
          const v = document.createElement('video');
          let t = 0;
          Object.defineProperty(v, 'duration', { get: () => d });
          Object.defineProperty(v, 'currentTime', { get: () => t, set: (x) => { t = x; } });
          document.body.appendChild(v);
          return [v, () => t, (x) => { t = x; }];
        };
        const [other, otherT] = make(7000);
        other.dispatchEvent(new Event('loadedmetadata'));
        await new Promise(r => setTimeout(r, 300));
        const untouched = otherT();
        const [v, getT, setT] = make(6010);
        v.dispatchEvent(new Event('loadedmetadata'));
        await new Promise(r => setTimeout(r, 300));
        setT(1500);
        v.dispatchEvent(new Event('seeked'));
        await new Promise(r => setTimeout(r, 300));
        return [untouched, getT()];
        """
        let result = try await model.webView.callAsyncJavaScript(js, contentWorld: .page) as? [Double]
        XCTAssertEqual(result, [0, 300])
        model.stop()
    }

    /// The page is remembered without any video, and reopens there.
    func testLastPageIsSavedWithoutVideo() async throws {
        let store = WatchlistStore(fileURL: nil, document: WatchlistDocument())
        let id = try XCTUnwrap(store.createItem(Item(title: "A", type: .movie))).id
        let model = BrowserModel()
        model.start(BrowserRequest(home: URL(string: "https://example.com/")!, itemID: id), store: store)
        model.webView.stopLoading()
        model.webView.loadHTMLString("<html></html>", baseURL: URL(string: "https://example.com/episode-3"))
        try await waitUntil { model.webView.url?.absoluteString == "https://example.com/episode-3" && !model.webView.isLoading }
        model.stop()
        XCTAssertEqual(store.item(id)?.lastPage, "https://example.com/episode-3")
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("timed out")
    }
}
