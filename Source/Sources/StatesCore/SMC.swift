import Foundation
import CSMC

public struct FanReading: Codable, Equatable, Identifiable {
    public var id: Int
    public var name: String
    public var currentRPM: Double?
    public var minimumRPM: Double
    public var maximumRPM: Double
    public var automatic: Bool?
    public var targetRPM: Double?
    public var mode: Int?
    public init(id: Int, name: String, currentRPM: Double?, minimumRPM: Double, maximumRPM: Double, automatic: Bool?, targetRPM: Double? = nil, mode: Int? = nil) {
        self.id=id; self.name=name; self.currentRPM=currentRPM; self.minimumRPM=minimumRPM; self.maximumRPM=maximumRPM; self.automatic=automatic; self.targetRPM=targetRPM; self.mode=mode
    }
}
public struct TemperatureReading: Codable, Equatable {
    public var name: String
    public var celsius: Double
    public init(name: String,celsius: Double) { self.name=name;self.celsius=celsius }
}
public struct SMCReading: Codable, Equatable {
    public var fans: [FanReading]
    public var temperatures: [TemperatureReading]
    public var systemWatts: Double?
    public var status: String
    public init(fans: [FanReading] = [], temperatures: [TemperatureReading] = [], systemWatts: Double? = nil, status: String = "读取中") { self.fans=fans;self.temperatures=temperatures;self.systemWatts=systemWatts;self.status=status }
}
public final class SMCDevice {
    private var connection: UInt32 = 0
    private let lock = NSRecursiveLock()
    private var allTemperatureKeys:[String]?
    private var discoveredReadableCount:Int?
    public var temperatureSensorCount:Int? {lock.lock();defer{lock.unlock()};return discoveredReadableCount}
    public init() { _ = states_smc_open(&connection) }
    deinit { states_smc_close(connection) }
    public static func decode(type: String, bytes: [UInt8]) -> Double? {
        func be(_ n:Int)->UInt64? { guard bytes.count>=n else{return nil};return bytes.prefix(n).reduce(UInt64(0)) {($0<<8)|UInt64($1)} }
        let value: Double?
        switch type {
        case "ui8 ": value=be(1).map {Double($0)}
        case "ui16": value=be(2).map {Double($0)}
        case "ui32": value=be(4).map {Double($0)}
        case "flt ": if bytes.count>=4 { let b=bytes.prefix(4).enumerated().reduce(UInt32(0)) {$0 | UInt32($1.element)<<UInt32($1.offset*8)};value=Double(Float(bitPattern:b)) } else {value=nil}
        case "sp78": value=be(2).map {Double(Int16(bitPattern:UInt16($0)))/256}
        case "fpe2": value=be(2).map {Double($0)/4}
        case "ioft": if bytes.count>=8 {value=Double(bytes.prefix(8).enumerated().reduce(UInt64(0)) {$0 | UInt64($1.element)<<UInt64($1.offset*8)})/65536} else {value=nil}
        default:
            let chars=Array(type.utf8)
            if chars.count==4,chars[0]==115,chars[1]==112,
               let integer=Int(String(UnicodeScalar(chars[2])),radix:16),let fraction=Int(String(UnicodeScalar(chars[3])),radix:16),integer+fraction==15 {
                value=be(2).map{Double(Int16(bitPattern:UInt16($0)))/pow(2,Double(fraction))}
            } else {value=nil}
        }
        return value.flatMap {$0.isFinite ? $0:nil}
    }
    public func number(_ key:String)->Double? {
        lock.lock();defer{lock.unlock()};guard connection != 0 else{return nil}
        var raw=StatesSMCValue();let result=key.withCString {states_smc_read(connection,$0,&raw)};guard result==0 else{return nil}
        let type=String(bytes:[UInt8((raw.type>>24)&255),UInt8((raw.type>>16)&255),UInt8((raw.type>>8)&255),UInt8(raw.type&255)],encoding:.ascii) ?? ""
        let bytes=withUnsafeBytes(of:&raw.bytes){Array($0.prefix(Int(raw.size)))}
        return Self.decode(type:type,bytes:bytes)
    }
    private func discoverTemperatureKeys()->[String] {
        if let allTemperatureKeys {return allTemperatureKeys}
        var count:UInt32=0
        guard connection != 0,states_smc_key_count(connection,&count)==0 else{return []}
        var keys:Set<String>=[]
        for index in 0..<min(count,10000) {
            var key=[CChar](repeating:0,count:5)
            let result=key.withUnsafeMutableBufferPointer{states_smc_temperature_key_at_index(connection,index,$0.baseAddress!)}
            if result==0 {keys.insert(String(cString:key))}
        }
        let sorted=keys.sorted();allTemperatureKeys=sorted;return sorted
    }
    public func snapshot(includeAllTemperatures:Bool = false)->SMCReading {
        lock.lock();defer{lock.unlock()}
        guard let n=number("FNum"), n>=0,n<=8 else{return .init(status:"SMC 无法读取")}
        var fans:[FanReading]=[]
        for id in 0..<Int(n) {
            let p="F\(id)";let mode=(number(p+"Md") ?? number(p+"md")).map(Int.init)
            fans.append(.init(id:id,name:"风扇 \(id+1)",currentRPM:number(p+"Ac"),minimumRPM:number(p+"Mn") ?? 0,maximumRPM:number(p+"Mx") ?? 0,automatic:mode.flatMap { $0 == 0 ? true : $0 == 1 ? false : nil },targetRPM:number(p+"Tg"),mode:mode))
        }
        // Numeric temperature whitelist; names intentionally expose keys rather than invent sensor locations.
        let knownKeys=["Tp01","Tp02","Tp03","Tp04","Tp05","Tp06","Tp07","Tp08","Tp09","Tp0a","Tp0b","Tp0c","Tp0d","Tp0e","Te05","Te09","Te0H","Te0S","Tg05","Tg0D","Tg0L","Tg0T","TC0P","TC0D","TB0T","Ts0P"]
        let keys=includeAllTemperatures ? discoverTemperatureKeys():knownKeys
        let temperatures=keys.compactMap {key -> TemperatureReading? in
            guard let t=number(key),includeAllTemperatures ? (t>=0 && t<=130):(t>0 && t<130) else{return nil}
            return .init(name:key,celsius:t)
        }
        if includeAllTemperatures {discoveredReadableCount=temperatures.count}
        let watts=number("PSTR").flatMap{ $0>=0 && $0<1000 ? $0:nil }
        return .init(fans:fans,temperatures:temperatures,systemWatts:watts,status:"SMC 实时读取")
    }
}
