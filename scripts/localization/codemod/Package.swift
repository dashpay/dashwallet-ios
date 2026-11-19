// swift-tools-version: 6.0
import PackageDescription

// swift-syntax 603.0.2 is the 6.3 release line; it resolves and builds with the Swift 6.4 toolchain of Xcode 27.2.
let package = Package(
    name: "codemod",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "603.0.2"),
    ],
    targets: [
        .target(
            name: "LocalizationCodemod",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        .executableTarget(name: "codemod", dependencies: ["LocalizationCodemod"]),
        .testTarget(name: "LocalizationCodemodTests", dependencies: ["LocalizationCodemod"]),
    ]
)
