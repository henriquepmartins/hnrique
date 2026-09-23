// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Henrique",
  platforms: [.iOS(.v26), .macOS(.v26)],
  products: [
    .library(name: "HenriqueCore", targets: ["HenriqueCore"]),
    .library(name: "HenriqueUI", targets: ["HenriqueUI"]),
  ],
  targets: [
    .target(name: "HenriqueCore"),
    .target(
      name: "HenriqueUI", dependencies: ["HenriqueCore"],
      resources: [.copy("Resources/AnthropicSerif.ttf")]),
    .testTarget(
      name: "HenriqueCoreTests", dependencies: ["HenriqueCore"],
      resources: [.copy("Fixtures")]),
    .testTarget(name: "HenriqueUITests", dependencies: ["HenriqueUI"]),
  ]
)
