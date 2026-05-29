// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "UltraDolmengSpotifyLyric",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "UltraDolmengSpotifyLyric", targets: ["UltraDolmengSpotifyLyric"])
    ],
    targets: [
        .target(
            name: "UltraDolmengCore",
            path: "Sources/UltraDolmengCore"
        ),
        .executableTarget(
            name: "UltraDolmengSpotifyLyric",
            dependencies: ["UltraDolmengCore"],
            path: "Sources/UltraDolmengSpotifyLyric"
        ),
        .testTarget(
            name: "UltraDolmengCoreTests",
            dependencies: ["UltraDolmengCore"],
            path: "Tests/UltraDolmengCoreTests"
        )
    ]
)
