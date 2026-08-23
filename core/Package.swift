// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BackdropCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "BackdropCore", targets: ["BackdropCore"]),
    ],
    targets: [
        .target(name: "BackdropCore"),
        .testTarget(name: "BackdropCoreTests", dependencies: ["BackdropCore"]),
    ],
    swiftLanguageModes: [.v5]
)
