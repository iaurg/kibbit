import AppKit

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }

    let id = UUID()
    let role: Role
    var text: String
    var context: String?
    var error: String?
    var stopped = false
}

@MainActor
final class ChatStore: ObservableObject {
    enum Page { case chat, settings }

    @Published var messages: [ChatMessage] = []
    @Published var input = ""
    /// Clipboard text snapshotted when the user attaches it; read only on demand.
    @Published var attachment: String?
    @Published private(set) var busy = false
    @Published private(set) var usage: Double?
    @Published var page: Page = .chat
    @Published var focusTick = 0
    @Published private(set) var claudeStatus = "Looking for claude…"

    let settings: AppSettings
    let animator: PetAnimator
    private let session: ClaudeSession
    private var binary: String?

    init(settings: AppSettings, animator: PetAnimator) {
        self.settings = settings
        self.animator = animator
        session = ClaudeSession(config: .init(binary: "", model: settings.model.rawValue, token: settings.token))
        session.onEvent = { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        relocateClaude()
    }

    func toggleClipboard() {
        if attachment != nil {
            attachment = nil
            return
        }
        let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if clip.isEmpty { NSSound.beep() } else { attachment = String(clip.prefix(20_000)) }
    }

    func relocateClaude() {
        binary = ClaudeSession.locateBinary(override: settings.claudePath)
        claudeStatus = binary.map { "Found \($0.replacingOccurrences(of: NSHomeDirectory(), with: "~"))" }
            ?? "claude CLI not found"
        applyConfig()
    }

    func applyConfig() {
        session.update(config: .init(binary: binary ?? "", model: settings.model.rawValue, token: settings.token))
    }

    /// Called when the panel opens: have a process ready before the user finishes typing.
    func prepare() {
        animator.poke()
        session.warm()
        focusTick += 1
    }

    func send() {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !busy else { return }
        let context = attachment
        var prompt = question
        if let context {
            prompt = "Context (from my clipboard):\n```\n\(context)\n```\n\n\(question)"
        }
        messages.append(ChatMessage(role: .user, text: question, context: context))
        messages.append(ChatMessage(role: .assistant, text: ""))
        input = ""
        attachment = nil
        busy = true
        animator.mood = .thinking
        session.send(prompt)
    }

    func stop() { session.stop() }

    func newChat() {
        if busy { session.terminate() }
        messages.removeAll()
        busy = false
        animator.mood = .idle
        session.reset()
        focusTick += 1
    }

    func copyLastAnswer() {
        guard let last = messages.last(where: { $0.role == .assistant && !$0.text.isEmpty }) else { return }
        copy(last.text)
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func handle(_ event: ClaudeSession.Event) {
        switch event {
        case .delta(let text):
            guard busy, let i = messages.indices.last else { return }
            messages[i].text += text
            if animator.mood != .talking { animator.mood = .talking }

        case .finished(let text, let error, let stopped):
            guard busy, let i = messages.indices.last else { return }
            busy = false
            if let text, !text.isEmpty { messages[i].text = text }
            messages[i].stopped = stopped
            if let error {
                messages[i].error = error
                animator.mood = .error
            } else {
                animator.mood = stopped ? .idle : .happy
            }

        case .usage(let fiveHour):
            usage = fiveHour
        }
    }
}
