import QuartzCore
import UIKit

/// Logs frames that came late (`-frameMonitor`), for chasing jank; also in Release, where it matters.
@MainActor
final class FrameMonitor: NSObject {
    static let shared = FrameMonitor()
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var late = 0
    private var frames = 0

    func start() {
        guard ProcessInfo.processInfo.arguments.contains("-frameMonitor"), link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in
                let monitor = FrameMonitor.shared
                NSLog("FRAMES %d late of %d", monitor.late, monitor.frames)
                monitor.late = 0
                monitor.frames = 0
            }
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { last = link.timestamp }
        guard last > 0 else { return }
        let gap = link.timestamp - last
        let expected = link.targetTimestamp - link.timestamp
        frames += 1
        if gap > max(expected, 1.0 / 120) * 1.8 {
            late += 1
            NSLog("HITCH %.0f ms", gap * 1000)
        }
    }
}
