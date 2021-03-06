// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Dragoman",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13)],
    products: [
        .library(
            name: "Dragoman",
            targets: ["Dragoman"]),
    ],
    dependencies: [
        .package(name: "Shout", url: "https://github.com/helsingborg-stad/spm-shout.git", from: "0.1.3"),
        .package(name: "TextTranslator", url: "https://github.com/helsingborg-stad/spm-text-translator", from: "0.2.1")
    ],
    targets: [
        .target(
            name: "Dragoman",
            dependencies: ["TextTranslator","Shout"]),
        .testTarget(
            name: "DragomanTests",
            dependencies: ["Dragoman"]),
    ]
)
