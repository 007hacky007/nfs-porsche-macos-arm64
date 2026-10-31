import Foundation

public enum PipelineEvent: Equatable {
    case step(id: String, title: String)
    case done(URL)
    case error(String)
    case game(version: String)
    case patches(ready: Bool)
    case supported(SupportedCopies)
    case log(String)
}

/// The accepted game releases, as `builder_cli supported` reports them from tools/game_source.py.
/// Sizes are exact byte counts of the extracted files, never of a disc image.
public struct SupportedCopies: Codable, Equatable {
    public struct DataVersion: Codable, Equatable {
        public let version: String
        public let files: Int
        public let bytes: Int64
        public let sha256: String
    }

    public struct Executable: Codable, Equatable {
        public let version: String
        public let name: String
        public let bytes: Int64
        public let sha256: String
    }

    public let summary: String
    public let data: [DataVersion]
    public let executables: [Executable]

    public static let checksumNote = "The checksums are of the extracted files, not of the disc image. "
        + "Any folder, ISO or BIN/CUE image that holds these files works."

    /// The list as plain text for Copy, with exact byte counts.
    public var plainText: String {
        (["\(summary)", "Game data (GameData, FEData, fe.txt and install.txt), one of:"]
            + data.map { "- \($0.version): \($0.files) files, \($0.bytes) bytes, SHA-256 \($0.sha256)" }
            + ["Porsche.exe, one of:"]
            + executables.map { "- \($0.version): \($0.bytes) bytes, SHA-256 \($0.sha256)" }
            + [Self.checksumNote]).joined(separator: "\n")
    }
}

private let eventPrefix = "NFSV-EVENT "

public func parsePipelineLine(_ line: String) -> PipelineEvent {
    guard line.hasPrefix(eventPrefix),
          let data = String(line.dropFirst(eventPrefix.count)).data(using: .utf8),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return .log(line) }

    if let id = obj["step"] as? String, let title = obj["title"] as? String {
        return .step(id: id, title: title)
    }
    if let path = obj["done"] as? String { return .done(URL(fileURLWithPath: path)) }
    if let msg = obj["error"] as? String { return .error(msg) }
    if obj["game"] as? String == "ok", let v = obj["version"] as? String {
        return .game(version: v)
    }
    if let p = obj["patches"] as? String { return .patches(ready: p == "ready") }
    if let s = obj["supported"], let json = try? JSONSerialization.data(withJSONObject: s),
       let copies = try? JSONDecoder().decode(SupportedCopies.self, from: json) {
        return .supported(copies)
    }
    return .log(line)
}
