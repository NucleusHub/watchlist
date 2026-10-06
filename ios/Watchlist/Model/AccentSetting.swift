import Foundation
import NucleusUI

/// This app's accent in the synced settings: `{ id, custom?, updatedAt }`. It carries its own stamp
/// and merges on its own, so a device that never picked one takes the account copy on sign-in
/// instead of overwriting it with newer, unrelated settings.
extension WatchlistSettings {
    var accent: NucleusAccent? {
        get {
            let o = raw["accent"]?.object
            return NucleusAccent(id: o?["id"]?.string, customHex: o?["custom"]?.string)
        }
        set {
            guard let newValue else { raw["accent"] = nil; return }
            var o: [String: JSONValue] = ["id": .string(newValue.id), "updatedAt": .string(Timestamp.now())]
            if let hex = newValue.customHex { o["custom"] = .string(hex) }
            raw["accent"] = .object(o)
        }
    }

    var accentStamp: Double { WatchlistDocument.stamp(raw["accent"]?.object) }

    /// When this app's own accent was last picked, on any device; nil if it never was.
    var accentPickedAt: Date? { Timestamp.date(raw["accent"]?.object?["updatedAt"]?.string) }

    /// `settings` with whichever accent of `a` and `b` was picked last.
    static func withNewerAccent(_ settings: WatchlistSettings, _ a: WatchlistSettings, _ b: WatchlistSettings) -> WatchlistSettings {
        var out = settings
        out.raw["accent"] = (b.accentStamp > a.accentStamp ? b : a).raw["accent"]
        return out
    }
}
