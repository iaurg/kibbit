import Carbon.HIToolbox
import Foundation
import Testing
@testable import Kibbit

@Suite("Onboarding", .serialized)
@MainActor
final class OnboardingTests {
    private let workspace = Fixtures.tempDirectory()
    private let defaults = UserDefaults(suiteName: "kibbit-tests-\(UUID().uuidString)")!

    deinit {
        try? FileManager.default.removeItem(at: workspace)
    }

    private func makeOnboarding(claudePath: String = Fixtures.fakeClaude) -> (Onboarding, AppSettings) {
        defaults.set(claudePath, forKey: "claudePath")
        let settings = AppSettings(defaults: defaults)
        return (Onboarding(settings: settings, workspace: workspace), settings)
    }

    @Test func parsesAuthStatus() {
        let signedIn = Data(#"{"loggedIn": true, "authMethod": "claude.ai", "subscriptionType": "max"}"#.utf8)
        #expect(Onboarding.parseAuthStatus(signedIn) == .ready(plan: "max"))
        #expect(Onboarding.parseAuthStatus(Data(#"{"loggedIn": true, "authMethod": "oauth_token"}"#.utf8)) == .ready(plan: nil))
        #expect(Onboarding.parseAuthStatus(Data(#"{"loggedIn": false}"#.utf8)) == .loggedOut)
        #expect(Onboarding.parseAuthStatus(Data("Error: something broke".utf8)) == .loggedOut)
    }

    @Test func detectsSignedInCLI() async {
        let (onboarding, _) = makeOnboarding()
        await onboarding.checkClaude()
        #expect(onboarding.claude == .ready(plan: "pro"))
    }

    @Test func detectsSignedOutCLI() async throws {
        try Data().write(to: workspace.appendingPathComponent("logged-out"))
        let (onboarding, _) = makeOnboarding()
        await onboarding.checkClaude()
        #expect(onboarding.claude == .loggedOut)
    }

    @Test func detectsMissingCLI() async {
        let (onboarding, _) = makeOnboarding(claudePath: "/nonexistent/claude")
        await onboarding.checkClaude()
        #expect(onboarding.claude == .missingCLI)
    }

    /// The Claude step polls, so signing in from Terminal flips it to ready with no click.
    @Test func claudeStepNoticesSignIn() async throws {
        let marker = workspace.appendingPathComponent("logged-out")
        try Data().write(to: marker)
        let (onboarding, _) = makeOnboarding()
        onboarding.go(to: .claude)
        try await waitUntil("signed-out state") { onboarding.claude == .loggedOut }
        try FileManager.default.removeItem(at: marker)
        try await waitUntil("sign-in noticed") { onboarding.claude == .ready(plan: "pro") }
        onboarding.go(to: .hotKey)
    }

    @Test func stepsAdvanceInOrder() {
        let (onboarding, _) = makeOnboarding()
        #expect(onboarding.step == .hatch)
        #expect(!onboarding.hatched)
        onboarding.hatch()
        onboarding.next()
        #expect(onboarding.step == .claude)
        onboarding.go(to: .finish)
        onboarding.next()
        #expect(onboarding.step == .finish, "no step after finish")
    }

    @Test func hotKeyPressOnlyCountsOnItsStep() {
        let (onboarding, _) = makeOnboarding()
        onboarding.hotKeyPressed()
        #expect(onboarding.hotKey == .waiting)
        onboarding.go(to: .hotKey)
        #expect(onboarding.isWaitingForHotKey)
        onboarding.hotKeyPressed()
        #expect(onboarding.hotKey == .received)
        #expect(!onboarding.isWaitingForHotKey)
        onboarding.hotKeyChanged()
        #expect(onboarding.hotKey == .waiting, "a new shortcut must be tested again")
    }

    @Test func reportsRejectedHotKeys() {
        let (onboarding, _) = makeOnboarding()
        onboarding.registrationResult(noErr)
        #expect(onboarding.hotKey == .waiting)
        onboarding.registrationResult(OSStatus(eventHotKeyExistsErr))
        guard case .failed(let message) = onboarding.hotKey else { Issue.record("expected failure"); return }
        #expect(message.contains("already taken"))
    }

    @Test func finishMarksOnboarded() {
        let (onboarding, settings) = makeOnboarding()
        onboarding.launchAtLogin = settings.launchAtLogin
        onboarding.finish()
        #expect(settings.onboarded)
        #expect(AppSettings(defaults: defaults).onboarded)
    }

    @Test func restartKeepsTheHatchedPet() {
        let (onboarding, settings) = makeOnboarding()
        settings.onboarded = true
        onboarding.go(to: .finish)
        onboarding.restart()
        #expect(onboarding.step == .hatch)
        #expect(onboarding.hatched, "returning users see their pet, not a new egg")
    }

    @Test func chatStoreStartsInSetupUntilOnboarded() {
        defaults.set(Fixtures.fakeClaude, forKey: "claudePath")
        let settings = AppSettings(defaults: defaults)
        let store = ChatStore(settings: settings, animator: PetAnimator(), workspace: workspace)
        #expect(store.page == .onboarding)
        store.onboarding.launchAtLogin = settings.launchAtLogin
        store.finishOnboarding()
        #expect(store.page == .chat)
        let again = ChatStore(settings: AppSettings(defaults: defaults), animator: PetAnimator(), workspace: workspace)
        #expect(again.page == .chat)
    }

    @Test func shellQuoting() {
        #expect(Onboarding.shellQuoted("/Users/me/.local/bin/claude") == "'/Users/me/.local/bin/claude'")
        #expect(Onboarding.shellQuoted("/Users/o'neil/claude") == #"'/Users/o'\''neil/claude'"#)
    }

    @Test func shareCardRenders() throws {
        let png = try #require(ShareCard.pngData(pet: .axolotl, seed: 0xDA6B_2B9B))
        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(png.count > 1_000)
    }
}
