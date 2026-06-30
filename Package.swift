// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SideDrawer",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "SideDrawer",
            targets: ["SideDrawer"]
        )
    ],
    targets: [
        .target(
            name: "SideDrawer"
        )
    ]
)
