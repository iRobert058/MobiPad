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
        .library(name: "MobiPadVideo", targets: ["MobiPadVideo"]),
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
        // Both apps: the GamePad screen as H.264 video, split into datagrams (Mac) and put back together (phone).
        .target(name: "MobiPadVideo", dependencies: ["MobiPadProtocol"]),
        .testTarget(name: "MobiPadProtocolTests", dependencies: ["MobiPadProtocol"]),
        .testTarget(name: "MobiPadNetworkTests", dependencies: ["MobiPadNetwork"]),
        .testTarget(name: "MobiPadDSUTests", dependencies: ["MobiPadDSU", "MobiPadNetwork"]),
        .testTarget(name: "MobiPadKeyboardTests", dependencies: ["MobiPadKeyboard"]),
        .testTarget(name: "MobiPadVideoTests", dependencies: ["MobiPadVideo", "MobiPadProtocol"]),
    ]
)
