import NucleusPlugins

/// Says a plugin reads the person's MovieDNA, so the app can tell them what it powers.
/// With no plugin contributing one, MovieDNA has no effect and the app says so.
public struct MovieDNAUse: Sendable {
    /// What the plugin does with it, already in the person's language, e.g. "Picks what Discover shows you".
    public let purpose: String

    public init(purpose: String) {
        self.purpose = purpose
    }
}

public extension ExtensionPoint where Contribution == MovieDNAUse {
    static var movieDNAUses: Self { .init("watchlist.movieDNAUses") }
}
