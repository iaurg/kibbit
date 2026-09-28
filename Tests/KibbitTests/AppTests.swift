import AppKit
import Testing
@testable import Kibbit

@Suite("Markdown rendering")
struct MarkdownTests {
    typealias Block = MarkdownBlocks.Block

    @Test func proseOnly() {
        #expect(MarkdownBlocks.parse("Just an answer.") == [.prose("Just an answer.")])
        #expect(MarkdownBlocks.parse("").isEmpty)
    }

    @Test func fencedCodeWithLanguage() {
        let text = """
        Run this:
        ```bash
        lsof -i :3000
        kill -9 1234
        ```
        Done.
        """
        #expect(MarkdownBlocks.parse(text) == [
            .prose("Run this:"),
            .code(lang: "bash", body: "lsof -i :3000\nkill -9 1234"),
            .prose("Done."),
        ])
    }

    @Test func fenceWithoutLanguage() {
        #expect(MarkdownBlocks.parse("```\nls\n```") == [.code(lang: "", body: "ls")])
    }

    /// While streaming, the closing fence hasn't arrived yet; the partial code must still render as code.
    @Test func unterminatedFenceIsCode() {
        #expect(MarkdownBlocks.parse("Try:\n```swift\nlet x = 1") == [.prose("Try:"), .code(lang: "swift", body: "let x = 1")])
    }

    @Test func inlineMarkdown() {
        #expect(String(MarkdownBlocks.inline("# Title").characters) == "Title")
        #expect(String(MarkdownBlocks.inline("- one\n  * two").characters) == "• one\n  • two")
        #expect(String(MarkdownBlocks.inline("use **git** `reset`").characters) == "use git reset")
        #expect(String(MarkdownBlocks.inline("#hashtag stays").characters) == "#hashtag stays")
    }
}

@Suite("Settings", .serialized)
@MainActor
struct SettingsTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "kibbit-tests-\(UUID().uuidString)")!
    }

    @Test func firstLaunchHatchesAPersistentSeed() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        let second = AppSettings(defaults: defaults)
        #expect(first.seed == second.seed)
        #expect(first.seed <= UInt64(UInt32.max))
        #expect(first.pet == .cat)
        #expect(first.model == .haiku)
    }

    @Test func choicesPersist() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.pet = .axolotl
        settings.seed = 0xDA6B_2B9B
        settings.model = .sonnet
        settings.hotKeyID = "cmd-opt-k"
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.pet == .axolotl)
        #expect(reloaded.seed == 0xDA6B_2B9B)
        #expect(reloaded.model == .sonnet)
        #expect(reloaded.hotKey.label == "⌘⌥ K")
        #expect(reloaded.palette == PetPalette(seed: 0xDA6B_2B9B, pet: .axolotl))
    }

    @Test func corruptValuesFallBack() {
        let defaults = freshDefaults()
        defaults.set("dragon", forKey: "pet")
        defaults.set("gpt", forKey: "model")
        defaults.set("not-a-number", forKey: "seed")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.pet == .cat)
        #expect(settings.model == .haiku)
        #expect(settings.seed <= UInt64(UInt32.max))
    }

    @Test func hotKeyPresets() {
        #expect(Set(HotKeyPreset.all.map(\.id)).count == HotKeyPreset.all.count)
        #expect(HotKeyPreset.find("bogus") == HotKeyPreset.all[0])
        #expect(HotKeyPreset.find("none").modifiers == 0)
    }
}

@Suite("Pet animation")
@MainActor
struct PetAnimatorTests {
    @Test func moodsDriveFrames() {
        let animator = PetAnimator()
        animator.mood = .thinking
        guard case .dots = animator.frame.overlay else { Issue.record("thinking shows dots"); return }
        animator.mood = .happy
        #expect(animator.frame.overlay == .heart)
        animator.mood = .error
        #expect(animator.frame.overlay == .bang)
        animator.mood = .sleeping
        #expect(animator.frame.eyesClosed)
        guard case .zzz = animator.frame.overlay else { Issue.record("sleeping shows Z"); return }
    }

    @Test func pokeWakesTheSleeper() {
        let animator = PetAnimator()
        animator.mood = .sleeping
        animator.poke()
        #expect(animator.mood == .idle)
    }
}

/// End-to-end: the chat view model talking to the fake CLI.
@Suite("Chat", .serialized)
@MainActor
final class ChatStoreTests {
    private let workspace = Fixtures.tempDirectory()
    private let store: ChatStore

    init() {
        let defaults = UserDefaults(suiteName: "kibbit-tests-\(UUID().uuidString)")!
        defaults.set(Fixtures.fakeClaude, forKey: "claudePath")
        store = ChatStore(settings: AppSettings(defaults: defaults), animator: PetAnimator(), workspace: workspace)
    }

    deinit {
        try? FileManager.default.removeItem(at: workspace)
    }

    @Test func findsConfiguredCLI() {
        #expect(store.claudeStatus.hasPrefix("Found"))
    }

    @Test func askAndAnswer() async throws {
        store.input = "  hello  "
        store.send()
        #expect(store.busy)
        #expect(store.input.isEmpty)
        #expect(store.messages.map(\.role) == [.user, .assistant])
        #expect(store.messages[0].text == "hello")

        try await waitUntil("answer") { !store.busy }
        #expect(store.messages[1].text == "Hello, world")
        #expect(store.messages[1].error == nil)
        #expect(store.usage == 0.25)
        #expect(store.animator.mood == .happy)
    }

    @Test func blankInputIsIgnored() {
        store.input = "   \n "
        store.send()
        #expect(store.messages.isEmpty)
        #expect(!store.busy)
    }

    @Test func errorsShowOnTheAnswer() async throws {
        store.input = "fail"
        store.send()
        try await waitUntil("error") { !store.busy }
        #expect(store.messages[1].error == "Not logged in · Please run /login")
        #expect(store.animator.mood == .error)
    }

    @Test func stopMarksAnswerStopped() async throws {
        store.input = "slow"
        store.send()
        try await waitUntil("partial answer") { store.messages.last?.text == "Working" }
        store.stop()
        try await waitUntil("stop") { !store.busy }
        #expect(store.messages[1].stopped)
        #expect(store.messages[1].text == "Working")
    }

    @Test func newChatClears() async throws {
        store.input = "hello"
        store.send()
        try await waitUntil("answer") { !store.busy }
        store.newChat()
        #expect(store.messages.isEmpty)
        #expect(!store.busy)
    }
}
