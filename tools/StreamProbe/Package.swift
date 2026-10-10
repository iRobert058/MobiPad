// swift-tools-version: 6.0
import PackageDescription

// A development tool: streams video to the phone's Stream Test screen and measures the delay.
// Run with: swift run -c release --package-path tools/StreamProbe StreamProbe --help
let package = Package(
    name: "StreamProbe",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../MobiPadKit")],
    targets: [
        .executableTarget(
            name: "StreamProbe",
            dependencies: [.product(name: "MobiPadVideo", package: "MobiPadKit")]
        ),
    ]
)
