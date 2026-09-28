import Foundation

/// Keeps the menu bar pet out from behind the MacBook notch.
///
/// macOS drops a brand-new status item at the left end of the status area. On a crowded menu bar
/// that is under the notch, where macOS hides it without reflowing. AppKit restores an item's spot
/// from the `NSStatusItem Preferred Position <autosave name>` default (points from the screen's
/// right edge), so seeding a small value places the pet beside the system icons instead.
struct StatusItemPlacement {
    static let positionKey = "NSStatusItem Preferred Position Item-0"
    static let autoMovedKey = "statusItemAutoMoved"
    /// Right of the notch, just left of Control Center and the clock on typical menu bars.
    static let rightSide = 250.0

    let defaults: UserDefaults

    /// First launch (or after an uninstall wiped settings): start on the right. A position the
    /// user picked by ⌘-dragging is left alone.
    func seedIfNeeded() {
        if defaults.object(forKey: Self.positionKey) == nil {
            defaults.set(Self.rightSide, forKey: Self.positionKey)
        }
    }

    /// Hidden once: move right automatically. Only once, so a user who hides the pet on purpose
    /// (e.g. with a menu bar manager) isn't fought on every launch.
    func shouldAutoMove(visible: Bool) -> Bool {
        !visible && !defaults.bool(forKey: Self.autoMovedKey)
    }

    func prepareMoveRight() {
        defaults.set(true, forKey: Self.autoMovedKey)
        defaults.set(Self.rightSide, forKey: Self.positionKey)
    }
}
