import SwiftUI

struct OnboardingView: View {
    @ObservedObject var store: ChatStore
    @ObservedObject var onboarding: Onboarding
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                PixelText("SETUP", pixel: 2.5)
                StepDots(current: onboarding.step.rawValue, color: settings.palette.body.color)
                Spacer()
                Button(action: store.finishOnboarding) { PixelText("SKIP", color: Theme.muted) }
                    .buttonStyle(PixelButtonStyle(fill: Theme.panel))
                    .help("Skip setup (you can run it again from Settings)")
            }
            .padding(12)
            .background(Theme.panel)
            Rectangle().fill(Theme.border).frame(height: 2)

            Group {
                switch onboarding.step {
                case .hatch: HatchStep(onboarding: onboarding, settings: settings, animator: store.animator)
                case .claude: ClaudeStep(onboarding: onboarding)
                case .hotKey: HotKeyStep(onboarding: onboarding, settings: settings, animator: store.animator)
                case .finish: FinishStep(onboarding: onboarding, settings: settings, animator: store.animator)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Rectangle().fill(Theme.border).frame(height: 2)
            footer
                .padding(12)
                .background(Theme.panel)
        }
    }

    private var footer: some View {
        HStack {
            if onboarding.step != .hatch {
                Button { onboarding.go(to: .init(rawValue: onboarding.step.rawValue - 1)!) } label: {
                    PixelText(icon: PixelFont.Icon.back)
                }
                .buttonStyle(PixelButtonStyle())
            }
            Spacer()
            switch onboarding.step {
            case .hatch:
                primary("NEXT", enabled: onboarding.hatched, action: onboarding.next)
            case .claude:
                if case .ready = onboarding.claude { primary("NEXT", action: onboarding.next) } else { secondary("SKIP FOR NOW", action: onboarding.next) }
            case .hotKey:
                if onboarding.hotKey == .received { primary("NEXT", action: onboarding.next) } else { secondary("SKIP", action: onboarding.next) }
            case .finish:
                primary("START ASKING", action: store.finishOnboarding)
            }
        }
    }

    private func primary(_ label: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                PixelText(label)
                PixelText(icon: PixelFont.Icon.send, color: settings.palette.body.color)
            }
        }
        .buttonStyle(PixelButtonStyle())
        .keyboardShortcut(.defaultAction)
        .disabled(!enabled)
    }

    private func secondary(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { PixelText(label, color: Theme.muted) }
            .buttonStyle(PixelButtonStyle(fill: Theme.panel))
    }
}

private struct StepDots: View {
    let current: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Onboarding.Step.allCases, id: \.rawValue) { step in
                Rectangle()
                    .fill(step.rawValue <= current ? color : Theme.border)
                    .frame(width: 6, height: 6)
            }
        }
    }
}

// MARK: - Steps

private struct HatchStep: View {
    @ObservedObject var onboarding: Onboarding
    @ObservedObject var settings: AppSettings
    @ObservedObject var animator: PetAnimator
    @State private var wobble = 0
    @State private var crack = 0
    @State private var hatching = false
    @State private var copied = false

    var body: some View {
        VStack(spacing: 14) {
            if onboarding.hatched {
                PetSpriteView(pet: settings.pet, palette: settings.palette, frame: animator.frame, pixel: 7)
                PixelText(settings.pet.displayName, pixel: 4, color: settings.palette.body.color)
                HStack(spacing: 10) {
                    PixelText(settings.palette.rarity.label, pixel: 2, color: settings.palette.rarity.color)
                    PixelText(PetPalette.seedCode(settings.seed), pixel: 2, color: Theme.muted)
                }
                Text(rarityBlurb)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                Button {
                    ShareCard.copyToPasteboard(pet: settings.pet, seed: settings.seed)
                    copied = true
                } label: {
                    HStack(spacing: 6) {
                        PixelText(icon: copied ? PixelFont.Icon.check : PixelFont.Icon.copy, color: copied ? Theme.good : Theme.text)
                        PixelText(copied ? "CARD COPIED" : "COPY SHARE CARD", color: copied ? Theme.good : Theme.text)
                    }
                }
                .buttonStyle(PixelButtonStyle())
            } else {
                CellCanvas(cells: Sprite.eggCells(palette: settings.palette, wobble: wobble, crack: crack), pixel: 7)
                PixelText(hatching ? "IT'S HATCHING!" : "SOMETHING IS INSIDE...", pixel: 2.5)
                Text("Every egg is unique. Its colors come from a random seed, and some are rare.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                Button(action: hatch) {
                    PixelText("HATCH", pixel: 2.5, color: settings.palette.body.color)
                }
                .buttonStyle(PixelButtonStyle())
                .disabled(hatching)
            }
        }
        .frame(maxWidth: .infinity)
        .task { await idleWobble() }
    }

    private var rarityBlurb: String {
        switch settings.palette.rarity {
        case .legendary: "Legendary! Only 3% of eggs hatch like this."
        case .rare: "A rare one. About 15% of eggs hatch two-toned."
        case .common: "Say hi to your new pet. Reroll colors or pick another pet any time in Settings."
        }
    }

    private func idleWobble() async {
        while !Task.isCancelled, !onboarding.hatched {
            try? await Task.sleep(for: .seconds(1.6))
            guard !hatching else { continue }
            for w in [1, -1, 1, 0] {
                wobble = w
                try? await Task.sleep(for: .milliseconds(90))
            }
        }
    }

    private func hatch() {
        hatching = true
        Task {
            for i in 0..<10 {
                wobble = i % 2 == 0 ? 1 : -1
                try? await Task.sleep(for: .milliseconds(70))
            }
            wobble = 0
            crack = 1
            try? await Task.sleep(for: .milliseconds(400))
            crack = 2
            try? await Task.sleep(for: .milliseconds(400))
            onboarding.hatch()
            animator.legendary = settings.palette.rarity == .legendary
            animator.mood = .happy
        }
    }
}

private struct ClaudeStep: View {
    @ObservedObject var onboarding: Onboarding

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PixelText("CONNECT CLAUDE", pixel: 3)
            Text("Kibbit answers with your Claude subscription through Claude Code. No API key needed.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                CheckRow(state: cliState, title: "Claude Code installed")
                CheckRow(state: loginState, title: loginTitle)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pixelPanel(fill: Theme.code, shadow: false)

            switch onboarding.claude {
            case .checking:
                PixelText("CHECKING...", pixel: 2, color: Theme.muted)
            case .missingCLI:
                Text("Install it with the official installer:")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                MarkdownBlocks(text: "```bash\n\(Onboarding.installCommand)\n```") { text in
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                Button(action: onboarding.installClaude) { PixelText("INSTALL IN TERMINAL") }
                    .buttonStyle(PixelButtonStyle())
            case .loggedOut:
                Text("Sign in with the Claude account that has your Pro or Max plan. A browser window will open.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onboarding.signIn) { PixelText("SIGN IN IN TERMINAL") }
                    .buttonStyle(PixelButtonStyle())
            case .ready:
                PixelText("YOU'RE CONNECTED!", pixel: 2, color: Theme.good)
            }

            if onboarding.claude == .missingCLI || onboarding.claude == .loggedOut {
                Text("This page updates by itself when you're done. Using a token from `claude setup-token`? Paste it in Settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var cliState: CheckRow.State {
        switch onboarding.claude {
        case .checking: .pending
        case .missingCLI: .bad
        default: .ok
        }
    }

    private var loginState: CheckRow.State {
        switch onboarding.claude {
        case .checking, .missingCLI: .pending
        case .loggedOut: .bad
        case .ready: .ok
        }
    }

    private var loginTitle: String {
        if case .ready(let plan?) = onboarding.claude { return "Signed in · \(plan.capitalized) plan" }
        return "Signed in"
    }
}

private struct CheckRow: View {
    enum State { case pending, ok, bad }

    let state: State
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            switch state {
            case .pending: PixelText("...", color: Theme.muted).frame(width: 10)
            case .ok: PixelText(icon: PixelFont.Icon.check, color: Theme.good).frame(width: 10)
            case .bad: PixelText(icon: PixelFont.Icon.close, color: Theme.danger).frame(width: 10)
            }
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(state == .pending ? Theme.muted : Theme.text)
        }
    }
}

private struct HotKeyStep: View {
    @ObservedObject var onboarding: Onboarding
    @ObservedObject var settings: AppSettings
    @ObservedObject var animator: PetAnimator

    var body: some View {
        VStack(spacing: 14) {
            PixelText("SUMMON ME ANYWHERE", pixel: 3)
            Text("From any app, even a fullscreen terminal, press:")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            Text(settings.hotKey.label)
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .pixelPanel(fill: Theme.panelHi, border: settings.palette.body.color)

            switch onboarding.hotKey {
            case .waiting:
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    let on = Int(ctx.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
                    PixelText("TRY IT NOW", pixel: 2.5, color: on ? settings.palette.body.color : Theme.muted)
                }
            case .received:
                HStack(spacing: 8) {
                    PixelText(icon: PixelFont.Icon.check, pixel: 2.5, color: Theme.good)
                    PixelText("GOT IT!", pixel: 2.5, color: Theme.good)
                }
            case .failed(let message):
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                Text("Nothing happened? Another app (Claude Desktop, ChatGPT, Raycast…) may already use it. Pick another:")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("", selection: $settings.hotKeyID) {
                    ForEach(HotKeyPreset.all.filter { $0.id != "none" }) { Text($0.label).tag($0.id) }
                }
                .labelsHidden()
                .frame(width: 150)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .onChange(of: onboarding.hotKey) {
            if onboarding.hotKey == .received { animator.mood = .happy }
        }
    }
}

private struct FinishStep: View {
    @ObservedObject var onboarding: Onboarding
    @ObservedObject var settings: AppSettings
    @ObservedObject var animator: PetAnimator

    var body: some View {
        VStack(spacing: 14) {
            PetSpriteView(pet: settings.pet, palette: settings.palette, frame: animator.frame, pixel: 5)
            PixelText("ALL SET!", pixel: 3.5, color: settings.palette.body.color)
            VStack(alignment: .leading, spacing: 6) {
                tip(settings.hotKey.id == "none" ? "click me" : settings.hotKey.label, "summon from anywhere")
                tip("↩", "ask")
                tip("⌘⇧V", "ask about your clipboard")
                tip("esc", "back to work")
            }
            .padding(10)
            .pixelPanel(fill: Theme.code, shadow: false)
            Toggle("Launch Kibbit at login", isOn: $onboarding.launchAtLogin)
                .toggleStyle(.checkbox)
                .foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity)
    }

    private func tip(_ key: String, _ label: String) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.text)
                .frame(width: 80, alignment: .trailing)
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .frame(width: 170, alignment: .leading)
        }
    }
}

// MARK: - Share card

/// The image users paste into chats: the "look what I hatched" loop.
struct ShareCard: View {
    let pet: PetKind
    let seed: UInt64

    var body: some View {
        let palette = PetPalette(seed: seed, pet: pet)
        VStack(spacing: 12) {
            PetSpriteView(pet: pet, palette: palette, frame: PetFrame(y: 0, overlay: palette.rarity == .common ? .heart : .sparkle), pixel: 9)
            PixelText(pet.displayName, pixel: 4, color: palette.body.color)
            PixelText(palette.rarity.label, pixel: 2.5, color: palette.rarity.color)
            PixelText(PetPalette.seedCode(seed), pixel: 2.5, color: Theme.text)
            PixelText("HATCHED IN KIBBIT", pixel: 1.5, color: Theme.muted)
                .padding(.top, 6)
        }
        .padding(28)
        .pixelPanel(fill: Theme.background, border: palette.body.color, shadow: false)
        .padding(8)
        .background(Theme.border)
    }

    @MainActor
    static func pngData(pet: PetKind, seed: UInt64) -> Data? {
        let renderer = ImageRenderer(content: ShareCard(pet: pet, seed: seed))
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    @MainActor
    static func copyToPasteboard(pet: PetKind, seed: UInt64) {
        guard let png = pngData(pet: pet, seed: seed) else { return NSSound.beep() }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)
    }
}
