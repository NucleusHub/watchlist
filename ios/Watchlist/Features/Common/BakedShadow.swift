import SwiftUI

extension View {
    /// A drop shadow drawn once into a bitmap that then just moves with the view. A live `.shadow` is worked
    /// out again every frame the view moves, which a pager full of posters can't afford.
    func bakedShadow(cornerRadius: CGFloat, color: Color = .black.opacity(0.25), radius: CGFloat, y: CGFloat) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(color)
                .blur(radius: radius / 2)
                .offset(y: y)
                .padding(-radius)
                .drawingGroup()
                .padding(radius)
                .allowsHitTesting(false)
        }
    }
}
