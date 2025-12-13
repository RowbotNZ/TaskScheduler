// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TaskScheduler",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "TaskScheduler",
            targets: ["TaskScheduler"]
        ),
        .library(
            name: "ViewModelTaskScheduler",
            targets: ["ViewModelTaskScheduler"]
        )
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "TaskScheduler"
        ),
        .target(
            name: "ViewModelTaskScheduler",
            dependencies: ["TaskScheduler"]
        ),
        .testTarget(
            name: "TaskSchedulerTests",
            dependencies: ["TaskScheduler"]
        ),
        .testTarget(
            name: "ViewModelTaskSchedulerTests",
            dependencies: ["ViewModelTaskScheduler"]
        )
    ]
)
