import Foundation
import Testing
@testable import Kibbit

/// Drives the real process plumbing against Fixtures/fake-claude, so CI needs no Claude login.
@Suite("Claude session (fake CLI)")
@MainActor
final class ClaudeSessionTests {
    private let workspace = Fixtures.tempDirectory()
    private var events: [ClaudeSession.Event] = []
    private var session: ClaudeSession!

    init() {
        session = makeSession()
    }

    deinit {
        // Dropping the session terminates its process.
        try? FileManager.default.removeItem(at: workspace)
    }

    private func makeSession(binary: String = Fixtures.fakeClaude, model: String = "haiku", token: String = "") -> ClaudeSession {
        let s = ClaudeSession(config: .init(binary: binary, model: model, token: token), workspace: workspace)
        s.onEvent = { [unowned self] in events.append($0) }
        return s
    }

    private var finished: [ClaudeSession.Event] {
        events.filter { if case .finished = $0 { true } else { false } }
    }

    private var launchArgs: [String] { lines(of: workspace.appendingPathComponent("launch-args.txt")) }
    /// Parsed into a dictionary so a failing expectation prints one value, never the whole
    /// environment (which in CI can hold runner credentials).
    private var launchEnv: [String: String] {
        var env: [String: String] = [:]
        for line in lines(of: workspace.appendingPathComponent("launch-env.txt")) {
            guard let eq = line.firstIndex(of: "=") else { continue }
            env[String(line[..<eq])] = String(line[line.index(after: eq)...])
        }
        return env
    }

    @Test func streamsAnAnswer() async throws {
        session.send("hello")
        try await waitUntil("answer") { finished.count == 1 }
        #expect(events == [
            .delta("Hello"),
            .delta(", world"),
            .usage(fiveHour: 0.25),
            .finished(text: "Hello, world", error: nil, stopped: false),
        ])
    }

    @Test func launchesWithoutToolsMemoryOrAPIKey() async throws {
        setenv("ANTHROPIC_API_KEY", "sk-ant-should-not-leak", 1)
        defer { unsetenv("ANTHROPIC_API_KEY") }
        session.warm()
        try await waitUntil("launch record") { !launchEnv.isEmpty }

        #expect(launchArgs.value(after: "--model") == "haiku")
        #expect(launchArgs.value(after: "--tools") == "")
        #expect(launchArgs.value(after: "--setting-sources") == "")
        #expect(launchArgs.value(after: "--input-format") == "stream-json")
        #expect(launchArgs.value(after: "--output-format") == "stream-json")
        #expect(launchArgs.contains("--strict-mcp-config"))
        #expect(!launchArgs.contains("--resume"))

        #expect(launchEnv["ANTHROPIC_API_KEY"] == nil)
        #expect(launchEnv["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] == "1")
        #expect(launchEnv["CLAUDE_CODE_DISABLE_CLAUDE_MDS"] == "1")
        #expect(launchEnv["CLAUDE_CODE_OAUTH_TOKEN"] == nil)
    }

    @Test func passesTokenFromSettings() async throws {
        session = makeSession(token: "sk-ant-oat-test")
        session.warm()
        try await waitUntil("launch record") { !launchEnv.isEmpty }
        #expect(launchEnv["CLAUDE_CODE_OAUTH_TOKEN"] == "sk-ant-oat-test")
    }

    @Test func stopInterruptsTheTurn() async throws {
        session.send("slow please")
        try await waitUntil("first delta") { events.contains(.delta("Working")) }
        session.stop()
        try await waitUntil("stop") { finished.count == 1 }
        #expect(finished == [.finished(text: nil, error: nil, stopped: true)])
    }

    @Test func surfacesErrorResults() async throws {
        session.send("fail")
        try await waitUntil("error") { finished.count == 1 }
        #expect(finished == [.finished(text: nil, error: "Not logged in · Please run /login", stopped: false)])
    }

    @Test func crashReportsStderr() async throws {
        session.send("crash")
        try await waitUntil("crash") { finished.count == 1 }
        guard case .finished(nil, let error?, false) = finished[0] else {
            Issue.record("unexpected \(finished)")
            return
        }
        #expect(error.contains("simulated failure"))
        #expect(!session.isRunning)
    }

    @Test func recoversAfterCrash() async throws {
        session.send("crash")
        try await waitUntil("crash") { finished.count == 1 }
        session.send("hello again")
        try await waitUntil("answer") { finished.count == 2 }
        #expect(finished.last == .finished(text: "Hello, world", error: nil, stopped: false))
    }

    @Test func resumesConversationAfterIdleShutdown() async throws {
        session.send("hello")
        try await waitUntil("first answer") { finished.count == 1 }
        session.terminate()
        session.send("and again")
        try await waitUntil("second answer") { finished.count == 2 }
        #expect(launchArgs.value(after: "--resume") == "fake-session-1")
    }

    @Test func resetStartsFresh() async throws {
        session.send("hello")
        try await waitUntil("answer") { finished.count == 1 }
        try FileManager.default.removeItem(at: workspace.appendingPathComponent("launch-args.txt"))
        session.reset()
        try await waitUntil("relaunch") { launchArgs.count > 1 }
        #expect(!launchArgs.contains("--resume"))
    }

    @Test func modelChangeRespawns() async throws {
        session.warm()
        try await waitUntil("launch") { launchArgs.value(after: "--model") == "haiku" }
        session.update(config: .init(binary: Fixtures.fakeClaude, model: "opus", token: ""))
        try await waitUntil("relaunch with opus") { launchArgs.value(after: "--model") == "opus" }
    }

    @Test func missingBinaryFailsGracefully() {
        session = makeSession(binary: "/nonexistent/claude")
        session.send("hello")
        guard case .finished(nil, let error?, false) = events.last else {
            Issue.record("unexpected \(events)")
            return
        }
        #expect(error.contains("not found"))
    }
}
