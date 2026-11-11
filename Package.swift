// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MultiPaySDK",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "MultiPaySDK", targets: ["MultiPaySDK"]),
    ],
    targets: [
        .target(name: "MultiPaySDK"),
        .testTarget(name: "MultiPaySDKTests", dependencies: ["MultiPaySDK"]),
    ]
)
