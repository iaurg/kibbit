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

    enum Event {
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
    private var stdout = Data()
    private var stderrTail = ""
    private var generation = 0
    private var sessionID: String?
    private var hasHistory = false
    private var turnActive = false
    private var stopRequested = false
    private var idleTimer: Timer?

    private let workspace: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kibbit/workspace", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    init(config: Config) {
        self.config = config
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
        if !config.token.isEmpty { env["CLAUDE_CODE_OAUTH_TOKEN"] = config.token }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: config.binary)
        p.arguments = args
        p.environment = env
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
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty { h.readabilityHandler = nil }
            DispatchQueue.main.async { self?.ingestError(data, gen: gen) }
        }
        p.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            DispatchQueue.main.async { self?.exited(status: status, gen: gen) }
        }

        do {
            try p.run()
        } catch {
            lastError = "Could not launch claude: \(error.localizedDescription)"
            return
        }
        process = p
        stdin = inPipe.fileHandleForWriting
        stdout = Data()
        stderrTail = ""
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
        stdout.append(data)
        while let nl = stdout.firstIndex(of: 0x0A) {
            let line = stdout[stdout.startIndex..<nl]
            stdout.removeSubrange(stdout.startIndex...nl)
            if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                handle(obj)
            }
        }
    }

    private func ingestError(_ data: Data, gen: Int) {
        guard gen == generation, let s = String(data: data, encoding: .utf8) else { return }
        stderrTail = String((stderrTail + s).suffix(600))
    }

    private func handle(_ obj: [String: Any]) {
        switch obj["type"] as? String {
        case "system":
            if obj["subtype"] as? String == "init", let id = obj["session_id"] as? String { sessionID = id }

        case "stream_event":
            guard let event = obj["event"] as? [String: Any], event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String else { return }
            onEvent?(.delta(text))

        case "rate_limit_event":
            let info = obj["rate_limit_info"] as? [String: Any]
            let windows = info?["unifiedWindows"] as? [String: Any]
            let fiveHour = windows?["five_hour"] as? [String: Any]
            if let used = (fiveHour?["utilization"] ?? info?["utilization"]) as? Double {
                onEvent?(.usage(fiveHour: used))
            }

        case "result":
            guard turnActive else { return }
            turnActive = false
            scheduleIdleShutdown()
            if stopRequested {
                onEvent?(.finished(text: nil, error: nil, stopped: true))
            } else if obj["is_error"] as? Bool == true || obj["subtype"] as? String != "success" {
                let message = obj["result"] as? String ?? (obj["errors"] as? [String])?.first ?? "Claude returned an error."
                onEvent?(.finished(text: nil, error: message, stopped: false))
            } else {
                onEvent?(.finished(text: obj["result"] as? String, error: nil, stopped: false))
            }

        default:
            break
        }
    }

    private func exited(status: Int32, gen: Int) {
        guard gen == generation else { return }
        process = nil
        stdin = nil
        let tail = stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
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
