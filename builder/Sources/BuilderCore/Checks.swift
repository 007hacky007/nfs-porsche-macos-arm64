import Foundation

public enum CheckID: CaseIterable {
    case mac, commandLineTools, buildTools, patches, gameCopy, destination, diskSpace
}

/// Grey (checking), green (ready), amber (automatic), red (blocked).
public enum CheckState: Equatable {
    case checking(String)
    case ready(String)
    case automatic(String)
    case blocked(String)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

public func canBuild(_ states: [CheckID: CheckState]) -> Bool {
    CheckID.allCases.allSatisfy { id in
        switch states[id] {
        case .ready?, .automatic?: return true
        default: return false
        }
    }
}

public func macCheck(isAppleSilicon: Bool, version: OperatingSystemVersion) -> CheckState {
    guard isAppleSilicon else {
        return .blocked("NFSV needs a Mac with Apple Silicon")
    }
    guard version.majorVersion >= 11 else {
        return .blocked("NFSV needs macOS 11 or newer")
    }
    return .ready("Apple Silicon, macOS \(version.majorVersion).\(version.minorVersion)")
}

public let requiredFreeBytes: Int64 = 3_000_000_000

public func diskSpaceCheck(available: Int64) -> CheckState {
    let gb = { (b: Int64) in String(format: "%.1f GB", Double(b) / 1_000_000_000) }
    if available >= requiredFreeBytes {
        return .ready("\(gb(available)) free")
    }
    return .blocked("Only \(gb(available)) free, \(gb(requiredFreeBytes)) needed")
}
