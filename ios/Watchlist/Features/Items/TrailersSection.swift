import NucleusUI
import SwiftUI

/// What a title is about.
struct OverviewSection: View {
    let text: String

    var body: some View {
        NucleusSection("Overview") {
            Text(verbatim: text)
                .font(.system(size: 15))
                .lineSpacing(2)
                .foregroundStyle(Nucleus.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
    }
}

/// The title's trailers and clips from TMDb. Tapping one plays it full screen; holding offers YouTube.
struct TrailersSection: View {
    let videos: [TMDb.Video]
    /// The video that was tapped and hasn't started yet.
    var loadingKey: String?
    let play: (TMDb.Video) -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        NucleusSection("Trailers") {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(videos.prefix(10)) { video in
                        Button { play(video) } label: { card(video) }
                            .buttonStyle(NucleusPressStyle(scale: 0.96))
                            .contextMenu {
                                Button { if let url = video.url { openURL(url) } } label: { Label("Open in YouTube", systemImage: "arrow.up.right") }
                            }
                            .accessibilityLabel(Text(verbatim: "\(video.kind): \(video.name)"))
                    }
                }
                .padding(14)
            }
        }
    }

    private func card(_ video: TMDb.Video) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: video.thumbnailURL) { $0.resizable().scaledToFill() } placeholder: { Nucleus.well }
                .frame(width: 220, height: 124)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    Group {
                        if loadingKey == video.key {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "play.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.black.opacity(0.55)))
                    .animation(.easeOut(duration: 0.15), value: loadingKey)
                }
            Text(verbatim: video.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Nucleus.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(verbatim: video.kind).font(.system(size: 12)).foregroundStyle(Nucleus.secondaryText)
        }
        .frame(width: 220, alignment: .leading)
    }
}
