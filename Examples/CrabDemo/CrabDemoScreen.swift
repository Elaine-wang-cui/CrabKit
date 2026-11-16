import CrabChat
import CrabKit
import SwiftUI

/// 演示界面：一页是聊天，一页是螃蟹自己。没有账号，也没有网络。
public struct CrabDemoScreen: View {
    public init() {}

    public var body: some View {
        TabView {
            ChatPlayground()
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
            CrabPlayground()
                .tabItem { Label("Crab", systemImage: "circle.grid.2x2") }
        }
    }
}
