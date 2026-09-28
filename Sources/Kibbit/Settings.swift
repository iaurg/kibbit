import Carbon.HIToolbox
import Foundation
import Security
import ServiceManagement

enum ClaudeModel: String, CaseIterable, Identifiable {
    case haiku, sonnet, opus

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

struct HotKeyPreset: Identifiable, Equatable {
    let id: String
    let label: String
    let keyCode: UInt32
    let modifiers: UInt32

    static let all: [HotKeyPreset] = [
        HotKeyPreset(id: "opt-space", label: "⌥ Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)),
        HotKeyPreset(id: "ctrl-opt-space", label: "⌃⌥ Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)),
        HotKeyPreset(id: "cmd-shift-space", label: "⌘⇧ Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey)),
        HotKeyPreset(id: "cmd-opt-k", label: "⌘⌥ K", keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | optionKey)),
        HotKeyPreset(id: "none", label: "Off", keyCode: 0, modifiers: 0),
    ]

    static func find(_ id: String) -> HotKeyPreset { all.first { $0.id == id } ?? all[0] }
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var pet: PetKind { didSet { defaults.set(pet.rawValue, forKey: "pet") } }
    @Published var seed: UInt64 { didSet { defaults.set(String(seed), forKey: "seed") } }
    @Published var model: ClaudeModel { didSet { defaults.set(model.rawValue, forKey: "model") } }
    @Published var hotKeyID: String { didSet { defaults.set(hotKeyID, forKey: "hotKey") } }
    @Published var claudePath: String { didSet { defaults.set(claudePath, forKey: "claudePath") } }
    @Published var token: String { didSet { Keychain.set(token, account: "oauth-token") } }
    @Published var onboarded: Bool { didSet { defaults.set(onboarded, forKey: "onboarded") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        onboarded = defaults.bool(forKey: "onboarded")
        if let stored = defaults.string(forKey: "pet").flatMap(PetKind.init(rawValue:)) {
            pet = stored
        } else {
            // A new install hatches a surprise species; it can be changed later in Settings.
            let hatched = PetKind.allCases.randomElement()!
            pet = hatched
            defaults.set(hatched.rawValue, forKey: "pet")
        }
        model = ClaudeModel(rawValue: defaults.string(forKey: "model") ?? "") ?? .haiku
        hotKeyID = defaults.string(forKey: "hotKey") ?? HotKeyPreset.all[0].id
        claudePath = defaults.string(forKey: "claudePath") ?? ""
        token = Keychain.get(account: "oauth-token") ?? ""
        if let stored = defaults.string(forKey: "seed").flatMap(UInt64.init) {
            seed = stored
        } else {
            // Each install hatches its own colors.
            seed = PetPalette.randomSeed()
            defaults.set(String(seed), forKey: "seed")
        }
    }

    var palette: PetPalette { PetPalette(seed: seed, pet: pet) }
    var hotKey: HotKeyPreset { HotKeyPreset.find(hotKeyID) }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }
}

enum Keychain {
    private static let service = "Kibbit"

    static func get(account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// Carbon hot keys work system-wide without the Accessibility permission an event tap would need.
final class HotKey {
    static var onPress: (() -> Void)?
    private static var handlerInstalled = false
    private var ref: EventHotKeyRef?

    /// Returns Carbon's status. Note it only reports clashes within this app: a combo already
    /// taken by another app (Claude Desktop, ChatGPT…) still returns noErr, which is why
    /// onboarding asks the user to actually press it.
    @discardableResult
    func register(_ preset: HotKeyPreset) -> OSStatus {
        unregister()
        guard preset.id != "none" else { return noErr }
        if !Self.handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKey.onPress?() }
                return noErr
            }, 1, &spec, nil, nil)
            Self.handlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x4B42_4254), id: 1)
        let status = RegisterEventHotKey(preset.keyCode, preset.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr { ref = nil }
        return status
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}
