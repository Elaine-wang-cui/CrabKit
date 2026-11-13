import SwiftUI

/// 演示页：一只会溜达的小螃蟹趴在一个假的输入框上，配一排按钮试各种动作。
/// 不连任何网络，全部用 MockReplyEngine 假装。
public struct CrabPlayground: View {
    @State private var engine = MockReplyEngine()
    @State private var roams = true
    @State private var blushing = false
    @State private var draft = ""
    @State private var note: String?

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(TimeOfDay.now.greeting)
                        .font(.system(size: 28, design: .serif))
                        .foregroundStyle(CrabTheme.textPrimary)
                    Text("点它、连戳三下、长按拎起来、往下一划拍扁、在下面打字或删字，都试试。")
                        .font(.footnote)
                        .foregroundStyle(CrabTheme.textSecondary)

                    controls

                    if !engine.text.isEmpty || engine.state != .idle {
                        VStack(alignment: .leading, spacing: 8) {
                            if !engine.text.isEmpty {
                                Text(engine.text)
                                    .foregroundStyle(CrabTheme.textPrimary)
                            }
                            if engine.state != .idle {
                                WorkingCrab(state: engine.state, bubbles: true)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CrabTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    if let note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(CrabTheme.textSecondary)
                    }
                }
                .padding(20)
            }
            .background {
                GeometryReader { g in
                    Color.clear
                        .onAppear { CrabStage.shared.area = g.frame(in: .global) }
                        .onChange(of: g.frame(in: .global)) { _, f in CrabStage.shared.area = f }
                }
            }

            // 小螃蟹趴在输入框上沿
            RoamingCrab(working: engine.state, roams: roams, pixel: 2,
                        typing: draft.count, cue: engine.cue, blushing: blushing)
            composer
        }
        .background(CrabTheme.background)
        .environment(\.crabStyle, .heart)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("闲着时到处爬", isOn: $roams)
            Toggle("脸红", isOn: $blushing)
            Toggle("同时用灵动岛（需要小组件扩展）", isOn: $engine.useIsland)
            HStack {
                Button("假装回复") { engine.send() }
                Button("翻资料再回复") { engine.send(withTool: true) }
                Button("停") { engine.stop() }
            }
            HStack {
                Button("冒爱心") { engine.fire(.heart) }
                Button("抱花跑") { engine.fire(.flower) }
                Button("举牌") { engine.fire(.sign("你好呀，我是小螃蟹")) }
            }
            HStack {
                ForEach(CrabCue.reactions, id: \.self) { e in
                    Button(e) { engine.fire(.reaction(e)) }
                }
            }
            Button("看看刚才对它做了什么") { note = CrabLog.shared.takeNote() ?? "还什么都没做" }
        }
        .buttonStyle(.bordered)
        .tint(CrabTheme.accent)
    }

    private var composer: some View {
        HStack {
            TextField("随便打点字…", text: $draft)
                .textFieldStyle(.plain)
            Button("发送") {
                let text = draft
                draft = ""
                engine.send(reply: text.isEmpty ? nil : "你说的是：" + text)
            }
        }
        .padding(14)
        .background(CrabTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(CrabTheme.accent, lineWidth: 1))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

#Preview {
    CrabPlayground()
}
