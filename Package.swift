// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SkillRetrieval",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SkillRetrieval", targets: ["SkillRetrieval"])
    ],
    targets: [
        .target(name: "SkillRetrieval"),
        .testTarget(name: "SkillRetrievalTests", dependencies: ["SkillRetrieval"])
    ]
)
