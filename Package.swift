// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Kibbit",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Kibbit", path: "Sources/Kibbit"),
        .testTarget(name: "KibbitTests", dependencies: ["Kibbit"], path: "Tests/KibbitTests",
                    exclude: ["Fixtures"]),
    ]
)
