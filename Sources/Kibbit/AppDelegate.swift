import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let animator = PetAnimator()
    private lazy var store = ChatStore(settings: settings, animator: animator)
    private let hotKey = HotKey()
    private var statusItem: NSStatusItem!
    private var panel: PetPanel!
    private var lastDismiss = Date.distantPast
    private var bag: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: CGFloat(Sprite.width) + 4)
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let root = RootView(store: store) { [weak self] in self?.dismiss() }
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: RootView.size)
        panel = PetPanel(contentView: hosting, size: RootView.size)
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.onDismiss = { [weak self] in self?.dismiss() }

        animator.legendary = settings.palette.rarity == .legendary
        Publishers.CombineLatest3(animator.$frame, settings.$pet, settings.$seed)
            .sink { [weak self] frame, pet, seed in
                self?.statusItem.button?.image = Sprite.menuBarImage(pet: pet, palette: PetPalette(seed: seed, pet: pet), frame: frame)
            }
            .store(in: &bag)

        // Model/token edits respawn the warm process; debounce so typing in Settings doesn't thrash it.
        Publishers.CombineLatest(settings.$model, settings.$token)
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.store.applyConfig() }
            .store(in: &bag)

        HotKey.onPress = { [weak self] in self?.toggle() }
        settings.$hotKeyID
            .sink { [weak self] id in self?.hotKey.register(HotKeyPreset.find(id)) }
            .store(in: &bag)

        store.prepare()

        // Launch args for scripting/smoke tests: `--show` opens the panel, `--settings` opens
        // it on the settings page, `--ask "…"` also sends a question.
        let args = CommandLine.arguments
        if args.contains("--settings") { store.page = .settings }
        if args.contains("--show") || args.contains("--ask") || args.contains("--settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.show() }
        }
        if let i = args.firstIndex(of: "--ask"), i + 1 < args.count {
            store.input = args[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.store.send() }
        }
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            toggle()
        }
    }

    private func toggle() {
        // A status-item click first resigns the panel's key status (dismissing it); don't reopen.
        guard Date().timeIntervalSince(lastDismiss) > 0.3 else { return }
        if panel.isVisible { dismiss() } else { show() }
    }

    private func show() {
        let anchor = statusItem.button.flatMap { b in b.window.map { $0.convertToScreen(b.convert(b.bounds, to: nil)) } }
        // Open where the user is working: the screen under the mouse pointer.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        panel.place(anchor: anchor, on: screen)
        panel.makeKeyAndOrderFront(nil)
        store.prepare()
    }

    private func dismiss() {
        guard panel.isVisible else { return }
        lastDismiss = Date()
        panel.orderOut(nil)
        if store.page == .settings { store.page = .chat }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Ask…", action: #selector(openFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "New Chat", action: #selector(newChatFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(settingsFromMenu), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Kibbit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Detach so the next left click opens the panel instead of the menu.
        statusItem.menu = nil
    }

    @objc private func openFromMenu() { store.page = .chat; show() }
    @objc private func newChatFromMenu() { store.newChat(); store.page = .chat; show() }
    @objc private func settingsFromMenu() { store.page = .settings; show() }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey.unregister()
    }
}
