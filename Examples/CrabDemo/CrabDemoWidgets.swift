import CrabKit
import CrabKitWidgets
import SwiftUI
import WidgetKit

/// 可选：小组件扩展（Widget Extension）里的入口。
/// 新建 Widget Extension target，把这个文件放进去，target 依赖 CrabKitWidgets。
/// app 和扩展都打开同一个 App Group，并在启动时设置 CrabSnapshot.appGroup。
@main
struct CrabDemoWidgets: WidgetBundle {
    var body: some Widget {
        CrabLiveActivity()
        CrabHomeWidget()
    }
}
