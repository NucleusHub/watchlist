import NucleusUI
import SwiftUI

/// Ten stars in half steps (0.5–10). Tapping the current value clears it.
struct RatingControl: View {
    @Binding var rating: Double?
    var size: CGFloat = 24

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...10, id: \.self) { star in
                ZStack {
                    Image(systemName: symbol(for: star))
                        .font(.system(size: size * 0.82))
                        .foregroundStyle(fill(for: star) ? Color(hex: 0xFBBF24) : Nucleus.secondaryText.opacity(0.6))
                    HStack(spacing: 0) {
                        Color.clear.contentShape(Rectangle()).onTapGesture { set(Double(star) - 0.5) }
                        Color.clear.contentShape(Rectangle()).onTapGesture { set(Double(star)) }
                    }
                }
                .frame(width: size, height: size)
            }
            if rating != nil {
                Text(String(format: rating!.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", rating!))
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Nucleus.primaryText)
                    .padding(.leading, 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Your rating")
        .accessibilityValue(rating.map { String(format: "%.1f / 10", $0) } ?? String(localized: "None"))
        .accessibilityAdjustableAction { direction in
            let now = rating ?? 0
            rating = direction == .increment ? min(10, now + 0.5) : (now <= 0.5 ? nil : now - 0.5)
        }
    }

    private func symbol(for star: Int) -> String {
        guard let rating else { return "star" }
        if rating >= Double(star) { return "star.fill" }
        if rating >= Double(star) - 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }

    private func fill(for star: Int) -> Bool { (rating ?? 0) >= Double(star) - 0.5 }

    private func set(_ value: Double) {
        Haptics.selection()
        rating = rating == value ? nil : value
    }
}
