// swift-tools-version: 6.2
import PackageDescription

let package = Package(
	name: "ATShare",
	platforms: [.macOS(.v15), .iOS(.v18)],
	products: [
		.library(
			name: "ATShare",
			targets: ["ATShare"]
		)
	],
	targets: [
		.target(
			name: "ATShare",
			swiftSettings: [
				.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
				.enableUpcomingFeature("InferIsolatedConformances")
			]
		),
		.testTarget(
			name: "ATShareTests",
			dependencies: ["ATShare"]
		)
	]
)
