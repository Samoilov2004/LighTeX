// swift-tools-version: 6.1

import PackageDescription

let developerFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"

let package = Package(
    name: "LighTex",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LighTex", targets: ["LighTex"])
    ],
    targets: [
        .executableTarget(name: "LighTex"),
        .testTarget(
            name: "LighTexTests",
            dependencies: ["LighTex"],
            swiftSettings: [
                .unsafeFlags(["-F", developerFrameworks])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", developerFrameworks,
                    "-Xlinker", "-rpath",
                    "-Xlinker", developerFrameworks
                ])
            ]
        )
    ]
)
