import Foundation

/// Drives a long-lived `claude -p` process over stream-JSON stdin/stdout.
///
/// Keeping the process warm cuts time-to-first-token from ~4s (cold CLI start) to ~1s.
/// Auth is whatever Claude Code already uses (your subscription login), or an optional
/// token from `claude setup-token`. All methods must be called on the main thread.
final class ClaudeSession {
    struct Config: Equatable {
        var binary: String
        var model: String
        var token: String
    }

    enum Event: Equatable {
        case delta(String)
        case finished(text: String?, error: String?, stopped: Bool)
        case usage(fiveHour: Double)
    }

    static let systemPrompt = """
    You are a tiny pixel pet living in the macOS menu bar. The user pops you open mid-task \
    (in a terminal or editor) for a quick answer and wants to get straight back to work.
    - Lead with the answer. No preamble, no restating the question, no offers to help further.
    - Prefer one line, a short list, or one code block. Go longer only if the question truly needs it.
    - Put commands and code in fenced code blocks with a language tag so they can be copied.
    - If the question is ambiguous, answer the most likely reading and note the assumption in a few words.
    """

    var onEvent: ((Event) -> Void)?
    private(set) var lastError: String?

    private var config: Config
    private var process: Process?
    private var stdin: FileHandle?
    private var parser = StreamParser()
    private var generation = 0
    private var sessionID: String?
    private var hasHistory = false
    private var turnActive = false
    private var stopRequested = false
    private var idleTimer: Timer?

    private let workspace: URL

    static let defaultWorkspace = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Kibbit/workspace", isDirectory: true)

    init(config: Config, workspace: URL = ClaudeSession.defaultWorkspace) {
        self.config = config
        self.workspace = workspace
        try? FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    deinit {
        process?.terminate()
    }

    var isRunning: Bool { process?.isRunning == true }

    func update(config new: Config) {
        guard new != config else { return }
        config = new
        // Respawn so the new model/credentials apply; --resume keeps the conversation.
        if isRunning, !turnActive {
            terminate()
            warm()
        }
    }

    func warm() {
        guard !isRunning else { return }
        spawn()
    }

    func send(_ text: String) {
        if !isRunning { spawn() }
        guard let stdin else {
            onEvent?(.finished(text: nil, error: lastError ?? "Could not start claude.", stopped: false))
            return
        }
        turnActive = true
        stopRequested = false
        hasHistory = true
        idleTimer?.invalidate()
        write(["type": "user", "message": ["role": "user", "content": text]], to: stdin)
    }

    func stop() {
        guard turnActive, let stdin else { return }
        stopRequested = true
        write(["type": "control_request", "request_id": UUID().uuidString, "request": ["subtype": "interrupt"]], to: stdin)
    }

    /// Forget the conversation and start a fresh warm process.
    func reset() {
        terminate()
        sessionID = nil
        hasHistory = false
        warm()
    }

    func terminate() {
        idleTimer?.invalidate()
        generation += 1
        stdin = nil
        process?.terminate()
        process = nil
        if turnActive {
            turnActive = false
            onEvent?(.finished(text: nil, error: nil, stopped: true))
        }
    }

    // MARK: - Process plumbing

    private func spawn() {
        lastError = nil
        guard FileManager.default.isExecutableFile(atPath: config.binary) else {
            lastError = "Claude Code CLI not found. Install it or set its path in Settings."
            return
        }
        var args = [
            "-p", "--model", config.model, "--effort", "low",
            "--tools", "", "--setting-sources", "", "--strict-mcp-config", "--disable-slash-commands",
            "--system-prompt", Self.systemPrompt,
            "--input-format", "stream-json", "--output-format", "stream-json",
            "--include-partial-messages", "--verbose",
        ]
        if hasHistory, let sessionID { args += ["--resume", sessionID] }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: config.binary)
        p.arguments = args
        p.environment = Self.environment(token: config.token)
        p.currentDirectoryURL = workspace
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe

        generation += 1
        let gen = generation
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty { h.readabilityHandler = nil }
            DispatchQueue.main.async { self?.ingest(data, gen: gen) }
        }
        // stderr only matters once the process dies (e.g. "Not logged in"). Reading it to EOF and
        // handing it over with the exit avoids racing two async callbacks.
        let stderrDone = DispatchGroup()
        var stderrData = Data()
        stderrDone.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrData = errPipe.fileHandleForReading.readDataToEndOfFile()
            stderrDone.leave()
        }
        p.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            _ = stderrDone.wait(timeout: .now() + 1)
            let stderr = String(decoding: stderrData.suffix(600), as: UTF8.self)
            DispatchQueue.main.async { self?.exited(status: status, stderr: stderr, gen: gen) }
        }

        do {
            try p.run()
        } catch {
            lastError = "Could not launch claude: \(error.localizedDescription)"
            return
        }
        process = p
        stdin = inPipe.fileHandleForWriting
        parser = StreamParser()
    }

    private func write(_ object: [String: Any], to handle: FileHandle) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        do {
            try handle.write(contentsOf: data)
        } catch {
            terminate()
            onEvent?(.finished(text: nil, error: "Lost connection to claude. Try again.", stopped: false))
        }
    }

    private func ingest(_ data: Data, gen: Int) {
        guard gen == generation else { return }
        parser.feed(data).forEach(handle)
    }

    private func handle(_ message: StreamParser.Message) {
        switch message {
        case .sessionStarted(let id):
            sessionID = id
        case .textDelta(let text):
            onEvent?(.delta(text))
        case .usage(let fiveHour):
            onEvent?(.usage(fiveHour: fiveHour))
        case .result(let ok, let text):
            guard turnActive else { return }
            turnActive = false
            scheduleIdleShutdown()
            if stopRequested {
                onEvent?(.finished(text: nil, error: nil, stopped: true))
            } else if ok {
                onEvent?(.finished(text: text, error: nil, stopped: false))
            } else {
                onEvent?(.finished(text: nil, error: text ?? "Claude returned an error.", stopped: false))
            }
        }
    }

    private func exited(status: Int32, stderr: String, gen: Int) {
        guard gen == generation else { return }
        process = nil
        stdin = nil
        let tail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        lastError = tail.isEmpty ? "claude exited (code \(status))." : tail
        if turnActive {
            turnActive = false
            onEvent?(.finished(text: nil, error: lastError, stopped: false))
        }
    }

    /// An idle warm process is ~150 MB; drop it after a while. The next question resumes the session.
    private func scheduleIdleShutdown() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: false) { [weak self] _ in
            guard let self, !self.turnActive else { return }
            self.terminate()
        }
    }

    /// Environment for every `claude` launch, chats and setup checks alike.
    static func environment(token: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Apps launched from Finder get a bare PATH; npm-installed CLIs also need node.
        let home = NSHomeDirectory()
        env["PATH"] = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", env["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
        // Never silently bill an API key: this app is meant to ride the subscription.
        env.removeValue(forKey: "ANTHROPIC_API_KEY")
        // --setting-sources "" doesn't cover these: the workspace lives under ~, so the CLI would
        // otherwise inject the home project's auto-memory and ~/.claude/CLAUDE.md into every question.
        env["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] = "1"
        env["CLAUDE_CODE_DISABLE_CLAUDE_MDS"] = "1"
        if !token.isEmpty { env["CLAUDE_CODE_OAUTH_TOKEN"] = token }
        return env
    }

    // MARK: - Locating the CLI

    static func locateBinary(override: String) -> String? {
        let fm = FileManager.default
        if !override.isEmpty { return fm.isExecutableFile(atPath: override) ? override : nil }
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/claude", "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
            "\(home)/.npm-global/bin/claude", "\(home)/.bun/bin/claude",
        ]
        if let hit = candidates.first(where: fm.isExecutableFile(atPath:)) { return hit }
        // Last resort: ask a login shell, which sees the user's real PATH.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v claude"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let path = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return fm.isExecutableFile(atPath: path) ? path : nil
    }
}
