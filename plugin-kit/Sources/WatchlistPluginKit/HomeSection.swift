import NucleusPlugins
import SwiftUI

/// A title as plugins see it: a read-only snapshot, so plugins don't depend on the app's model.
public struct PluginTitle: Identifiable, Hashable, Sendable {
    public struct Resume: Hashable, Sendable {
        public let position: Double
        public let duration: Double

        public init(position: Double, duration: Double) {
            self.position = position
            self.duration = duration
        }

        public var fraction: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }
    }

    public struct Episode: Hashable, Sendable {
        public let season: Int
        public let episode: Int

        public init(season: Int, episode: Int) {
            self.season = season
            self.episode = episode
        }
    }

    public let id: String
    public let title: String
    public let kind: MediaKind
    public let posterURL: URL?
    public let isCompleted: Bool
    /// When the person last watched it in the app's browser; nil if never.
    public let lastWatchedAt: Date?
    /// Where the video was left, if a position is saved.
    public let resume: Resume?
    /// The next episode of a show with tracked episodes.
    public let nextEpisode: Episode?
    /// The site of the page to jump back to; nil when there is nothing to jump back to.
    public let resumeHost: String?

    public init(id: String, title: String, kind: MediaKind, posterURL: URL?, isCompleted: Bool, lastWatchedAt: Date?,
                resume: Resume?, nextEpisode: Episode?, resumeHost: String?) {
        self.id = id
        self.title = title
        self.kind = kind
        self.posterURL = posterURL
        self.isCompleted = isCompleted
        self.lastWatchedAt = lastWatchedAt
        self.resume = resume
        self.nextEpisode = nextEpisode
        self.resumeHost = resumeHost
    }
}

/// What the app hands a home section each time it draws.
@MainActor
public struct HomeSectionContext {
    public let titles: [PluginTitle]
    /// False when the person turned the in-app browser off, so there is nothing to resume into.
    public let canResume: Bool
    /// Opens the title in the app's browser where it was left.
    public let resume: @MainActor (String) -> Void

    public init(titles: [PluginTitle], canResume: Bool, resume: @escaping @MainActor (String) -> Void) {
        self.titles = titles
        self.canResume = canResume
        self.resume = resume
    }
}

/// A section a plugin puts at the top of the Watchlist's home. Return an empty view to show nothing.
public protocol HomeSection: Sendable {
    var id: String { get }
    @MainActor func view(_ context: HomeSectionContext) -> AnyView
}

public extension ExtensionPoint where Contribution == any HomeSection {
    static var homeSections: Self { .init("watchlist.homeSections") }
}
