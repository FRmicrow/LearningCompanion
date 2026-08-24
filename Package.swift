// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipboardVocab",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ClipboardVocab", targets: ["ClipboardVocab"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0")
    ],
    targets: [
        .executableTarget(
            name: "ClipboardVocab",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "ClipboardVocab",
            exclude: [
                "App/Info.plist",
                "App/ClipboardVocab.entitlements"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ClipboardVocabTests",
            dependencies: [
                .target(name: "ClipboardVocab"),
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Tests"
        )
    ]
)
