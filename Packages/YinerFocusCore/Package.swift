// swift-tools-version: 5.9
import PackageDescription

// 纯逻辑库，只依赖 Foundation，便于在 Linux 上跑验收测试。
// 菜单栏、Apple Events、EventKit 等 macOS 部分在 App 工程里，最低系统是 macOS 26。
let package = Package(
    name: "YinerFocusCore",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .library(name: "YinerFocusCore", targets: ["YinerFocusCore"])
    ],
    targets: [
        .target(
            name: "YinerFocusCore",
            path: "Sources/YinerFocusCore"
        ),
        .testTarget(
            name: "YinerFocusCoreTests",
            dependencies: ["YinerFocusCore"],
            path: "Tests/YinerFocusCoreTests"
        )
    ]
)
