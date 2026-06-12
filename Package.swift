// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Anchor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Anchor", targets: ["Anchor"])
    ],
    targets: [
        .executableTarget(
            name: "Anchor",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon")
            ]
        ),
        .testTarget(
            name: "AnchorTests",
            dependencies: ["Anchor"],
            linkerSettings: [
                .linkedFramework("ApplicationServices")
            ]
        )
    ]
)
