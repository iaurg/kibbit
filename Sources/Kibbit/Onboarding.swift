import AppKit
import Carbon.HIToolbox
import SwiftUI

/// First-run setup: hatch the pet, make sure Claude Code is installed and signed in, and prove the
/// hotkey reaches us. Each check is re-runnable because users leave to fix things in Terminal.
@MainActor
final class Onboarding: ObservableObject {
    enum Step: Int, CaseIterable { case hatch, claude, hotKey, finish }

    enum ClaudeCheck: Equatable {
        case checking
        case missingCLI
        case loggedOut
        case ready(plan: String?)
    }

    enum HotKeyCheck: Equatable {
        case waiting
        case received
        case failed(String)
    }

    static let installCommand = "curl -fsSL https://claude.ai/install.sh | bash"

    @Published var step: Step = .hatch
    @Published private(set) var hatched = false
    @Published private(set) var hatching = false
    @Published private(set) var eggWobble = 0
    @Published private(set) var eggCrack = 0
    @Published private(set) var claude: ClaudeCheck = .checking
    @Published private(set) var hotKey: HotKeyCheck = .waiting
    @Published var launchAtLogin = true

    private let settings: AppSettings
    private let workspace: URL
    private var polling: Task<Void, Never>?

    init(settings: AppSettings, workspace: URL = ClaudeSession.defaultWorkspace) {
        self.settings = settings
        self.workspace = workspace
    }

    var isWaitingForHotKey: Bool { step == .hotKey && hotKey != .received }

    func hatch() { hatched = true }

    /// Shake, crack twice, then reveal.
    func playHatch() async {
        guard !hatched, !hatching else { return }
        hatching = true
        for i in 0..<10 {
            eggWobble = i % 2 == 0 ? 1 : -1
            try? await Task.sleep(for: .milliseconds(70))
        }
        eggWobble = 0
        for stage in 1...2 {
            eggCrack = stage
            try? await Task.sleep(for: .milliseconds(400))
        }
        hatching = false
        hatched = true
    }

    func next() {
        guard let following = Step(rawValue: step.rawValue + 1) else { return }
        go(to: following)
    }

    func go(to target: Step) {
        step = target
        polling?.cancel()
        switch target {
        case .claude: startPolling()
        case .hotKey: hotKey = .waiting
        default: break
        }
    }

    func restart() {
        hatched = settings.onboarded
        go(to: .hatch)
    }

    func finish() {
        polling?.cancel()
        if launchAtLogin != settings.launchAtLogin { settings.launchAtLogin = launchAtLogin }
        settings.onboarded = true
    }

    // MARK: Claude

    /// Re-checks every couple of seconds while this step is on screen, so finishing the
    /// install or sign-in in Terminal flips the row green without a click.
    private func startPolling() {
        polling = Task { [weak self] in
            // Bounded, so a user who never installs Claude Code doesn't leave it polling forever.
            for _ in 0..<300 where !Task.isCancelled {
                await self?.checkClaude()
                if case .ready = self?.claude { return }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func checkClaude() async {
        let override = settings.claudePath
        let token = settings.token
        let workspace = workspace
        claude = await Task.detached {
            guard let binary = ClaudeSession.locateBinary(override: override) else { return ClaudeCheck.missingCLI }
            return Self.authStatus(binary: binary, token: token, workspace: workspace)
        }.value
    }

    nonisolated static func authStatus(binary: String, token: String, workspace: URL) -> ClaudeCheck {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = ["auth", "status", "--json"]
        p.environment = ClaudeSession.environment(token: token)
        p.currentDirectoryURL = workspace
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return .missingCLI }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return parseAuthStatus(data)
    }

    nonisolated static func parseAuthStatus(_ data: Data) -> ClaudeCheck {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["loggedIn"] as? Bool == true else { return .loggedOut }
        return .ready(plan: obj["subscriptionType"] as? String)
    }

    func installClaude() {
        runInTerminal(Self.installCommand, title: "Installing Claude Code")
    }

    func signIn() {
        let binary = ClaudeSession.locateBinary(override: settings.claudePath) ?? "claude"
        runInTerminal("\(Self.shellQuoted(binary)) auth login", title: "Signing in to Claude")
    }

    /// Opens Terminal with a command already running. A generated `.command` file needs no
    /// Automation permission, unlike scripting Terminal through Apple Events.
    private func runInTerminal(_ command: String, title: String) {
        let script = """
        #!/bin/bash
        clear
        echo "Kibbit · \(title)"
        echo
        \(command)
        echo
        echo "Done. You can close this window and go back to Kibbit."
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kibbit-setup-\(UUID().uuidString.prefix(8)).command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            NSSound.beep()
        }
    }

    nonisolated static func shellQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: Hotkey

    func registrationResult(_ status: OSStatus) {
        guard status != noErr else { return }
        hotKey = .failed(status == OSStatus(eventHotKeyExistsErr)
            ? "That shortcut is already taken. Pick another below."
            : "macOS refused that shortcut (error \(status)). Pick another below.")
    }

    func hotKeyPressed() {
        guard isWaitingForHotKey else { return }
        hotKey = .received
    }

    func hotKeyChanged() {
        hotKey = .waiting
    }
}
