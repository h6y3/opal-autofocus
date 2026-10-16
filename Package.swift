// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "opal-autofocus",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "opal-autofocus", targets: ["OpalAutofocusCLI"]),
        .library(name: "OpalUVC", targets: ["OpalUVC"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "COpalUSB",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .target(name: "OpalUVC", dependencies: ["COpalUSB"]),
        .executableTarget(
            name: "OpalAutofocusCLI",
            dependencies: [
                "OpalUVC",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "OpalUVCTests", dependencies: ["OpalUVC"]),
        .testTarget(name: "OpalAutofocusCLITests", dependencies: ["OpalAutofocusCLI"]),
    ],
    swiftLanguageModes: [.v5]
)
