// swift-tools-version:5.9
// Builds the Mac menu bar app. The iPhone app is the Xcode project from project.yml.
import PackageDescription

let package = Package(
    name: "Frank",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FrankMac", targets: ["FrankMac"]),
    ],
    targets: [
        .target(name: "FrankShared", path: "Shared", exclude: ["Fonts"]),
        .executableTarget(
            name: "FrankMac",
            dependencies: ["FrankShared"],
            path: "Mac",
            exclude: ["Info.plist"]
        ),
    ]
)
