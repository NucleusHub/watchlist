import Foundation
import NucleusUI
import Observation

enum GridStyle: String, CaseIterable, Codable {
    case list, big, small
}

/// Device-local preferences (UserDefaults). None of these sync.
@MainActor
@Observable
final class Preferences {
    private let defaults: UserDefaults

    var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    var gridStyle: GridStyle { didSet { defaults.set(gridStyle.rawValue, forKey: "gridStyle") } }
    var shakeToReport: Bool { didSet { defaults.set(shakeToReport, forKey: "shakeToReport") } }
    var inAppBrowser: Bool { didSet { defaults.set(inAppBrowser, forKey: "inAppBrowser") } }
    var hasSeenWelcome: Bool { didSet { defaults.set(hasSeenWelcome, forKey: "hasSeenWelcome") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "appearance": AppearanceMode.dark.rawValue,
            "gridStyle": GridStyle.small.rawValue,
            "shakeToReport": true,
            "inAppBrowser": true,
            "hasSeenWelcome": false,
        ])
        appearance = AppearanceMode(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .dark
        gridStyle = GridStyle(rawValue: defaults.string(forKey: "gridStyle") ?? "") ?? .small
        shakeToReport = defaults.bool(forKey: "shakeToReport")
        inAppBrowser = defaults.bool(forKey: "inAppBrowser")
        hasSeenWelcome = defaults.bool(forKey: "hasSeenWelcome")
    }
}
