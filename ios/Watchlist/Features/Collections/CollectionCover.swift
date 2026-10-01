import NucleusUI
import SwiftUI

/// A collection's cover: its own image, or member posters in slanted bands, or a folder.
struct CollectionCover: View {
    let collection: WatchCollection
    var posters: [String]? = nil
    @Environment(WatchlistStore.self) private var store

    var body: some View {
        let shown = Array((posters ?? store.coverPosters(of: collection)).prefix(8))
        ZStack {
            Nucleus.well
            if let cover = collection.coverUrl {
                Poster(url: cover, cornerRadius: 0)
            } else if shown.isEmpty {
                Image(systemName: "folder").font(.system(size: 28, weight: .light)).foregroundStyle(Nucleus.secondaryText)
            } else {
                GeometryReader { geo in
                    let skew = geo.size.width * 0.09
                    let band = (geo.size.width + skew) / CGFloat(shown.count)
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(shown.enumerated()), id: \.offset) { i, url in
                            Poster(url: url, cornerRadius: 0)
                                .frame(width: band + skew + 2, height: geo.size.height)
                                .clipShape(Band(skew: skew, gap: shown.count > 1 ? geo.size.width * 0.009 : 0))
                                .offset(x: CGFloat(i) * band - skew)
                        }
                    }
                }
            }
        }
        .clipped()
    }
}

/// A parallelogram leaning right; neighbours tile with a hairline gap.
private struct Band: Shape {
    let skew: CGFloat
    let gap: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + skew + gap, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - skew - gap, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
