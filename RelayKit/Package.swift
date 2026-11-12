// swift-tools-version: 5.9
// RelayKit : logique partagée de l'app Relay (modèles, client API, protocole Guacamole).
// Sans UIKit : compilable et testable sur Linux (swift test) comme sur iOS.
import PackageDescription

let package = Package(
    name: "RelayKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "RelayKit", targets: ["RelayKit"])],
    targets: [
        .target(name: "RelayKit", swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]),
        .testTarget(name: "RelayKitTests", dependencies: ["RelayKit"]),
    ],
    swiftLanguageVersions: [.v5]
)
