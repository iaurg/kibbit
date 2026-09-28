import SwiftUI

struct RootView: View {
    static let size = NSSize(width: 386, height: 526)

    @ObservedObject var store: ChatStore
    var close: () -> Void

    var body: some View {
        Group {
            switch store.page {
            case .chat: ChatView(store: store, settings: store.settings, close: close)
            case .settings: SettingsView(store: store, settings: store.settings)
            case .onboarding: OnboardingView(store: store, onboarding: store.onboarding, settings: store.settings)
            }
        }
        .frame(width: 380, height: 520)
        .background(Theme.background)
        .clipShape(PixelBox(notch: 3))
        .padding(3)
        .background(PixelBox(notch: 6).fill(store.settings.palette.body.color))
        .onExitCommand {
            if store.page == .settings { store.page = .chat } else { close() }
        }
    }
}

struct ChatView: View {
    @ObservedObject var store: ChatStore
    @ObservedObject var settings: AppSettings
    var close: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ChatHeader(store: store, settings: settings, animator: store.animator)
            PixelRule()
            messages
            PixelRule()
            inputBar
        }
        .onChange(of: store.focusTick) { focused = true }
        .onAppear { focused = true }
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if store.messages.isEmpty {
                    EmptyState(hotKey: settings.hotKey.label)
                        .padding(.top, 70)
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(store.messages) { message in
                            MessageRow(message: message, busy: store.busy && message.id == store.messages.last?.id,
                                       palette: settings.palette, copy: store.copy)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(12)
                }
            }
            .scrollIndicators(.never)
            .onChange(of: store.messages) { proxy.scrollTo("bottom", anchor: .bottom) }
        }
        .frame(maxHeight: .infinity)
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let clip = store.attachment {
                HStack(spacing: 6) {
                    PixelText(icon: PixelFont.Icon.clip, pixel: 1.5, color: settings.palette.accent.color)
                    Text(clip.replacingOccurrences(of: "\n", with: " ⏎ "))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Button { store.attachment = nil } label: {
                        PixelText(icon: PixelFont.Icon.close, pixel: 1.5, color: Theme.muted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .pixelPanel(fill: Theme.code, shadow: false)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button(action: store.toggleClipboard) {
                    PixelText(icon: PixelFont.Icon.clip, color: store.attachment != nil ? settings.palette.accent.color : Theme.muted)
                }
                .buttonStyle(PixelButtonStyle(fill: Theme.panel))
                .help("Attach clipboard as context (⌘⇧V)")
                .keyboardShortcut("v", modifiers: [.command, .shift])

                TextField("Ask anything…", text: $store.input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1...6)
                    .focused($focused)
                    .onSubmit { store.send() }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .pixelPanel(fill: Theme.code, border: focused ? settings.palette.body.color : Theme.border, shadow: false)

                if store.busy {
                    Button(action: store.stop) { PixelText(icon: PixelFont.Icon.stop, color: Theme.danger) }
                        .buttonStyle(PixelButtonStyle())
                        .help("Stop (⌘.)")
                        .keyboardShortcut(".", modifiers: .command)
                } else {
                    Button(action: store.send) { PixelText(icon: PixelFont.Icon.send, color: settings.palette.body.color) }
                        .buttonStyle(PixelButtonStyle())
                        .help("Send (↩)")
                        .disabled(store.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(10)
        .background(Theme.panel)
    }
}

private struct ChatHeader: View {
    @ObservedObject var store: ChatStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var animator: PetAnimator

    var body: some View {
        HStack(spacing: 10) {
            PetSpriteView(pet: settings.pet, palette: settings.palette, frame: animator.frame, pixel: 2.5)
            VStack(alignment: .leading, spacing: 6) {
                PixelText(settings.pet.displayName, pixel: 2, color: settings.palette.body.color)
                PixelText(status, pixel: 1.5, color: Theme.muted)
                if let usage = store.usage { EnergyBar(remaining: 1 - usage, color: settings.palette.body.color) }
            }
            Spacer()
            Button(action: store.newChat) { PixelText(icon: PixelFont.Icon.plus) }
                .buttonStyle(PixelButtonStyle())
                .help("New chat (⌘N)")
                .keyboardShortcut("n", modifiers: .command)
            Button { store.page = .settings } label: { PixelText(icon: PixelFont.Icon.gear) }
                .buttonStyle(PixelButtonStyle())
                .help("Settings (⌘,)")
                .keyboardShortcut(",", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.panel)
    }

    private var status: String {
        let model = settings.model.label
        return switch animator.mood {
        case .thinking: "\(model) · THINKING"
        case .talking: "\(model) · TYPING"
        case .sleeping: "\(model) · ZZZ"
        case .error: "\(model) · OOPS"
        default: "\(model) · READY"
        }
    }
}

/// Remaining share of the 5-hour subscription window, as a pixel health bar.
private struct EnergyBar: View {
    let remaining: Double
    let color: Color

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<10, id: \.self) { i in
                Rectangle()
                    .fill(Double(i) < (remaining * 10).rounded(.up) ? color : Theme.border)
                    .frame(width: 5, height: 4)
            }
        }
        .padding(2)
        .background(Theme.border)
        .help("5-hour usage: \(Int(((1 - remaining) * 100).rounded()))%")
    }
}

private struct PixelRule: View {
    var body: some View {
        Rectangle().fill(Theme.border).frame(height: 2)
    }
}

private struct EmptyState: View {
    let hotKey: String

    var body: some View {
        VStack(spacing: 14) {
            PixelText("ASK ME ANYTHING", pixel: 2.5, color: Theme.text)
            VStack(spacing: 6) {
                hint("↩", "send")
                hint("⌘⇧V", "attach clipboard")
                hint("⌘N", "new chat")
                hint("esc", "back to work")
                if hotKey != "Off" { hint(hotKey, "summon from anywhere") }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.text)
                .frame(width: 80, alignment: .trailing)
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .frame(width: 150, alignment: .leading)
        }
    }
}

struct MessageRow: View {
    let message: ChatMessage
    let busy: Bool
    let palette: PetPalette
    let copy: (String) -> Void

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                VStack(alignment: .trailing, spacing: 4) {
                    if message.context != nil {
                        HStack(spacing: 4) {
                            PixelText(icon: PixelFont.Icon.clip, pixel: 1.5, color: palette.accent.color)
                            PixelText("CLIPBOARD", pixel: 1.5, color: Theme.muted)
                        }
                    }
                    Text(message.text)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .pixelPanel(fill: Theme.panelHi, border: palette.body.color, shadow: false)
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                if message.text.isEmpty, busy {
                    ThinkingLabel(color: palette.body.color)
                } else if !message.text.isEmpty {
                    MarkdownBlocks(text: message.text, copy: copy)
                }
                if let error = message.error {
                    Text(error)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.danger)
                        .textSelection(.enabled)
                }
                if message.stopped {
                    PixelText("STOPPED", pixel: 1.5, color: Theme.muted)
                }
                if !busy, !message.text.isEmpty {
                    CopyButton { copy(message.text) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ThinkingLabel: View {
    let color: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.3)) { context in
            let n = Int(context.date.timeIntervalSinceReferenceDate / 0.3) % 4
            PixelText("THINKING" + String(repeating: ".", count: n), pixel: 2, color: color)
        }
    }
}

struct CopyButton: View {
    var label = "COPY"
    let action: () -> Void
    @State private var copied = false

    var body: some View {
        Button {
            action()
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
            HStack(spacing: 4) {
                PixelText(icon: copied ? PixelFont.Icon.check : PixelFont.Icon.copy, pixel: 1.5, color: copied ? Theme.good : Theme.muted)
                PixelText(copied ? "COPIED" : label, pixel: 1.5, color: copied ? Theme.good : Theme.muted)
            }
            .padding(2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Splits an answer into prose and fenced code blocks; prose gets inline markdown only,
/// which keeps rendering instant while text is still streaming in.
struct MarkdownBlocks: View {
    let text: String
    let copy: (String) -> Void

    enum Block: Hashable {
        case prose(String)
        case code(lang: String, body: String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.parse(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .prose(let s):
                    Text(Self.inline(s))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                        .tint(Theme.good)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        // Answers can be steered by pasted content; only let links open web pages,
                        // never file:// or custom app schemes.
                        .environment(\.openURL, OpenURLAction { url in
                            ["http", "https"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded
                        })
                case .code(let lang, let body):
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            PixelText(lang.isEmpty ? "CODE" : lang, pixel: 1.5, color: Theme.muted)
                            Spacer()
                            CopyButton { copy(body) }
                        }
                        ScrollView(.horizontal) {
                            Text(body)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Theme.text)
                                .textSelection(.enabled)
                                .fixedSize()
                        }
                        .scrollIndicators(.never)
                    }
                    .padding(8)
                    .pixelPanel(fill: Theme.code, shadow: false)
                }
            }
        }
    }

    static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var prose: [Substring] = []
        var code: [Substring] = []
        var lang: String?
        func flushProse() {
            let s = prose.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !s.isEmpty { blocks.append(.prose(s)) }
            prose.removeAll()
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let l = lang {
                    blocks.append(.code(lang: l, body: code.joined(separator: "\n")))
                    code.removeAll()
                    lang = nil
                } else {
                    flushProse()
                    lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
            } else if lang != nil {
                code.append(line)
            } else {
                prose.append(line)
            }
        }
        // An unterminated fence is just a code block still streaming in.
        if let l = lang { blocks.append(.code(lang: l, body: code.joined(separator: "\n"))) }
        flushProse()
        return blocks
    }

    static func inline(_ s: String) -> AttributedString {
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var line = String(line)
            if let hashes = line.firstIndex(where: { $0 != "#" }), line.hasPrefix("#"), line[hashes] == " " {
                line = "**" + line[line.index(after: hashes)...] + "**"
            }
            for bullet in ["- ", "* "] where line.trimmingCharacters(in: .whitespaces).hasPrefix(bullet) {
                let indent = line.prefix { $0 == " " }
                line = indent + "• " + line.dropFirst(indent.count + 2)
            }
            return line
        }
        let joined = lines.joined(separator: "\n")
        return (try? AttributedString(markdown: joined, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(joined)
    }
}
