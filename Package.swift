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
        // 聊天页、输入框、发送气泡的飞行。只有界面和内存里的假回复。
        .library(name: "CrabChat", targets: ["CrabChat"]),
        // 把聊天页和螃蟹预览放在一起的演示界面，给一个 iOS App 工程引用。
        .library(name: "CrabDemo", targets: ["CrabDemo"]),
    ],
    targets: [
        .target(name: "CrabKit", path: "Sources/CrabKit"),
        .target(name: "CrabKitWidgets", dependencies: ["CrabKit"], path: "Sources/CrabKitWidgets"),
        .target(name: "CrabChat", dependencies: ["CrabKit"], path: "Sources/CrabChat"),
        .target(
            name: "CrabDemo",
            dependencies: ["CrabKit", "CrabChat"],
            path: "Examples/CrabDemo",
            exclude: ["CrabDemoApp.swift", "CrabDemoWidgets.swift"]
        ),
    ]
)
