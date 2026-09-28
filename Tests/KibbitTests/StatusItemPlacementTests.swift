import Foundation
import Testing
@testable import Kibbit

@Suite("Menu bar placement")
struct StatusItemPlacementTests {
    private func placement() -> (StatusItemPlacement, UserDefaults) {
        let defaults = UserDefaults(suiteName: "kibbit-tests-\(UUID().uuidString)")!
        return (StatusItemPlacement(defaults: defaults), defaults)
    }

    /// A fresh install (or one after --uninstall) must not start at the left end of the
    /// status area, which is behind the notch on crowded MacBook menu bars.
    @Test func freshInstallStartsOnTheRight() {
        let (p, defaults) = placement()
        p.seedIfNeeded()
        #expect(defaults.double(forKey: StatusItemPlacement.positionKey) == StatusItemPlacement.rightSide)
    }

    @Test func userChosenPositionIsKept() {
        let (p, defaults) = placement()
        defaults.set(612.0, forKey: StatusItemPlacement.positionKey)
        p.seedIfNeeded()
        #expect(defaults.double(forKey: StatusItemPlacement.positionKey) == 612)
    }

    @Test func autoMovesOnlyOnce() {
        let (p, defaults) = placement()
        #expect(!p.shouldAutoMove(visible: true))
        #expect(p.shouldAutoMove(visible: false))
        defaults.set(820.0, forKey: StatusItemPlacement.positionKey)
        p.prepareMoveRight()
        #expect(defaults.double(forKey: StatusItemPlacement.positionKey) == StatusItemPlacement.rightSide)
        #expect(!p.shouldAutoMove(visible: false), "a user hiding the pet on purpose isn't fought every launch")
    }

    @Test func positionKeyMatchesAppKitsDefaultAutosaveName() {
        #expect(StatusItemPlacement.positionKey == "NSStatusItem Preferred Position Item-0")
    }
}
