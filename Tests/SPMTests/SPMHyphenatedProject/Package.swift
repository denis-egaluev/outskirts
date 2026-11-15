// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SPMHyphenatedProject",
    targets: [
        .target(name: "My-Lib"),
        .testTarget(name: "My-LibTests", dependencies: ["My-Lib"]),
    ]
)
