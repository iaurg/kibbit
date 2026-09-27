import Foundation

@MainActor
final class PetAnimator: ObservableObject {
    enum Mood: Equatable { case idle, thinking, talking, happy, sleeping, error }

    @Published private(set) var frame = PetFrame()
    @Published var mood: Mood = .idle {
        didSet {
            guard mood != oldValue else { return }
            tick = 0
            lastActivity = Date()
            moodTimeout?.invalidate()
            // Reactions are brief; the pet settles back to idle on its own.
            if mood == .happy || mood == .error {
                moodTimeout = Timer.scheduledTimer(withTimeInterval: mood == .happy ? 2 : 4, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.mood = .idle }
                }
            }
            advance()
        }
    }

    var legendary = false
    private var tick = 0
    private var timer: Timer?
    private var moodTimeout: Timer?
    private var lastActivity = Date()
    private var nextBlink = Int.random(in: 12...40)

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func poke() {
        lastActivity = Date()
        if mood == .sleeping { mood = .idle }
    }

    private func advance() {
        tick += 1
        if mood == .idle, Date().timeIntervalSince(lastActivity) > 10 * 60 { mood = .sleeping }

        var f = PetFrame()
        switch mood {
        case .idle:
            // Gentle breathing: down for 4 ticks, up for 4.
            f.y = (tick / 4) % 2 == 0 ? 1 : 2
            if tick % nextBlink == 0 {
                f.eyesClosed = true
                nextBlink = Int.random(in: 12...40)
            }
            if legendary, (tick / 3) % 12 == 0 { f.overlay = .sparkle }
        case .thinking:
            f.y = tick % 2 == 0 ? 1 : 2
            f.overlay = .dots((tick / 2) % 4)
        case .talking:
            f.y = tick % 4 < 2 ? 1 : 2
            f.eyesClosed = tick % 16 == 0
        case .happy:
            f.y = [0, 0, 1, 2, 1][tick % 5]
            f.overlay = .heart
        case .sleeping:
            f.y = (tick / 8) % 2 == 0 ? 1 : 2
            f.eyesClosed = true
            f.overlay = .zzz(tick / 6)
        case .error:
            f.y = 2
            f.overlay = .bang
        }
        if f != frame { frame = f }
    }
}
