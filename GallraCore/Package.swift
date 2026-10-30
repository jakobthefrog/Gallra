// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GallraCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "GallraCore", targets: ["GallraCore"]),
    ],
    targets: [
        .target(name: "GallraCore"),
        .testTarget(name: "GallraCoreTests", dependencies: ["GallraCore"]),
    ]
)
