import Foundation

public let bundledSourceEntries = ["build.sh", "requirements.txt", "tools", "runtime", "launcher", "third_party"]

public struct BuilderPaths {
    public let support: URL

    public init(support: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/NFSV Builder")) {
        self.support = support
    }

    public var python: URL { support.appendingPathComponent("python") }
    public var pythonExecutable: URL { python.appendingPathComponent("bin/python3") }

    public func workspace(version: String) -> URL {
        support.appendingPathComponent(version)
    }

    public func venvPython(version: String) -> URL {
        workspace(version: version).appendingPathComponent(".venv/bin/python")
    }
}

private let versionMarker = ".builder-version"

/// Copies the pipeline sources into `destination`. A destination whose marker
/// matches `version` is left alone; anything else is replaced atomically.
public func prepareWorkspace(sources: URL, destination: URL, version: String) throws {
    let fm = FileManager.default
    let marker = destination.appendingPathComponent(versionMarker)
    if let current = try? String(contentsOf: marker, encoding: .utf8), current == version {
        return
    }

    let parent = destination.deletingLastPathComponent()
    try fm.createDirectory(at: parent, withIntermediateDirectories: true)
    let temp = parent.appendingPathComponent(".\(destination.lastPathComponent).tmp-\(UUID().uuidString)")
    do {
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        for entry in bundledSourceEntries {
            let from = sources.appendingPathComponent(entry)
            guard fm.fileExists(atPath: from.path) else { continue }
            try fm.copyItem(at: from, to: temp.appendingPathComponent(entry))
        }
        try removePycache(in: temp)
        try removeQuarantine(at: temp)
        try version.write(to: temp.appendingPathComponent(versionMarker), atomically: true, encoding: .utf8)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: temp, to: destination)
    } catch {
        try? fm.removeItem(at: temp)
        throw error
    }
}

private func removePycache(in root: URL) throws {
    let fm = FileManager.default
    guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return }
    var found: [URL] = []
    for case let url as URL in walker where url.lastPathComponent == "__pycache__" {
        found.append(url)
        walker.skipDescendants()
    }
    for url in found { try fm.removeItem(at: url) }
}

/// Ready when the private Python is installed and the workspace venv was built from the
/// current requirements.txt. Otherwise red: roughly 90 MB (Python archive plus packages) to fetch.
public func buildToolsCheck(paths: BuilderPaths, version: String) -> CheckState {
    let workspace = paths.workspace(version: version)
    guard PythonRuntime.isInstalled(paths),
          FileManager.default.fileExists(atPath: paths.venvPython(version: version).path),
          let requirements = try? sha256Hex(of: workspace.appendingPathComponent("requirements.txt")),
          let recorded = try? String(contentsOf: workspace.appendingPathComponent(".venv/.build-requirements-sha256"), encoding: .utf8),
          recorded.trimmingCharacters(in: .whitespacesAndNewlines) == requirements
    else { return .blocked("about 90 MB download") }
    return .ready("Installed")
}
