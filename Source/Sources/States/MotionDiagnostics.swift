import Foundation

enum MotionDiagnostics {
    private static let queue = DispatchQueue(label: "local.states.motion-trace", qos: .utility)
    private static var directory: URL? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--motion-trace"), args.count > index + 1 else { return nil }
        return URL(fileURLWithPath: args[index + 1], isDirectory: true)
    }
    static func save(_ name: String, driver: String, samples: [FrameSample]) {
        guard let directory else { return }
        struct Record: Encodable { let driver: String; let samples: [FrameSample] }
        queue.async {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(Record(driver: driver, samples: samples))
                try data.write(to: directory.appendingPathComponent(name + ".json"), options: .atomic)
            } catch { /* Diagnostics never interrupt the UI. */ }
        }
    }
}
