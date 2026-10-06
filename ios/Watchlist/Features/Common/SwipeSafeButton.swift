import SwiftUI
import UIKit

/// A button that ignores the tap when the finger dragged first. A plain `Button` fires wherever the finger
/// lifts inside it, so flicking across a wide card to change tabs used to open the card.
struct SwipeSafeButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder var label: Label
    @State private var dragged = false

    var body: some View {
        let button = Button { if !dragged { action() } } label: { label }
        if #available(iOS 18, *) {
            button.gesture(MoveWatcher(touched: { dragged = false }, moved: { dragged = true }))
        } else {
            button.simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in dragged = true }.onEnded { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { dragged = false }
            })
        }
    }
}

/// Notices the finger moving over the view, then steps aside at once. A recognizer that kept tracking would
/// make the page's swipe wait for the finger to lift; one that has failed holds nothing up.
@available(iOS 18, *)
struct MoveWatcher: UIGestureRecognizerRepresentable {
    /// A new touch began: the last drag is over.
    let touched: () -> Void
    let moved: () -> Void

    func makeUIGestureRecognizer(context: Context) -> Recognizer {
        let recognizer = Recognizer()
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: Recognizer, context: Context) {
        recognizer.touched = touched
        recognizer.moved = moved
    }

    final class Recognizer: UIGestureRecognizer {
        var touched: () -> Void = {}
        var moved: () -> Void = {}
        private var start: CGPoint?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            start = touches.first?.location(in: view)
            touched()
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            if travelled(touches) {
                moved()
                state = .failed
            }
        }

        // A fast flick can end before any move reaches here, so the distance is checked at the end too.
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            if travelled(touches) { moved() }
            state = .failed
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            if travelled(touches) { moved() }
            state = .failed
        }

        override func reset() { start = nil }

        // Never pushed out by the page's swipe, which would otherwise stop it from seeing the move.
        override func canBePrevented(by preventing: UIGestureRecognizer) -> Bool { false }
        override func canPrevent(_ prevented: UIGestureRecognizer) -> Bool { false }

        private func travelled(_ touches: Set<UITouch>) -> Bool {
            guard let start, let now = touches.first?.location(in: view) else { return false }
            return hypot(now.x - start.x, now.y - start.y) > 10
        }
    }
}
