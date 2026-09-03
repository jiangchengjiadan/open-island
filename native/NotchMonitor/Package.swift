// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchMonitor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "NotchMonitor", targets: ["NotchMonitor"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "OpenIslandCore",
            path: "Sources/OpenIslandCore"
        ),
        .executableTarget(
            name: "NotchMonitor",
            dependencies: ["OpenIslandCore"],
            path: "Sources",
            exclude: [
                "AppRuntime",
                "OpenIslandCore"
            ],
            sources: ["."],
            resources: [
                .copy("AppRuntime/bridge"),
                .copy("AppRuntime/scripts"),
                .copy("AppRuntime/runtime-manifest.json")
            ]
        ),
        .testTarget(
            name: "OpenIslandCoreTests",
            dependencies: ["OpenIslandCore"],
            path: "Tests/OpenIslandCoreTests"
        )
    ]
)
