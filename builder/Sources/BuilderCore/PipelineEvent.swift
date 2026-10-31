import Foundation

public enum PipelineEvent: Equatable {
    case step(id: String, title: String)
    case done(URL)
    case error(String)
    case game(version: String)
    case patches(ready: Bool)
    case log(String)
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
    return .log(line)
}
