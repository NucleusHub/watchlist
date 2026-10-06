#if canImport(UIKit)
import Observation
import SwiftUI
import UIKit

/// Pages side by side, all kept loaded, that follow the finger: stop mid-swipe and both halves show,
/// let go and it settles on the nearer page (or the next one, when flicked).
/// Row swipe actions, sideways strips and vertical scrolling inside the pages keep their own gestures.
public struct PagedCarousel<Page: Hashable, Content: View>: View {
    let pages: [Page]
    @Binding var selection: Page
    let progress: CarouselProgress?
    let content: (Page) -> Content

    /// `progress` follows the finger, for pills that slide along; only views reading it redraw while dragging.
    public init(_ pages: [Page], selection: Binding<Page>, progress: CarouselProgress? = nil, @ViewBuilder content: @escaping (Page) -> Content) {
        self.pages = pages
        _selection = selection
        self.progress = progress
        self.content = content
    }

    public var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(pages, id: \.self) { page in
                    content(page)
                        .frame(width: geo.size.width, height: geo.size.height)
                        // Pages out of view stay loaded but aren't read out or found by UI tests.
                        .accessibilityHidden(page != selection)
                }
            }
            .modifier(CarouselMotion(index: pages.firstIndex(of: selection) ?? 0, count: pages.count, width: geo.size.width, progress: progress) { target in
                guard pages.indices.contains(target) else { return }
                selection = pages[target]
            })
        }
        .clipped()
    }
}

/// Where a carousel is between its pages while a finger drags it: 1.5 is halfway from the second page to the third.
@MainActor
@Observable
public final class CarouselProgress {
    public var position: CGFloat = 0
    public var isDragging = false

    public init() {}
}

/// The swipe itself. Kept apart from the pages so following the finger only moves them, never rebuilds them.
private struct CarouselMotion: ViewModifier {
    let index: Int
    let count: Int
    let width: CGFloat
    let progress: CarouselProgress?
    let settle: (Int) -> Void
    @State private var drag: CGFloat = 0

    func body(content: Content) -> some View {
        let x = -CGFloat(index) * width + resisted(drag)
        // A visual effect moves the pages when drawing only; an `.offset` would count as the pages moving,
        // so every view in them would have its geometry worked out again on every frame of the drag.
        let moved = content
            .visualEffect { page, _ in page.offset(x: x) }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        if #available(iOS 18, *) {
            moved.gesture(PagePan(changed: follow, ended: end))
        } else {
            moved.simultaneousGesture(DragGesture(minimumDistance: 20)
                .onChanged { if abs($0.translation.width) > abs($0.translation.height) { follow($0.translation.width) } }
                .onEnded { end($0.translation.width, $0.velocity.width) })
        }
    }

    private func follow(_ translation: CGFloat) {
        drag = translation
        guard let progress, width > 0 else { return }
        progress.isDragging = true
        progress.position = CGFloat(index) - resisted(translation) / width
    }

    /// Past the first or last page the pages still move, but only a third as far, so the edge is felt.
    private func resisted(_ drag: CGFloat) -> CGFloat {
        let pastStart = index == 0 && drag > 0
        let pastEnd = index == count - 1 && drag < 0
        return pastStart || pastEnd ? drag / 3 : drag
    }

    private func end(_ translation: CGFloat, _ velocity: CGFloat) {
        // A flick counts for more than its distance, so a quick short swipe still turns the page.
        let projected = translation + velocity * 0.25
        var target = index
        if projected < -width / 2 { target = index + 1 } else if projected > width / 2 { target = index - 1 }
        target = min(max(target, 0), count - 1)
        withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
            if target != index { settle(target) }
            drag = 0
            progress?.isDragging = false
            progress?.position = CGFloat(target)
        }
    }
}

/// A horizontal pan that steps aside for row swipe actions and sideways-scrolling strips, and makes vertical
/// scrolling wait only until it's clear the finger is going up or down.
@available(iOS 18, *)
private struct PagePan: UIGestureRecognizerRepresentable {
    let changed: (CGFloat) -> Void
    let ended: (CGFloat, CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed: changed(translation)
        case .ended: ended(translation, recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed: ended(translation, 0)
        default: break
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y) * 1.2
        }

        /// A swipe on a row's actions or along a sideways strip belongs to them.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
            if String(describing: type(of: other)).contains("SwipeAction") { return true }
            if let scroll = other.view as? UIScrollView, other === scroll.panGestureRecognizer {
                return scroll.contentSize.width > scroll.bounds.width + 1
            }
            return false
        }

        /// Vertical lists wait for this pan to decide; it gives up at once when the finger goes up or down.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            guard let scroll = other.view as? UIScrollView, other === scroll.panGestureRecognizer else { return false }
            return scroll.contentSize.width <= scroll.bounds.width + 1
        }
    }
}
#endif
