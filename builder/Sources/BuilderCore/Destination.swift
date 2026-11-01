import Foundation

public let defaultDestination = URL(fileURLWithPath: "/Applications")

public struct InstallError: LocalizedError {
    public let message: String
    /// Underlying error text, for the log.
    public var details: String? = nil
    public var errorDescription: String? { message }
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
    do {
        if fm.fileExists(atPath: staging.path) { try fm.removeItem(at: staging) }
        try fm.copyItem(at: built, to: staging)
        try removeQuarantine(fromBuiltApp: staging)
        var final = target
        if fm.fileExists(atPath: target.path) {
            final = try fm.replaceItemAt(target, withItemAt: staging) ?? target
        } else {
            try fm.moveItem(at: staging, to: target)
        }
        guard fm.fileExists(atPath: final.appendingPathComponent("Contents/Info.plist").path) else {
            throw InstallError(message: "The installed app is incomplete.")
        }
        return final
    } catch {
        try? fm.removeItem(at: staging)
        throw InstallError(
            message: "Could not install NFSV into \(directory.lastPathComponent). Choose another folder and try again.",
            details: String(describing: error))
    }
}
