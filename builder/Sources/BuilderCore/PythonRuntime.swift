import Foundation
import CryptoKit

struct PythonInstallError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func sha256Hex(of url: URL) throws -> String {
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

public enum PythonRuntime {
    // python-build-standalone release 20261026, CPython 3.12.16; hash from that release's SHA256SUMS.
    public static let url = URL(string: "https://github.com/astral-sh/python-build-standalone/releases/download/20261026/cpython-3.12.16%2B20261026-aarch64-apple-darwin-install_only.tar.gz")!
    public static let sha256 = "fbf4afef53c2a6b72bb741bc06d5671a9dfaf87bd84e5aa73ac9b3d0d589f14e"

    public static func isInstalled(_ paths: BuilderPaths) -> Bool {
        FileManager.default.isExecutableFile(atPath: paths.pythonExecutable.path)
    }

    public static func install(_ paths: BuilderPaths,
                               sha256 expected: String = PythonRuntime.sha256,
                               download: (URL, @escaping (Result<URL, Error>) -> Void) -> Void,
                               completion: @escaping (Result<Void, Error>) -> Void) {
        download(url) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let file):
                completion(Result { try finishInstall(paths, archive: file, expected: expected) })
            }
        }
    }

    private static func finishInstall(_ paths: BuilderPaths, archive: URL, expected: String) throws {
        let fm = FileManager.default
        defer { try? fm.removeItem(at: archive) }

        guard try sha256Hex(of: archive) == expected.lowercased() else {
            throw PythonInstallError(message: "The downloaded Python failed its checksum, so it was discarded")
        }

        try fm.createDirectory(at: paths.support, withIntermediateDirectories: true)
        let temp = paths.support.appendingPathComponent(".python.tmp-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: temp) }
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)

        let tar = SystemCommandRunner().run("/usr/bin/tar", ["-xzf", archive.path, "-C", temp.path])
        guard tar.status == 0 else {
            throw PythonInstallError(message: "Could not unpack Python: \(tar.output)")
        }
        let extracted = temp.appendingPathComponent("python")
        guard fm.isExecutableFile(atPath: extracted.appendingPathComponent("bin/python3").path) else {
            throw PythonInstallError(message: "The Python download did not contain python/bin/python3")
        }
        try removeQuarantine(at: extracted)
        if fm.fileExists(atPath: paths.python.path) {
            try fm.removeItem(at: paths.python)
        }
        try fm.moveItem(at: extracted, to: paths.python)
    }
}
