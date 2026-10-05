import Foundation

/// The script injected into every page and frame of the in-app browser. It follows any long video
/// by its media events, so it doesn't depend on the site; the app answers `attach` with where to resume.
enum VideoTracker {
    static let handlerName = "watchlist"
    /// Shorter videos are ads and previews.
    static let minimumDuration: Double = 120
    /// How long after a resume the script undoes jumps away from it; a seek of your own inside it is undone too.
    nonisolated(unsafe) static var resumeGuardSeconds: Double = 6

    static var source: String { """
    (() => {
      if (window.__watchlistTracker) return;
      window.__watchlistTracker = true;
      const MIN = \(Int(minimumDuration));
      const EVENTS = ['loadedmetadata', 'durationchange', 'playing', 'timeupdate', 'pause', 'seeked', 'ended'];
      const send = (m) => { try { return window.webkit.messageHandlers.\(handlerName).postMessage(m); } catch (e) {} };
      const state = new WeakMap();
      const guards = new WeakMap();
      const watched = new WeakSet();
      const roots = [document];
      let sentAt = 0;

      async function attach(v) {
        state.set(v, 'pending');
        const resume = await send({ kind: 'attach', duration: v.duration });
        state.set(v, 'ready');
        if (typeof resume === 'number' && resume > 0 && Math.abs(v.currentTime - resume) > 5) {
          guards.set(v, { target: resume, until: Date.now() + \(Int(resumeGuardSeconds * 1000)), tries: 0 });
          v.currentTime = resume;
        }
      }

      function onMedia(e) {
        if (e.__watchlist) return;
        e.__watchlist = true;
        const v = e.target;
        if (!(v instanceof HTMLMediaElement) || !isFinite(v.duration) || v.duration < MIN) return;
        if (!state.has(v)) attach(v);
        if (state.get(v) !== 'ready' || e.type === 'loadedmetadata' || e.type === 'durationchange') return;
        // Players often restore a position of their own just after load; win that tug of war a few times.
        const g = guards.get(v);
        if (g && Date.now() < g.until && g.tries < 3 && e.type !== 'ended' && Math.abs(v.currentTime - g.target) > 20) {
          g.tries++;
          v.currentTime = g.target;
          return;
        }
        const now = Date.now();
        // Closer reports near the end, where players tend to jump to the next page.
        const gap = v.currentTime / v.duration >= 0.85 ? 1000 : 3000;
        if (e.type === 'timeupdate' && now - sentAt < gap) return;
        sentAt = now;
        send({ kind: e.type === 'timeupdate' ? 'progress' : e.type, position: v.currentTime, duration: v.duration });
      }

      // Listening on the element itself also reaches players inside shadow roots, where document-level listeners don't.
      function watch(v) {
        if (watched.has(v)) return;
        watched.add(v);
        for (const t of EVENTS) v.addEventListener(t, onMedia);
        if (v.readyState >= 1) onMedia({ type: 'loadedmetadata', target: v });
      }

      for (const t of EVENTS) document.addEventListener(t, onMedia, true);

      const attachShadow = Element.prototype.attachShadow;
      Element.prototype.attachShadow = function (init) {
        const root = attachShadow.call(this, init);
        roots.push(root);
        return root;
      };
      const play = HTMLMediaElement.prototype.play;
      HTMLMediaElement.prototype.play = function (...args) {
        watch(this);
        return play.apply(this, args);
      };
      setInterval(() => roots.forEach((r) => r.querySelectorAll('video, audio').forEach(watch)), 2000);
    })();
    """ }
}
