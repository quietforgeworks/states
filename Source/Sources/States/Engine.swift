import AppKit
import IOKit.pwr_mgt
import StatesCore

struct HistoryPoint {
    var date: Date, cpu: Double?, gpu: Double?, memory: Double?, watts: Double?
}

final class MonitorEngine {
    var onUpdate: (() -> Void)?
    private(set) var reading = SystemReading()
    private(set) var smc = SMCReading()
    private(set) var history: [HistoryPoint] = []
    private let queue = DispatchQueue(label: "local.states.sampling", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var sampler: NativeMetricsSampler?
    private var device: SMCDevice?
    private var generation: UInt64 = 0
    private var actualInterval: Double = 0
    private let prefs: StatesPreferences
    init(prefs: StatesPreferences) { self.prefs = prefs }
    func start() {
        let interval = prefs.batterySaver && reading.power.source.contains("电池") ? max(5, prefs.interval) : prefs.interval
        guard actualInterval != interval else { return }
        actualInterval = interval; generation &+= 1; let token = generation
        queue.async { [self] in
            self.timer?.cancel()
            if self.sampler == nil { self.sampler = NativeMetricsSampler(); self.device = SMCDevice() }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(150))
            timer.setEventHandler { [weak self] in
                guard let self, let sampler = self.sampler, let device = self.device else { return }
                let reading = autoreleasepool { sampler.sample() }
                let smc = autoreleasepool { device.snapshot() }
                DispatchQueue.main.async {
                    guard token == self.generation else { return }
                    self.reading = reading; self.smc = smc
                    self.history.append(.init(date: reading.date, cpu: reading.cpu.usage, gpu: reading.gpu.usage, memory: reading.memory.available ? reading.memory.fraction : nil, watts: smc.systemWatts ))
                    if self.history.count > 180 { self.history.removeFirst(self.history.count - 180) }
                    self.onUpdate?(); self.start()
                }
            }
            self.timer = timer; timer.resume()
        }
    }
    func stop() { generation &+= 1; actualInterval = 0; queue.async { self.timer?.cancel(); self.timer = nil } }
}

final class AwakeController {
    private var assertion: IOPMAssertionID = 0
    private var expires: Date?
    private var timer: Timer?
    var onChange: (() -> Void)?
    var active: Bool { assertion != 0 }
    var remaining: String {
        guard let expires, active else { return "关闭" }
        return "剩余 \(max(0, Int(ceil(expires.timeIntervalSinceNow / 60)))) 分钟"
    }
    func enable(minutes: Int = 60) -> Bool {
        disable()
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn), "临时保持唤醒" as CFString, &assertion)
        guard result == kIOReturnSuccess else { assertion = 0; return false }
        expires = Date().addingTimeInterval(Double(minutes * 60))
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.expires?.timeIntervalSinceNow ?? 0 <= 0 { self.disable() } else { self.onChange?() }
        }
        onChange?(); return true
    }
    func disable() { timer?.invalidate(); timer = nil; if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }; expires = nil; onChange?() }
    deinit { if assertion != 0 { IOPMAssertionRelease(assertion) } }
}

enum DisplayFormat {
    static func percent(_ value: Double?) -> String { value.map { "\(Int(($0 * 100).rounded()))%" } ?? "—" }
    static func watts(_ value: Double?, signed: Bool = false) -> String {
        guard let value, value.isFinite else { return "不可用" }
        return String(format: signed ? "%+.1f W" : "%.1f W", value)
    }
    static func bytes(_ value: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory) }
    static func diskBytes(_ value: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file) }
    static func rate(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(max(0, value)), countStyle: .file) + "/s"
    }
}
