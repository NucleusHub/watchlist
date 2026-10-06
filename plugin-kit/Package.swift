// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WatchlistPluginKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WatchlistPluginKit", targets: ["WatchlistPluginKit"]),
    ],
    dependencies: [
        .package(path: "../../../nucleus-native-plugins"),
        .package(url: "https://github.com/NucleusHub/nucleus-native-ui", from: "0.1.0"),
    ],
    targets: [
        .target(name: "WatchlistPluginKit", dependencies: [
            .product(name: "NucleusPlugins", package: "nucleus-native-plugins"),
            .product(name: "NucleusUI", package: "nucleus-native-ui", condition: .when(platforms: [.iOS])),
        ]),
    ]
)
