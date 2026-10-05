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
    ],
    targets: [
        .target(name: "WatchlistPluginKit", dependencies: [
            .product(name: "NucleusPlugins", package: "nucleus-native-plugins"),
        ]),
    ]
)
