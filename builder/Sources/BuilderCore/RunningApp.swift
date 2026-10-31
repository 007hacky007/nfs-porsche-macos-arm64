import AppKit

/// True while the game (bundle id from tools/package.py) is running.
public func isNFSVRunning() -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: "org.nfsv.local").isEmpty
}
