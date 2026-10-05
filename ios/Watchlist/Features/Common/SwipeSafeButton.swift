import SwiftUI

/// A button that ignores the tap when the finger dragged first. A plain `Button` fires wherever the finger
/// lifts inside it, so flicking across a wide card to change tabs used to open the card.
struct SwipeSafeButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder var label: Label
    @State private var dragged = false

    var body: some View {
        Button { if !dragged { action() } } label: { label }
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { _ in dragged = true }
                    // The tap lands right after the drag ends; clear the flag once it has had its chance.
                    .onEnded { _ in DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { dragged = false } }
            )
    }
}
