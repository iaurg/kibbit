import Foundation

/// Turns the `claude -p --output-format stream-json` byte stream into the few messages the app
/// cares about. Output arrives in arbitrary chunks, so partial lines are buffered until their newline.
struct StreamParser {
    enum Message: Equatable {
        case sessionStarted(id: String)
        case textDelta(String)
        case usage(fiveHour: Double)
        case result(ok: Bool, text: String?)
    }

    private var buffer = Data()

    mutating func feed(_ data: Data) -> [Message] {
        buffer.append(data)
        var out: [Message] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let msg = Self.message(from: obj) {
                out.append(msg)
            }
        }
        return out
    }

    static func message(from obj: [String: Any]) -> Message? {
        switch obj["type"] as? String {
        case "system":
            guard obj["subtype"] as? String == "init", let id = obj["session_id"] as? String else { return nil }
            return .sessionStarted(id: id)

        case "stream_event":
            // Only visible text; thinking and tool-input deltas are skipped.
            guard let event = obj["event"] as? [String: Any], event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String else { return nil }
            return .textDelta(text)

        case "rate_limit_event":
            let info = obj["rate_limit_info"] as? [String: Any]
            let windows = info?["unifiedWindows"] as? [String: Any]
            let fiveHour = windows?["five_hour"] as? [String: Any]
            guard let used = (fiveHour?["utilization"] ?? info?["utilization"]) as? Double else { return nil }
            return .usage(fiveHour: used)

        case "result":
            if obj["is_error"] as? Bool == true || obj["subtype"] as? String != "success" {
                let message = obj["result"] as? String ?? (obj["errors"] as? [String])?.first
                return .result(ok: false, text: message)
            }
            return .result(ok: true, text: obj["result"] as? String)

        default:
            return nil
        }
    }
}
