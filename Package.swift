// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "updater",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/leviouwendijk/plate.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Interfaces.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Executable.git", branch: "master"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "updater",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "plate", package: "plate"),
                .product(name: "Interfaces", package: "Interfaces"),
                .product(name: "Executable", package: "Executable"),
            ],
            exclude: [
                "main.swift.bak"
            ],
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
