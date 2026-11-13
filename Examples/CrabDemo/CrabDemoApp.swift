import CrabKit
import SwiftUI

/// 最小演示 app：新建一个 iOS App 工程，把这个文件替换掉自动生成的 App 文件，
/// 再把本仓库作为本地 Swift Package 加进去（File → Add Package Dependencies… → Add Local…）。
@main
struct CrabDemoApp: App {
    var body: some Scene {
        WindowGroup {
            CrabPlayground()
        }
    }
}
