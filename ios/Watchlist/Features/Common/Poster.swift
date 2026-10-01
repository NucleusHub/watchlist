import NucleusUI
import SwiftUI

/// A poster from a URL or an inlined data URL, with a quiet placeholder while it loads.
struct Poster: View {
    let url: String?
    var type: ItemType = .movie
    var cornerRadius: CGFloat = 12

    var body: some View {
        Color.clear
            .overlay {
                if let url, url.hasPrefix("data:"), let image = Images.image(fromDataURL: url) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if let url, let u = URL(string: url) {
                    AsyncImage(url: u, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            Nucleus.well
            Image(systemName: type == .show ? "tv" : "film")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Nucleus.secondaryText)
        }
    }
}

extension WatchStatus {
    var color: Color {
        switch self {
        case .planned: Color(hex: 0xEB6834)
        case .watching: Color(hex: 0x2A78D6)
        case .completed: Color(hex: 0x1BAF7A)
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .planned: "Planned"
        case .watching: "Watching"
        case .completed: "Completed"
        }
    }

    var symbol: String {
        switch self {
        case .planned: "bookmark"
        case .watching: "play.circle"
        case .completed: "checkmark.circle.fill"
        }
    }
}

extension ItemType {
    var title: LocalizedStringKey { self == .movie ? "Movie" : "Show" }
    var symbol: String { self == .movie ? "film" : "tv" }
}

/// A small rounded tag.
struct Tag: View {
    let text: Text
    var color: Color? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let color { Circle().fill(color).frame(width: 6, height: 6) }
            text
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Nucleus.glyph)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(Nucleus.well))
    }
}

extension Item {
    /// "2024 · 2h 46m" or "2022 · 2 seasons · 19 ep".
    var metaLine: String {
        var parts: [String] = []
        if let year { parts.append(String(year)) }
        if type == .movie {
            if let runtime, runtime > 0 { parts.append(RuntimeText.short(runtime)) }
        } else {
            if let seasons, seasons > 0 { parts.append(String(localized: "\(seasons) seasons")) }
            if let episodes, episodes > 0 { parts.append(String(localized: "\(episodes) ep")) }
        }
        return parts.joined(separator: " · ")
    }
}
