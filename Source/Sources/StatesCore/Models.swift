import Foundation

public struct CPUReading: Codable, Equatable {
    public var usage: Double?
    public var cores: [Double]
    public var loadAverage: Double?
    public var modelName: String, logicalCores: Int
    public var performanceCores: Int?, efficiencyCores: Int?
    public init(usage: Double? = nil, cores: [Double] = [], loadAverage: Double? = nil, modelName: String = "CPU", logicalCores: Int = 0, performanceCores: Int? = nil, efficiencyCores: Int? = nil) {
        self.usage = usage; self.cores = cores; self.loadAverage = loadAverage; self.modelName = modelName; self.logicalCores = logicalCores; self.performanceCores = performanceCores; self.efficiencyCores = efficiencyCores
    }
}
public struct GPUReading: Codable, Equatable {
    public var usage: Double?
    public var name: String
    public var coreCount: Int?
    public init(usage: Double? = nil, name: String = "GPU", coreCount: Int? = nil) { self.usage = usage; self.name = name; self.coreCount = coreCount }
}
public struct MemoryReading: Codable, Equatable {
    public var total: UInt64, used: UInt64, compressed: UInt64, swapUsed: UInt64
    public var pressure: String
    public var available: Bool, swapAvailable: Bool
    public var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    public init(total: UInt64 = 0, used: UInt64 = 0, compressed: UInt64 = 0, swapUsed: UInt64 = 0, pressure: String = "未知", available: Bool = false, swapAvailable: Bool = false) {
        self.total = total; self.used = used; self.compressed = compressed; self.swapUsed = swapUsed; self.pressure = pressure; self.available = available; self.swapAvailable = swapAvailable
    }
}
public struct PowerReading: Codable, Equatable {
    public var source: String, state: String
    public var externalConnected: Bool?
    public var batteryPowerSource: String?
    public var batteryPercent: Double?, healthPercent: Double?, cycleCount: Int?
    public var batteryWatts: Double?, adapterRatedWatts: Double?, inputWatts: Double?, systemLoadWatts: Double?
    public var voltage: Double?, currentAmps: Double?, remainingMinutes: Double?
    public init(source: String = "读取中", state: String = "读取中", batteryPercent: Double? = nil, healthPercent: Double? = nil,
                cycleCount: Int? = nil, batteryWatts: Double? = nil, adapterRatedWatts: Double? = nil, inputWatts: Double? = nil, systemLoadWatts: Double? = nil,
                voltage: Double? = nil, currentAmps: Double? = nil, remainingMinutes: Double? = nil,
                externalConnected: Bool? = nil, batteryPowerSource: String? = nil) {
        self.externalConnected = externalConnected; self.batteryPowerSource = batteryPowerSource
        self.source = source; self.state = state; self.batteryPercent = batteryPercent; self.healthPercent = healthPercent
        self.cycleCount = cycleCount; self.batteryWatts = batteryWatts; self.adapterRatedWatts = adapterRatedWatts; self.inputWatts = inputWatts
        self.systemLoadWatts = systemLoadWatts
        self.voltage = voltage; self.currentAmps = currentAmps; self.remainingMinutes = remainingMinutes
    }
}
public struct NetworkReading: Codable, Equatable {
    public var receivedPerSecond: Double?, sentPerSecond: Double?, interface: String
    public init(receivedPerSecond: Double? = nil, sentPerSecond: Double? = nil, interface: String = "—") {
        self.receivedPerSecond = receivedPerSecond; self.sentPerSecond = sentPerSecond; self.interface = interface
    }
}
public struct DiskReading: Codable, Equatable {
    public var available: UInt64, total: UInt64
    public init(available: UInt64 = 0, total: UInt64 = 0) { self.available = available; self.total = total }
}
public struct SystemReading: Codable, Equatable {
    public var date: Date, cpu: CPUReading, gpu: GPUReading, memory: MemoryReading, power: PowerReading
    public var network: NetworkReading, disk: DiskReading, thermal: String, uptime: TimeInterval
    public init(date: Date = Date(), cpu: CPUReading = .init(), gpu: GPUReading = .init(), memory: MemoryReading = .init(),
                power: PowerReading = .init(), network: NetworkReading = .init(), disk: DiskReading = .init(), thermal: String = "未知", uptime: TimeInterval = 0) {
        self.date = date; self.cpu = cpu; self.gpu = gpu; self.memory = memory; self.power = power
        self.network = network; self.disk = disk; self.thermal = thermal; self.uptime = uptime
    }
}
