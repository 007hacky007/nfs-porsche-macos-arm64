import Foundation

public let appName = "NFSV.app"

public func isAppBundle(_ url: URL) -> Bool {
    url.pathExtension.lowercased() == "app"
}

/// The NFSV.app an update replaces: the one in the saved destination, else in /Applications.
/// Whether its game can be reused is checked like any chosen game copy (`builder_cli check-game`).
public func findInstalledApp(destination: URL?, fallback: URL = defaultDestination) -> URL? {
    for directory in [destination, fallback].compactMap({ $0 }) {
        let app = directory.appendingPathComponent(appName)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: app.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return app
        }
    }
    return nil
}

/// The Builder version that built `app` (Info.plist NFSBuilderVersion), nil for a Terminal build or an older app.
public func builderStamp(ofApp app: URL) -> String? {
    guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let stamp = plist["NFSBuilderVersion"] as? String, !stamp.isEmpty
    else { return nil }
    return stamp
}

public func buildButtonTitle(game: URL?, oldStamp: String?, newVersion: String) -> String {
    guard let game = game, isAppBundle(game) else { return "Build NFSV.app" }
    guard let old = oldStamp else { return "Update NFSV.app" }
    return "Update NFSV.app (\(old) -> \(newVersion))"
}

/// The game row for a game reused from an app: the current one in `destination`, or another named app.
public func appGameMessage(version: String, app: URL, destination: URL) -> String {
    let current = app.standardizedFileURL == destination.appendingPathComponent(appName).standardizedFileURL
    return "\(version), using the game inside \(current ? "the current NFSV.app" : app.path)"
}
