import SwiftUI

/// The chat page with an in-memory session and a local reply.
/// Drop this into a SwiftUI app. It does not read a store or open a connection.
public struct ChatPlayground: View {
    @State private var session = ChatSession()
    @State private var chrome = ChatChrome()

    public init() {}

    public var body: some View {
        ChatView(session: session, onMenu: {}, onSettings: {})
            .environment(chrome)
    }
}
