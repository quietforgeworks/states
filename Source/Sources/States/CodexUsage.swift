import AppKit
import StatesCore

private enum UsageError: Error { case unavailable, disconnected, timeout }

private final class UsageReply {
    let semaphore = DispatchSemaphore(value: 0)
    var message: [String: Any]?
}

private final class CodexUsageRPC {
    private let lock = NSLock()
    private var process: Process?
    private var input: Pipe?
    private var pending: [Int: UsageReply] = [:]
    private var serial = 0
    private var allowed = false
    func enable() { lock.lock(); allowed = true; lock.unlock() }
    func close() { disconnect(disable: true) }
    private func disconnect(disable: Bool) {
        lock.lock(); if disable { allowed = false }
        let child = process; process = nil
        let stream = input; input = nil
        let waiting = pending.values; pending.removeAll()
        lock.unlock()
        try? stream?.fileHandleForWriting.close()
        if child?.isRunning == true { child?.terminate() }
        for reply in waiting { reply.semaphore.signal() }
    }
    private func connect() throws {
        lock.lock()
        guard allowed else { lock.unlock(); throw UsageError.disconnected }
        if process?.isRunning == true { lock.unlock(); return }
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            NSHomeDirectory() + "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex"
        ]
        guard let executable = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            lock.unlock(); throw UsageError.unavailable
        }
        let child = Process(), stdin = Pipe(), stdout = Pipe()
        child.executableURL = URL(fileURLWithPath: executable)
        child.arguments = ["app-server", "--listen", "stdio://"]
        child.standardInput = stdin; child.standardOutput = stdout; child.standardError = FileHandle.nullDevice
        do { try child.run() } catch { lock.unlock(); throw error }
        process = child; input = stdin
        lock.unlock()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var buffer = Data()
            while true {
                let block = stdout.fileHandleForReading.availableData
                if block.isEmpty { break }
                buffer.append(block)
                while let end = buffer.firstIndex(of: 10) {
                    let line = buffer.prefix(upTo: end); buffer.removeSubrange(...end)
                    guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                          let id = message["id"] as? Int, let self else { continue }
                    self.lock.lock()
                    if let reply = self.pending[id] { reply.message = message; reply.semaphore.signal() }
                    self.lock.unlock()
                }
            }
            try? stdout.fileHandleForReading.close()
            guard let self else { return }
            self.lock.lock()
            if self.process === child {
                self.process = nil; self.input = nil
                for reply in self.pending.values { reply.semaphore.signal() }
            }
            self.lock.unlock()
        }
        _ = try request("initialize", params: ["clientInfo": ["name": "states_usage", "title": "States", "version": "1.0.6"],
                         "capabilities": ["experimentalApi": true]])
        try send(["method": "initialized"])
    }
    private func send(_ message: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: message); data.append(10)
        lock.lock(); defer { lock.unlock() }
        guard allowed, let input, process?.isRunning == true else { throw UsageError.disconnected }
        try input.fileHandleForWriting.write(contentsOf: data)
    }
    private func request(_ method: String, params: [String: Any]? = nil) throws -> [String: Any] {
        let reply = UsageReply()
        lock.lock(); serial += 1; let id = serial; pending[id] = reply; lock.unlock()
        defer { lock.lock(); pending.removeValue(forKey: id); lock.unlock() }
        var message: [String: Any] = ["id": id, "method": method]
        if let params { message["params"] = params }
        try send(message)
        guard reply.semaphore.wait(timeout: .now() + 25) == .success else { throw UsageError.timeout }
        lock.lock(); let result = reply.message; lock.unlock()
        guard let result, result["error"] == nil, let value = result["result"] as? [String: Any] else { throw UsageError.unavailable }
        return value
    }
    func readLimits() throws -> [CodexQuotaWindow] {
        do { try connect(); return CodexQuotaWindow.parse(try request("account/rateLimits/read")) }
        catch {
            disconnect(disable: false); throw error
        }
    }
}

final class CodexUsageService {
    var onUpdate: (() -> Void)?
    private(set) var windows: [CodexQuotaWindow] = []
    private(set) var quotaUpdatedAt: Date?
    private(set) var quotaFailed = false
    private(set) var tokens: Int64?
    private(set) var tokenDay: String?
    private var timers: [DispatchSourceTimer] = []
    private var generation = 0
    private let rpc = CodexUsageRPC()
    private let tokenQueue = DispatchQueue(label: "local.states.codex.tokens", qos: .utility)
    private let quotaQueue = DispatchQueue(label: "local.states.codex.quota", qos: .utility)
    private let scanner = CodexLocalUsageScanner(home: URL(fileURLWithPath:
        ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory() + "/.codex", isDirectory: true))
    func start() {
        guard timers.isEmpty else { return }
        generation += 1; let token = generation; rpc.enable()
        let local = DispatchSource.makeTimerSource(queue: tokenQueue)
        local.schedule(deadline: .now(), repeating: 10, leeway: .seconds(1))
        local.setEventHandler { [weak self] in
            guard let self else { return }
            let now = Date(), tokens = autoreleasepool { self.scanner.scan() }
            DispatchQueue.main.async {
                guard token == self.generation else { return }
                self.tokens = tokens; self.tokenDay = CodexUsageFormat.day(now); self.onUpdate?()
            }
        }
        let quota = DispatchSource.makeTimerSource(queue: quotaQueue)
        quota.schedule(deadline: .now(), repeating: 60, leeway: .seconds(2))
        quota.setEventHandler { [weak self] in
            guard let self else { return }
            do {
                let windows = try self.rpc.readLimits()
                DispatchQueue.main.async {
                    guard token == self.generation else { return }
                    self.windows = windows; self.quotaUpdatedAt = Date(); self.quotaFailed = windows.isEmpty; self.onUpdate?()
                }
            } catch {
                DispatchQueue.main.async {
                    guard token == self.generation else { return }
                    self.quotaFailed = true; self.onUpdate?()
                }
            }
        }
        timers = [local, quota]; local.resume(); quota.resume()
    }
    func stop() { generation += 1; for timer in timers { timer.cancel() }; timers.removeAll(); rpc.close() }
    var todayTokens: Int64? { tokenDay == CodexUsageFormat.day(Date()) ? tokens : nil }
    var window: CodexQuotaWindow? { windows.min { ($0.remaining ?? 101) < ($1.remaining ?? 101) } }
    var isStale: Bool { quotaFailed || quotaUpdatedAt.map { Date().timeIntervalSince($0) > 150 } ?? true }
    deinit { for timer in timers { timer.cancel() }; rpc.close() }
}

final class CodexUsageTile: Surface {
    private let title = label("Codex", size: 12, weight: .medium, color: .secondaryLabelColor)
    private let value = label("—", size: 28, weight: .semibold)
    private let resetTitle = label("距离自动恢复", size: 10, color: .secondaryLabelColor)
    private let reset = label("—", size: 12, weight: .medium)
    private let usage = label("今日 — MToken", size: 11, color: .secondaryLabelColor)
    private let track = NSView(), fill = NSView()
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true); setAccessibilityRole(.group); setAccessibilityLabel("Codex 用量")
        value.font = .monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        reset.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        resetTitle.alignment = .right; reset.alignment = .right
        title.frame = NSRect(x: 15, y: 12, width: 100, height: 17)
        value.frame = NSRect(x: 15, y: 33, width: 100, height: 37)
        resetTitle.frame = NSRect(x: 112, y: 12, width: 131, height: 17)
        reset.frame = NSRect(x: 107, y: 43, width: 136, height: 22)
        usage.frame = NSRect(x: 15, y: 75, width: 228, height: 17)
        track.frame = NSRect(x: 15, y: 113, width: 228, height: 3)
        track.wantsLayer = true; track.layer?.cornerRadius = 2
        fill.wantsLayer = true; fill.layer?.cornerRadius = 2; track.addSubview(fill)
        for item in [title, value, resetTitle, reset, usage, track] { addSubview(item) }
    }
    required init?(coder: NSCoder) { fatalError() }
    func update(_ service: CodexUsageService, color: NSColor) {
        update(window: service.window, tokens: service.todayTokens, stale: service.isStale, color: color)
    }
    func update(window: CodexQuotaWindow?, tokens: Int64?, stale: Bool, color: NSColor, now: Date = Date()) {
        title.stringValue = stale && window != nil ? "Codex · 待同步" : "Codex"
        value.stringValue = CodexUsageFormat.remaining(window?.remaining)
        reset.stringValue = CodexUsageFormat.countdown(window?.resetsAt, now: now)
        usage.stringValue = "今日 " + CodexUsageFormat.millions(tokens)
        let accent: NSColor = (window?.remaining ?? 100) <= 10 ? .systemOrange : color
        track.layer?.backgroundColor = accent.withAlphaComponent(0.15).cgColor
        fill.layer?.backgroundColor = accent.cgColor
        fill.frame = NSRect(x: 0, y: 0, width: 228 * CGFloat(window?.remaining ?? 0) / 100, height: 3)
        setAccessibilityValue("剩余 " + value.stringValue + "，自动恢复 " + reset.stringValue + "，" + usage.stringValue)
        toolTip = "额度来自当前登录的 Codex 账户；今日用量统计本机 Codex 记录，北京时间 00:00 起算，含缓存输入。"
    }
}
