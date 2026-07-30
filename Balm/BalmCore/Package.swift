// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BalmCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "BalmModels", targets: ["BalmModels"]),
        .library(name: "BalmAPI", targets: ["BalmAPI"]),
        .library(name: "BalmAuth", targets: ["BalmAuth"]),
        .library(name: "BalmADF", targets: ["BalmADF"]),
        .library(name: "BalmPersistence", targets: ["BalmPersistence"]),
        .library(name: "BalmDesignSystem", targets: ["BalmDesignSystem"]),
        .library(name: "BalmFeatures", targets: ["BalmFeatures"])
    ],
    targets: [
        .target(
            name: "BalmModels",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "BalmAuth",
            dependencies: ["BalmModels"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "BalmAPI",
            dependencies: ["BalmModels", "BalmAuth"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "BalmADF",
            dependencies: ["BalmModels"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "BalmPersistence",
            dependencies: ["BalmModels", "BalmADF"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "BalmDesignSystem",
            dependencies: [],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "BalmFeatures",
            dependencies: [
                "BalmModels",
                "BalmAPI",
                "BalmAuth",
                "BalmADF",
                "BalmPersistence",
                "BalmDesignSystem"
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "BalmModelsTests",
            dependencies: ["BalmModels"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "BalmAPITests",
            dependencies: ["BalmAPI"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "BalmAuthTests",
            dependencies: ["BalmAuth"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "BalmADFTests",
            dependencies: ["BalmADF"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "BalmFeaturesTests",
            dependencies: ["BalmFeatures"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
