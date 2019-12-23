// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ElasticLog",
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "ElasticLog",
            targets: ["ElasticLog"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", .upToNextMajor(from: "1.2.0")),
        .package(url: "https://github.com/apple/swift-nio.git", .upToNextMajor(from: "2.12.0")),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", .upToNextMajor(from: "2.5.0")),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "ElasticLog",
            dependencies: ["Logging", "NIO", "NIOConcurrencyHelpers", "NIOSSL"]),
        .testTarget(
            name: "ElasticLogTests",
            dependencies: ["ElasticLog"]),
    ]
)
