// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MobiPadKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "MobiPadProtocol", targets: ["MobiPadProtocol"]),
        .library(name: "MobiPadNetwork", targets: ["MobiPadNetwork"]),
        .library(name: "MobiPadDSU", targets: ["MobiPadDSU"]),
        .library(name: "MobiPadKeyboard", targets: ["MobiPadKeyboard"]),
    ],
    targets: [
        // Shared by the iPhone app and the Mac companion app.
        .target(name: "MobiPadProtocol"),
        // Both apps: the phone's link to the Mac, the Mac's host for up to four phones, Bonjour discovery.
        .target(name: "MobiPadNetwork", dependencies: ["MobiPadProtocol"]),
        // Mac companion app only: serves controllers to emulators over the DSU protocol.
        .target(name: "MobiPadDSU", dependencies: ["MobiPadProtocol"]),
        // Mac companion app only: Player 1 as key presses, for emulators without DSU (Ryujinx).
        .target(name: "MobiPadKeyboard", dependencies: ["MobiPadProtocol"]),
        .testTarget(name: "MobiPadProtocolTests", dependencies: ["MobiPadProtocol"]),
        .testTarget(name: "MobiPadNetworkTests", dependencies: ["MobiPadNetwork"]),
        .testTarget(name: "MobiPadDSUTests", dependencies: ["MobiPadDSU", "MobiPadNetwork"]),
        .testTarget(name: "MobiPadKeyboardTests", dependencies: ["MobiPadKeyboard"]),
    ]
)
