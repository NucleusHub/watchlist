#if canImport(UIKit)
import NucleusUI
import SwiftUI

/// A poster from a URL, with a film glyph while there's none.
public struct TitlePoster: View {
    let url: URL?
    let cornerRadius: CGFloat

    public init(url: URL?, cornerRadius: CGFloat = 14) {
        self.url = url
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Nucleus.well)
            .overlay {
                if let url {
                    AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                } else {
                    Image(systemName: "film").foregroundStyle(Nucleus.secondaryText)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// A circular photo, with initials sized to the circle when there's no picture.
public struct PersonPhoto: View {
    let url: URL?
    let name: String

    public init(url: URL?, name: String) {
        self.url = url
        self.name = name
    }

    public var body: some View {
        Circle()
            .fill(Nucleus.well)
            .overlay {
                if let url {
                    AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { initials }
                } else {
                    initials
                }
            }
            .clipShape(Circle())
    }

    private var initials: some View {
        GeometryReader { geo in
            Text(verbatim: name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined())
                .font(.system(size: max(12, geo.size.width * 0.34), weight: .semibold, design: .rounded))
                .foregroundStyle(Nucleus.secondaryText)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// Marks titles already in the watchlist.
public struct LibraryBadge: View {
    var size: CGFloat

    public init(size: CGFloat = 20) { self.size = size }

    public var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.inLibrary))
            .accessibilityLabel("In your watchlist")
    }
}

public extension Color {
    /// Green for "already in your watchlist".
    static let inLibrary = Color(red: 0.2, green: 0.78, blue: 0.35)
}
#endif
