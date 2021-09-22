// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.
import PackageDescription

let package = Package(
    name: "RZImport",
    platforms: [
        .iOS(.v9),
        .macOS(.v10_10),
    ],
    products: [
        .library(
            name: "RZImport",
            targets: ["RZImport"]),
    ],
    targets: [
        .target(
            name: "RZImport",
            path: "Classes",
            publicHeadersPath: "Classes"),
    ]
)
