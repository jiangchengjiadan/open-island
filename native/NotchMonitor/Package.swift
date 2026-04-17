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
        .executableTarget(
            name: "NotchMonitor",
            dependencies: [],
            path: "Sources",
            exclude: [
                "AppRuntime"
            ],
            sources: ["."],
            resources: [
                .copy("AppRuntime/bridge"),
                .copy("AppRuntime/scripts")
            ]
        )
    ]
)
