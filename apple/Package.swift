// swift-tools-version: 6.1
// This is a Skip (https://skip.dev) package.
import PackageDescription

let package = Package(
    name: "apple",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "CLIFlashcards", type: .dynamic, targets: ["CLIFlashcards"]),
    ],
    dependencies: [
        .package(url: "https://github.com/skiptools/skip.git", from: "1.9.21"),
        .package(url: "https://github.com/skiptools/skip-fuse-ui.git", from: "1.0.0"),
        // The Android document picker, for importing backups.
        .package(url: "https://github.com/skiptools/skip-kit.git", from: "1.1.7"),
        // Scheduling, cards, answers and storage, with no UI. A separate plain
        // Swift package, so its tests run anywhere (`swift test` in FlashcardsCore/).
        .package(path: "FlashcardsCore"),
    ],
    targets: [
        .target(name: "CLIFlashcards", dependencies: [
            .product(name: "FlashcardsCore", package: "FlashcardsCore"),
            .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
            .product(name: "SkipKit", package: "skip-kit", condition: .when(platforms: [.android])),
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)
