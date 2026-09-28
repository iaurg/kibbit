import Foundation
import Testing
@testable import Kibbit

@Suite("Stream-JSON parser")
struct StreamParserTests {
    private func feed(_ lines: String...) -> [StreamParser.Message] {
        var parser = StreamParser()
        return parser.feed(Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    @Test func sessionInit() {
        #expect(feed(#"{"type":"system","subtype":"init","session_id":"abc","tools":[]}"#) == [.sessionStarted(id: "abc")])
        #expect(feed(#"{"type":"system","subtype":"status","status":"requesting"}"#).isEmpty)
    }

    @Test func textDeltasOnly() {
        let messages = feed(
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hmm"}}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Paris."}}}"#,
            #"{"type":"stream_event","event":{"type":"message_stop"}}"#
        )
        #expect(messages == [.textDelta("Paris.")])
    }

    @Test func linesSplitAcrossChunks() {
        var parser = StreamParser()
        let line = #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"hi"}}}"# + "\n"
        let bytes = Array(line.utf8)
        #expect(parser.feed(Data(bytes[..<20])).isEmpty)
        #expect(parser.feed(Data(bytes[20..<(bytes.count - 1)])).isEmpty)
        #expect(parser.feed(Data(bytes[(bytes.count - 1)...])) == [.textDelta("hi")])
    }

    @Test func skipsGarbageAndUnknownTypes() {
        let messages = feed(
            "not json at all",
            "[1, 2, 3]",
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"dup"}]}}"#,
            #"{"type":"control_response","response":{"subtype":"success"}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"ok"}}}"#
        )
        #expect(messages == [.textDelta("ok")])
    }

    @Test func usageFromUnifiedWindows() {
        let line = #"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","utilization":0.9,"unifiedWindows":{"five_hour":{"utilization":0.05,"resetsAt":1790564400}}}}"#
        #expect(feed(line) == [.usage(fiveHour: 0.05)])
    }

    @Test func usageFallsBackToTopLevelUtilization() {
        #expect(feed(#"{"type":"rate_limit_event","rate_limit_info":{"utilization":0.4}}"#) == [.usage(fiveHour: 0.4)])
        #expect(feed(#"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed"}}"#).isEmpty)
    }

    @Test func results() {
        #expect(feed(#"{"type":"result","subtype":"success","is_error":false,"result":"Paris."}"#) == [.result(ok: true, text: "Paris.")])
        #expect(feed(#"{"type":"result","subtype":"success","is_error":true,"result":"Not logged in"}"#) == [.result(ok: false, text: "Not logged in")])
        #expect(feed(#"{"type":"result","subtype":"error_max_turns","errors":["too many turns"]}"#) == [.result(ok: false, text: "too many turns")])
        #expect(feed(#"{"type":"result","subtype":"error_during_execution"}"#) == [.result(ok: false, text: nil)])
    }
}
