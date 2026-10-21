// swift-tools-version:5.9
import PackageDescription

// ScrollCore holds the decision logic (which devices count as a mouse, and
// what natural scrolling should become). It uses Foundation only, so it and
// its tests build on Linux too. The menu bar app needs AppKit and IOKit, so
// it is only declared when the package is built on a Mac.
var targets: [Target] = [
    .target(
        name: "ScrollCore",
        path: "Sources/ScrollCore"
    ),
    .testTarget(
        name: "ScrollCoreTests",
        dependencies: ["ScrollCore"],
        path: "Tests/ScrollCoreTests"
    ),
]

#if os(macOS)
    targets.append(
        .executableTarget(
            name: "NaturalScrollToggle",
            dependencies: ["ScrollCore"],
            path: "Sources/NaturalScrollToggle"
        )
    )
#endif

let package = Package(
    name: "NaturalScrollToggle",
    platforms: [.macOS(.v14)],
    targets: targets
)
