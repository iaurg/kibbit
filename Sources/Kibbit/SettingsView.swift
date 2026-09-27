import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: ChatStore
    @ObservedObject var settings: AppSettings
    @State private var tokenDraft = ""
    @State private var pathDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { store.page = .chat } label: { PixelText(icon: PixelFont.Icon.back) }
                    .buttonStyle(PixelButtonStyle())
                    .keyboardShortcut("[", modifiers: .command)
                PixelText("SETTINGS", pixel: 2.5)
                Spacer()
            }
            .padding(12)
            .background(Theme.panel)
            Rectangle().fill(Theme.border).frame(height: 2)

            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("PET") { petGrid }
                    section("COLORS") { colors }
                    section("MODEL") {
                        Picker("", selection: $settings.model) {
                            ForEach(ClaudeModel.allCases) { Text($0 == .haiku ? "Haiku ⚡︎" : $0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        caption("Haiku answers fastest. Switching keeps the current chat.")
                    }
                    section("HOTKEY") {
                        Picker("", selection: $settings.hotKeyID) {
                            ForEach(HotKeyPreset.all) { Text($0.label).tag($0.id) }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                    section("CLAUDE") { claude }
                    section("SYSTEM") {
                        Toggle("Launch at login", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 }))
                            .toggleStyle(.checkbox)
                            .foregroundStyle(Theme.text)
                        Button { NSApp.terminate(nil) } label: { PixelText("QUIT", color: Theme.danger) }
                            .buttonStyle(PixelButtonStyle())
                    }
                }
                .padding(14)
                .id("top")
            }
            .scrollIndicators(.never)
            // The text fields grab first-responder on appear, which scrolls them into view.
            .onAppear { DispatchQueue.main.async { proxy.scrollTo("top", anchor: .top) } }
            }
        }
        .onAppear {
            tokenDraft = settings.token
            pathDraft = settings.claudePath
        }
    }

    private var petGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(78), spacing: 8), count: 4), alignment: .leading, spacing: 8) {
            ForEach(PetKind.allCases) { pet in
                let selected = pet == settings.pet
                Button { settings.pet = pet } label: {
                    VStack(spacing: 4) {
                        PetSpriteView(pet: pet, palette: PetPalette(seed: settings.seed, pet: pet), pixel: 3)
                            .frame(width: 48, height: 54, alignment: .leading)
                            .clipped()
                        PixelText(pet.displayName, pixel: 1.5, color: selected ? Theme.text : Theme.muted)
                    }
                    .frame(width: 70, height: 76)
                    .pixelPanel(fill: selected ? Theme.panelHi : Theme.panel, border: selected ? settings.palette.body.color : Theme.border,
                                shadow: selected)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var colors: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                PixelText(PetPalette.seedCode(settings.seed), pixel: 2, color: Theme.text)
                PixelText(settings.palette.rarity.label, pixel: 1.5, color: rarityColor)
            }
            Spacer()
            Button {
                settings.seed = PetPalette.randomSeed()
                store.animator.legendary = settings.palette.rarity == .legendary
                store.animator.mood = .happy
            } label: {
                HStack(spacing: 6) {
                    PixelText(icon: PixelFont.Icon.dice, color: settings.palette.accent.color)
                    PixelText("REROLL")
                }
            }
            .buttonStyle(PixelButtonStyle())
        }
    }

    private var rarityColor: Color {
        switch settings.palette.rarity {
        case .common: Theme.muted
        case .rare: Color(red: 0.45, green: 0.75, blue: 1)
        case .legendary: Color(red: 1, green: 0.85, blue: 0.3)
        }
    }

    private var claude: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Rectangle().fill(store.claudeStatus.hasPrefix("Found") ? Theme.good : Theme.danger).frame(width: 6, height: 6)
                Text(store.claudeStatus)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            field("CLI path (blank = auto-detect)", text: $pathDraft, secure: false)
            field("Token from `claude setup-token` (optional)", text: $tokenDraft, secure: true)
            HStack {
                Button {
                    settings.claudePath = pathDraft.trimmingCharacters(in: .whitespaces)
                    settings.token = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.relocateClaude()
                } label: { PixelText("SAVE") }
                    .buttonStyle(PixelButtonStyle())
                Spacer()
            }
            caption("Uses your Claude subscription through Claude Code's login. Run `claude` once in a terminal to sign in, or paste a long-lived token.")
        }
    }

    private func field(_ placeholder: String, text: Binding<String>, secure: Bool) -> some View {
        Group {
            if secure { SecureField(placeholder, text: text) } else { TextField(placeholder, text: text) }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(Theme.text)
        .padding(8)
        .pixelPanel(fill: Theme.code, shadow: false)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PixelText(title, pixel: 2, color: settings.palette.body.color)
            content()
        }
    }

    private func caption(_ s: String) -> some View {
        Text(.init(s))
            .font(.system(size: 11))
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
