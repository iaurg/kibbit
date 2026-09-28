import AppKit

// Writing to a dead claude process must surface as an error, not kill the app.
signal(SIGPIPE, SIG_IGN)

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--render-gallery"), i + 1 < args.count {
    DebugRender.gallery(to: args[i + 1])
    exit(0)
}
if let i = args.firstIndex(of: "--render-card"), i + 1 < args.count {
    let settings = MainActor.assumeIsolated { AppSettings() }
    let png = MainActor.assumeIsolated { ShareCard.pngData(pet: settings.pet, seed: settings.seed) }
    try? png?.write(to: URL(fileURLWithPath: args[i + 1]))
    exit(png == nil ? 1 : 0)
}
if let i = args.firstIndex(of: "--render-iconset"), i + 1 < args.count {
    DebugRender.iconset(to: args[i + 1])
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
