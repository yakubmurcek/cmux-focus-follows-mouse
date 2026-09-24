// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "cmux-focus-follows-mouse",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "cmux-ffm", targets: ["cmux-ffm"])
    ],
    targets: [
        .executableTarget(
            name: "cmux-ffm",
            path: "Sources"
        )
    ]
)
