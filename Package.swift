// swift-tools-version: 5.9
// License: MIT
import PackageDescription

let package = Package(
    name: "CrabKit",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS(.v17)],
    products: [
        // 小螃蟹本体：像素帧、动画、会溜达会被戳的那只、灵动岛数据
        .library(name: "CrabKit", targets: ["CrabKit"]),
        // 放进你自己的小组件扩展里用：灵动岛 / 锁屏 / 桌面小组件的样子
        .library(name: "CrabKitWidgets", targets: ["CrabKitWidgets"]),
    ],
    targets: [
        .target(name: "CrabKit", path: "Sources/CrabKit"),
        .target(name: "CrabKitWidgets", dependencies: ["CrabKit"], path: "Sources/CrabKitWidgets"),
    ]
)
