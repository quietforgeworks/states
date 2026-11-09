import XCTest
@testable import StatesCore

final class CodexUsageTests: XCTestCase {
    private func event(_ total: Int64, _ last: Int64, stamp: String = "2026-11-06T16:01:00.000Z") -> [String: Any] {
        ["type": "event_msg", "timestamp": stamp, "payload": ["type": "token_count", "info": [
            "total_token_usage": ["total_tokens": total], "last_token_usage": ["total_tokens": last]]]]
    }
    func testRepeatedNotificationsAndForkBaseline() {
        let counter = CodexTokenCounter(); var cursor = CodexTokenCursor()
        counter.ingest(event(1000, 1000), cursor: &cursor)
        counter.ingest(event(1000, 1000), cursor: &cursor)
        counter.ingest(event(1500, 500), cursor: &cursor)
        var fork = CodexTokenCursor(); counter.ingest(event(50000, 100), cursor: &fork)
        XCTAssertEqual(counter.daily["2026-11-07"], 1600)
    }
    func testBeijingMidnight() {
        let counter = CodexTokenCounter(); var cursor = CodexTokenCursor()
        counter.ingest(event(700, 700, stamp: "2026-11-06T15:59:59Z"), cursor: &cursor)
        counter.ingest(event(1000, 300, stamp: "2026-11-06T16:00:00Z"), cursor: &cursor)
        XCTAssertEqual(counter.daily["2026-11-06"], 700)
        XCTAssertEqual(counter.daily["2026-11-07"], 300)
    }
    func testIncrementalPartialLinesAndArchiveMove() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("archived_sessions"), withIntermediateDirectories: true)
        let file = root.appendingPathComponent("sessions/test.jsonl")
        var first = try JSONSerialization.data(withJSONObject: event(1000, 1000)); first.append(10)
        try first.write(to: file)
        let scanner = CodexLocalUsageScanner(home: root), today = ISO8601DateFormatter().date(from: "2026-11-07T03:00:00Z")!
        XCTAssertEqual(scanner.scan(now: today), 1000)
        var next = try JSONSerialization.data(withJSONObject: event(1500, 500)); next.append(10)
        let output = try FileHandle(forWritingTo: file); try output.seekToEnd()
        try output.write(contentsOf: next.prefix(20)); XCTAssertEqual(scanner.scan(now: today), 1000)
        try output.write(contentsOf: next.dropFirst(20)); try output.close()
        XCTAssertEqual(scanner.scan(now: today), 1500)
        try FileManager.default.moveItem(at: file, to: root.appendingPathComponent("archived_sessions/test.jsonl"))
        XCTAssertEqual(scanner.scan(now: today), 1500)
    }
    func testMissingQuotaAndMostRecentWindow() {
        let rows = CodexQuotaWindow.parse(["rateLimits": ["primary": ["usedPercent": NSNull()]]])
        XCTAssertNil(rows.first?.remaining)
        XCTAssertEqual(CodexQuotaWindow.parse(["rateLimitsByLimitId": ["codex": ["primary": ["usedPercent": 8.0]]]]).first?.remaining, 92)
        XCTAssertEqual(CodexUsageFormat.millions(1_500_000), "1.500 MToken")
        XCTAssertEqual(CodexUsageFormat.millions(nil), "— MToken")
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(CodexUsageFormat.countdown(now.addingTimeInterval(6*86400+5*3600+45*60+24), now: now), "6天 05:45:24")
        XCTAssertEqual(CodexUsageFormat.countdown(now.addingTimeInterval(-1), now: now), "等待同步")
    }
}
