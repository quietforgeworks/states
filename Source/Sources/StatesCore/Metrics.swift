import Foundation
import Darwin
import IOKit
import IOKit.ps
import SystemConfiguration

/// Stateful native sampler. Call from one serial background queue; publish its value on main.
/// Missing counters remain nil. No subprocesses, privilege requests or hardware writes occur here.
public final class NativeMetricsSampler {
    private var lastCPU: [[UInt32]]?
    private var lastNetwork: (time: TimeInterval, counters: [String: (UInt64, UInt64)])?
    private var diskCache = DiskReading()
    private var diskCacheTime: TimeInterval = -.infinity
    private lazy var cpuHardware = readCPUHardware()
    private var gpuHardware: [UInt64: (name: String, cores: Int?)] = [:]
    public init() {}

    public func sample() -> SystemReading {
        let now = ProcessInfo.processInfo.systemUptime
        if now - diskCacheTime > 30 { diskCache = disk(); diskCacheTime = now }
        return SystemReading(cpu: cpu(), gpu: gpu(), memory: memory(), power: power(),
                             network: network(now: now), disk: diskCache,
                             thermal: thermal(), uptime: now)
    }

    private func cpu() -> CPUReading {
        var reading = cpuHardware
        var count: natural_t = 0
        var info: processor_info_array_t?
        var words: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &words)
        guard result == KERN_SUCCESS, let info else { lastCPU = nil; return reading }
        defer { vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(words) * vm_size_t(MemoryLayout<integer_t>.stride)) }
        let width = Int(CPU_STATE_MAX)
        guard width > 0, Int(words) >= Int(count) * width else { lastCPU = nil; return reading }
        let current = (0..<Int(count)).map { core in (0..<width).map { UInt32(bitPattern: info[core * width + $0]) } }
        let previous = lastCPU
        lastCPU = current
        var load: Double = 0
        let hasLoad = getloadavg(&load, 1) == 1
        reading.loadAverage = hasLoad ? load : nil
        guard let previous, previous.count == current.count else { return reading }
        let fractions = zip(previous, current).map { MetricsMath.cpuFraction(previous: $0.0, current: $0.1) }
        guard fractions.allSatisfy({ $0 != nil }), !fractions.isEmpty else { return reading }
        let values = fractions.compactMap { $0 }
        reading.usage = values.reduce(0, +) / Double(values.count)
        reading.cores = values
        return reading
    }

    private func readCPUHardware() -> CPUReading {
        var reading = CPUReading()
        reading.modelName = sysctlString("machdep.cpu.brand_string") ?? "CPU"
        reading.logicalCores = sysctlInt("hw.ncpu") ?? ProcessInfo.processInfo.processorCount
        if let levels = sysctlInt("hw.nperflevels"), (1...8).contains(levels) {
            for index in 0..<levels {
                guard let name = sysctlString("hw.perflevel\(index).name"),
                      let count = sysctlInt("hw.perflevel\(index).logicalcpu"), count > 0 else { continue }
                switch name.lowercased() {
                case "performance": reading.performanceCores = count
                case "efficiency": reading.efficiencyCores = count
                default: break
                }
            }
        }
        return reading
    }

    private func sysctlInt(_ key: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(key, &value, &size, nil, 0) == 0 ? Int(value) : nil
    }
    private func sysctlString(_ key: String) -> String? {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, (1...1024).contains(size) else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(cString: bytes)
    }

    private func memory() -> MemoryReading {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let total = ProcessInfo.processInfo.physicalMemory
        var pressure: Int32 = 0
        var pressureSize = MemoryLayout<Int32>.size
        let hasPressure = sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &pressureSize, nil, 0) == 0
        let pressureName = hasPressure ? ([1: "正常", 2: "偏高", 4: "严重"][Int(pressure)] ?? "未知") : "未知"
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let hasSwap = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0
        guard result == KERN_SUCCESS else { return MemoryReading(total: total, pressure: pressureName) }
        let page = UInt64(vm_kernel_page_size)
        // App memory + wired + compressed; file-backed cache and purgeable memory are reclaimable.
        let appPages = UInt64(stats.active_count) + UInt64(stats.inactive_count) + UInt64(stats.speculative_count)
        let reclaimable = UInt64(stats.external_page_count) + UInt64(stats.purgeable_count)
        let app = appPages > reclaimable ? appPages - reclaimable : 0
        let used = min(total, (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page)
        return MemoryReading(total: total, used: used, compressed: UInt64(stats.compressor_page_count) * page,
                             swapUsed: hasSwap ? swap.xsu_used : 0, pressure: pressureName, available: true, swapAvailable: hasSwap)
    }

    private func gpu() -> GPUReading {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return GPUReading() }
        defer { IOObjectRelease(iterator) }
        var selected: GPUReading?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            // Registry entry IDs serve only as in-memory cache keys, never persisted or displayed.
            var entryID: UInt64 = 0
            let cacheable = IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS
            let metadata: (name: String, cores: Int?)
            if cacheable, let cached = gpuHardware[entryID] { metadata = cached }
            else {
                var name = "GPU"
                if let model = registryValue(service, "model") as? String { name = model }
                else if let model = registryValue(service, "model") as? Data, let text = String(data: model, encoding: .utf8) { name = text.trimmingCharacters(in: .controlCharacters) }
                let count = (registryValue(service, "gpu-core-count") as? NSNumber)?.intValue
                metadata = (name, count.flatMap { (1...1024).contains($0) ? $0 : nil })
                if cacheable { gpuHardware[entryID] = metadata }
            }
            var usage: Double?
            if let stats = registryValue(service, "PerformanceStatistics") as? [String: Any] {
                // IOAccelerator provides percentage counters on supported drivers. Never infer utilization from frequency.
                for key in ["Device Utilization %", "GPU Activity(%)", "GPU Core Utilization"] {
                    if let number = stats[key] as? NSNumber, let value = MetricsMath.validPercent(number.doubleValue) {
                        usage = value
                        break
                    }
                }
            }
            let candidate = GPUReading(usage: usage, name: metadata.name, coreCount: metadata.cores)
            // Preserve model/core metadata from the same device as its reported utilization.
            if selected == nil || (usage ?? -1) > (selected?.usage ?? -1) { selected = candidate }
        }
        return selected ?? GPUReading()
    }

    private func power() -> PowerReading {
        var reading = PowerReading(source: "未知", state: "未知")
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                      desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
                let external = desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
                let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
                let full = desc[kIOPSIsChargedKey] as? Bool ?? false
                reading.source = external ? "电源适配器" : "电池"
                reading.state = charging ? "充电中" : (full ? "已充满" : (external ? "已接电 · 暂停充电" : "放电中"))
                if let current = number(desc[kIOPSCurrentCapacityKey]), let max = number(desc[kIOPSMaxCapacityKey]), max > 0 {
                    reading.batteryPercent = min(100, Swift.max(0, current / max * 100))
                }
                let timeKey = charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
                if let minutes = number(desc[timeKey]), minutes > 0 { reading.remainingMinutes = minutes }
                break
            }
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return reading }
        defer { IOObjectRelease(service) }
        // Only read specific non-identifying properties; never enumerate battery metadata.
        var properties: [String: Any] = [:]
        for key in ["ExternalConnected", "IsCharging", "Voltage", "InstantAmperage", "Amperage", "AdapterDetails", "PowerTelemetryData"] {
            properties[key] = registryValue(service, key)
        }
        reading = MetricsMath.applyingBatteryRegistry(to: reading, properties: properties)
        if let cycle = number(registryValue(service, "CycleCount")), cycle >= 0, cycle < 100000 { reading.cycleCount = Int(cycle) }
        // Raw/design capacity ratios are not the official battery-health percentage.
        reading.healthPercent = nil
        return reading
    }

    private func network(now: TimeInterval) -> NetworkReading {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { lastNetwork = nil; return NetworkReading() }
        defer { freeifaddrs(list) }
        var counters: [String: (UInt64, UInt64)] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            let entry = item.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  entry.ifa_flags & UInt32(IFF_UP) != 0, entry.ifa_flags & UInt32(IFF_RUNNING) != 0,
                  entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  let data = entry.ifa_data else { continue }
            let name = String(cString: entry.ifa_name)
            // Physical Ethernet / Wi-Fi only: avoids counting VPN tunnels and their transport twice.
            guard name.hasPrefix("en") else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            counters[name] = (UInt64(stats.ifi_ibytes), UInt64(stats.ifi_obytes))
        }
        // Prefer the primary physical interface selected by SystemConfiguration. If unavailable,
        // report the sum of active physical interfaces without tunnel/loopback duplication.
        let primary = primaryInterface()
        let selected = primary.flatMap { counters[$0] == nil ? nil : $0 }
        let names = selected.map { [$0] } ?? counters.keys.sorted()
        let previous = lastNetwork
        lastNetwork = (now, counters)
        let label = names.isEmpty ? "—" : names.joined(separator: "+")
        guard let previous else { return NetworkReading(interface: label) }
        let elapsed = now - previous.time
        // Sleep, clock discontinuity or an unusually long gap invalidates instantaneous rates.
        guard elapsed > 0, elapsed <= 15, !names.isEmpty else { return NetworkReading(interface: label) }
        var input: Double = 0, output: Double = 0
        for name in names {
            guard let current = counters[name], let old = previous.counters[name],
                  let received = MetricsMath.rate(previous: old.0, current: current.0, elapsed: elapsed),
                  let sent = MetricsMath.rate(previous: old.1, current: current.1, elapsed: elapsed) else { return NetworkReading(interface: label) }
            input += received; output += sent
        }
        return NetworkReading(receivedPerSecond: input, sentPerSecond: output, interface: label)
    }

    private func primaryInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "States" as CFString, nil, nil) else { return nil }
        for key in ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"] {
            if let values = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any], let name = values["PrimaryInterface"] as? String, name.hasPrefix("en") { return name }
        }
        return nil
    }

    private func disk() -> DiskReading {
        // Reports free capacity without treating reclaimable/purgeable files as already free.
        guard let values = try? FileManager.default.attributesOfFileSystem(forPath: "/System/Volumes/Data"),
              let total = values[.systemSize] as? NSNumber,
              let available = values[.systemFreeSize] as? NSNumber else { return DiskReading() }
        return DiskReading(available: available.uint64Value, total: total.uint64Value)
    }
    private func thermal() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "正常"
        case .fair: return "温热"
        case .serious: return "较热"
        case .critical: return "过热"
        @unknown default: return "未知"
        }
    }
    private func registryValue(_ service: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
    private func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }
}

// Pure unit/delta conversions, shared by the sampler and deterministic self-tests.
enum MetricsMath {
    static func cpuFraction(previous: [UInt32], current: [UInt32]) -> Double? {
        guard previous.count == current.count, current.count >= Int(CPU_STATE_MAX) else { return nil }
        // CPU tick counters wrap naturally at UInt32.max; a delta over 2^31 is treated as reset.
        let deltas = zip(previous, current).map { $0.1 &- $0.0 }
        guard deltas.allSatisfy({ $0 < UInt32.max / 2 }) else { return nil }
        let total = deltas.reduce(UInt64(0)) { $0 + UInt64($1) }
        guard total > 0 else { return nil }
        return Double(total - UInt64(deltas[Int(CPU_STATE_IDLE)])) / Double(total)
    }
    static func rate(previous: UInt64, current: UInt64, elapsed: Double) -> Double? {
        guard elapsed.isFinite, elapsed > 0, current >= previous else { return nil }
        return Double(current - previous) / elapsed
    }
    static func validPercent(_ value: Double) -> Double? {
        guard value.isFinite, (0...100).contains(value) else { return nil }
        return value / 100
    }
    static func signedMilliamps(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        // Earlier drivers exposed two's complement UInt32 currents.
        if value > Double(Int32.max), value <= Double(UInt32.max) { return Double(Int32(bitPattern: UInt32(value))) }
        return value
    }
    /// Registry connection status wins over the slower IOPS summary. No prior frame is reused.
    static func applyingBatteryRegistry(to initial: PowerReading, properties: [String: Any]) -> PowerReading {
        var reading = initial
        let external = properties["ExternalConnected"] as? Bool
        let charging = properties["IsCharging"] as? Bool
        reading.externalConnected = external
        if let external {
            reading.source = external ? "电源适配器" : "电池"
            if !external {
                reading.state = "放电中"
                // IOPS may still report a cached time-to-full after removal.
                if initial.source != "电池" { reading.remainingMinutes = nil }
            } else if let charging {
                reading.state = charging ? "充电中" : (initial.state == "已充满" ? "已充满" : "已接电 · 暂停充电")
                if initial.source != "电源适配器" { reading.remainingMinutes = nil }
            }
        }
        // Always clear previous values before validating this sample, including after disconnect.
        reading.batteryWatts = nil
        reading.batteryPowerSource = nil
        reading.currentAmps = nil
        reading.voltage = nil
        reading.adapterRatedWatts = nil
        reading.inputWatts = nil
        reading.systemLoadWatts = nil
        if let mv = (properties["Voltage"] as? NSNumber)?.doubleValue, mv.isFinite, (1000...30000).contains(mv) {
            reading.voltage = mv / 1000
        }
        // InstantAmperage can remain live while the driver's averaged Amperage is zero.
        // Decode UInt64 two's complement BEFORE floating conversion; older UInt32 is also supported.
        for key in ["InstantAmperage", "Amperage"] {
            guard let raw = properties[key] as? NSNumber, raw.doubleValue.isFinite,
                  let ma = signedMilliamps(Double(raw.int64Value)), abs(ma) <= 50000 else { continue }
            let onBattery = external == false || (external == nil && reading.source == "电池")
            // A running Mac cannot consume zero battery power without an external source.
            // Positive current after removal is a cached charging frame, not discharge.
            if onBattery && ma >= 0 { continue }
            if external == true && charging == false && ma > 0 { continue }
            guard let volts = reading.voltage, abs(volts * ma / 1000) <= 600 else { continue }
            reading.currentAmps = ma / 1000
            reading.batteryWatts = volts * ma / 1000
            reading.batteryPowerSource = "\(key) × Voltage"
            break
        }
        // Adapter and load telemetry may remain cached after physical removal.
        // Never reuse those frames or derive a battery measurement by balancing other powers.
        guard external == true else { return reading }
        if let adapter = properties["AdapterDetails"] as? [String: Any],
           let watts = (adapter["Watts"] as? NSNumber)?.doubleValue,
           watts.isFinite, watts > 0, watts < 1000 { reading.adapterRatedWatts = watts }
        if let telemetry = properties["PowerTelemetryData"] as? [String: Any] {
            reading.inputWatts = validatedInputWatts(externalConnected: true,
                milliwatts: (telemetry["SystemPowerIn"] as? NSNumber)?.doubleValue,
                millivolts: (telemetry["SystemVoltageIn"] as? NSNumber)?.doubleValue,
                milliamps: (telemetry["SystemCurrentIn"] as? NSNumber)?.doubleValue)
            if let mw = (telemetry["SystemLoad"] as? NSNumber)?.doubleValue,
               mw.isFinite, (0...600000).contains(mw) { reading.systemLoadWatts = mw / 1000 }
        }
        return reading
    }
    static func validatedInputWatts(externalConnected: Bool, milliwatts: Double?, millivolts: Double?, milliamps: Double?) -> Double? {
        guard externalConnected, let power = milliwatts, let voltage = millivolts, let current = milliamps,
              power.isFinite, voltage.isFinite, current.isFinite else { return nil }
        let watts = power / 1000, volts = voltage / 1000, amps = current / 1000
        guard (0...600).contains(watts), (4...60).contains(volts), (0...12).contains(amps),
              abs(watts - volts * amps) <= max(2, watts * 0.2) else { return nil }
        return watts
    }
}

public func runMetricsSelfTests() throws {
    struct Failure: Error { let check: String }
    func require(_ condition: Bool, _ check: String) throws { if !condition { throw Failure(check: check) } }
    try require(MetricsMath.cpuFraction(previous: [0, 0, 0, 0], current: [20, 0, 80, 0]) == 0.2, "CPU tick utilization")
    try require(MetricsMath.cpuFraction(previous: [1, 1, 1, 1], current: [1, 1, 1, 1]) == nil, "CPU idle sample is unavailable")
    try require(MetricsMath.cpuFraction(previous: [100, 0, 100, 0], current: [1, 0, 1, 0]) == nil, "CPU reset")
    try require(MetricsMath.rate(previous: 100, current: 500, elapsed: 2) == 200, "Network bytes per second")
    try require(MetricsMath.rate(previous: 500, current: 100, elapsed: 2) == nil, "Network reset")
    try require(MetricsMath.rate(previous: 0, current: 10, elapsed: 0) == nil, "Network zero interval")
    try require(MetricsMath.validPercent(125) == nil && MetricsMath.validPercent(25) == 0.25, "GPU percentage units")
    try require(MetricsMath.signedMilliamps(4294966296) == -1000, "Signed battery current")
    try require(MetricsMath.signedMilliamps(-1000) == -1000, "Discharging battery sign")
    try require(MetricsMath.validatedInputWatts(externalConnected: true, milliwatts: 10418, millivolts: 20509, milliamps: 508) == 10.418, "Input power unit conversion and physical agreement")
    try require(MetricsMath.validatedInputWatts(externalConnected: false, milliwatts: 10418, millivolts: 20509, milliamps: 508) == nil, "Disconnected adapter rejects stale telemetry")
    try require(MetricsMath.validatedInputWatts(externalConnected: true, milliwatts: 50000, millivolts: 20509, milliamps: 508) == nil, "Inconsistent input power rejected")
    try require(MetricsMath.validatedInputWatts(externalConnected: true, milliwatts: .nan, millivolts: 20509, milliamps: 508) == nil, "Invalid input telemetry rejected")
    try require(MetricsMath.validatedInputWatts(externalConnected: true, milliwatts: 10418, millivolts: nil, milliamps: 508) == nil, "Missing input telemetry rejected")
}
