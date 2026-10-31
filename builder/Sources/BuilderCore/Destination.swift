import Foundation

public let defaultDestination = URL(fileURLWithPath: "/Applications")

struct InstallError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

public func destinationCheck(_ directory: URL) -> CheckState {
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir)
    if exists, isDir.boolValue, FileManager.default.isWritableFile(atPath: directory.path) {
        return .ready(directory.path)
    }
    return .blocked("Choose a folder you can write to")
}

/// Copies `built` next to the final location, then swaps it in so the old app survives any failure.
public func installApp(_ built: URL, into directory: URL, isRunning: () -> Bool) throws -> URL {
    if isRunning() { throw InstallError(message: "Quit NFSV first, then try again.") }
    let fm = FileManager.default
    let target = directory.appendingPathComponent("NFSV.app")
    let staging = directory.appendingPathComponent(".NFSV.app.installing")
    if fm.fileExists(atPath: staging.path) { try fm.removeItem(at: staging) }
    do {
        try fm.copyItem(at: built, to: staging)
        try removeQuarantine(at: staging)
        if fm.fileExists(atPath: target.path) {
            _ = try fm.replaceItemAt(target, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: target)
        }
    } catch {
        try? fm.removeItem(at: staging)
        throw error
    }
    return target
}
