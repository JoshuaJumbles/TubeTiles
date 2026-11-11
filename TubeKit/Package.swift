// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TubeKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TubeKit", targets: ["TubeKit"]),
    ],
    targets: [
        .target(name: "TubeKit"),
        .testTarget(name: "TubeKitTests", dependencies: ["TubeKit"]),
    ]
)
