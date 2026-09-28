import Foundation

enum Fixtures {
    /// Stand-in for the `claude` CLI; see Fixtures/fake-claude.
    static let fakeClaude = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/fake-claude").path

    static func tempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kibbit-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

struct TimedOut: Error, CustomStringConvertible {
    let what: String
    var description: String { "Timed out waiting for \(what)" }
}

/// Polls on the main actor so callbacks dispatched to the main queue get a chance to run.
@MainActor
func waitUntil(_ what: String, timeout: TimeInterval = 10, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { throw TimedOut(what: what) }
        try await Task.sleep(for: .milliseconds(20))
    }
}

func lines(of file: URL) -> [String] {
    (try? String(contentsOf: file, encoding: .utf8))?.components(separatedBy: "\n") ?? []
}

extension Array where Element == String {
    /// The value following a command-line flag, e.g. `["--model", "haiku"].value(after: "--model")`.
    func value(after flag: String) -> String? {
        guard let i = firstIndex(of: flag), i + 1 < count else { return nil }
        return self[i + 1]
    }
}
