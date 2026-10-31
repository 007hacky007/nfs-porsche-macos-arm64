import XCTest
@testable import BuilderCore

final class RecordingRunner: CommandRunning {
    var calls: [String] = []
    let results: [String: (status: Int32, output: String)]
    init(results: [String: (status: Int32, output: String)]) { self.results = results }
    func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        calls.append(([executable] + arguments).joined(separator: " "))
        return results[executable] ?? (127, "")
    }
}

final class EnvironmentTests: XCTestCase {
    private var tmp: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory.appendingPathComponent("nfsv-env-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tmp)
    }

    private func write(_ text: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    func testCLTDetectionNeverInvokesShims() {
        let runner = RecordingRunner(results: ["/usr/bin/xcode-select": (0, "/Library/Developer/CommandLineTools\n")])
        let clt = CommandLineTools(runner: runner, fileExists: {
            ["/Library/Developer/CommandLineTools/usr/bin/clang", "/usr/bin/codesign"].contains($0)
        })
        XCTAssertTrue(clt.state().isReady)
        XCTAssertFalse(runner.calls.contains { $0.contains("xcrun") || $0 == "/usr/bin/clang" })
        let missing = CommandLineTools(runner: RecordingRunner(results: ["/usr/bin/xcode-select": (2, "")]), fileExists: { _ in false })
        if case .blocked = missing.state() {} else { XCTFail("expected blocked") }
    }

    func testCLTAcceptsXcodeToolchainAndNeedsCodesign() {
        let runner = RecordingRunner(results: ["/usr/bin/xcode-select": (0, "/Applications/Xcode.app/Contents/Developer\n")])
        let clang = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
        XCTAssertTrue(CommandLineTools(runner: runner, fileExists: { [clang, "/usr/bin/codesign"].contains($0) }).state().isReady)
        if case .blocked = CommandLineTools(runner: runner, fileExists: { $0 == clang }).state() {} else { XCTFail("codesign missing") }
    }

    func testStartInstallRunsXcodeSelect() {
        let runner = RecordingRunner(results: [:])
        CommandLineTools(runner: runner, fileExists: { _ in false }).startInstall()
        XCTAssertEqual(runner.calls, ["/usr/bin/xcode-select --install"])
    }

    func testBuilderPaths() {
        let paths = BuilderPaths(support: URL(fileURLWithPath: "/s"))
        XCTAssertEqual(paths.python.path, "/s/python")
        XCTAssertEqual(paths.pythonExecutable.path, "/s/python/bin/python3")
        XCTAssertEqual(paths.workspace(version: "1.0").path, "/s/1.0")
        XCTAssertEqual(paths.venvPython(version: "1.0").path, "/s/1.0/.venv/bin/python")
    }

    func testStaleOrHalfCopiedWorkspaceIsReplaced() throws {
        let src = tmp.appendingPathComponent("src"), dst = tmp.appendingPathComponent("dst")
        try write("new", to: src.appendingPathComponent("tools/a.py"))
        try write("old", to: dst.appendingPathComponent("tools/a.py"))
        try write("0.9", to: dst.appendingPathComponent(".builder-version"))
        try prepareWorkspace(sources: src, destination: dst, version: "1.0")
        XCTAssertEqual(read(dst.appendingPathComponent("tools/a.py")), "new")
        XCTAssertEqual(read(dst.appendingPathComponent(".builder-version")), "1.0")

        // No marker (crash mid-copy) is also replaced.
        try fm.removeItem(at: dst.appendingPathComponent(".builder-version"))
        try write("junk", to: dst.appendingPathComponent("tools/a.py"))
        try prepareWorkspace(sources: src, destination: dst, version: "1.0")
        XCTAssertEqual(read(dst.appendingPathComponent("tools/a.py")), "new")

        // Same version with marker: nothing is copied.
        try write("kept", to: dst.appendingPathComponent("tools/a.py"))
        try prepareWorkspace(sources: src, destination: dst, version: "1.0")
        XCTAssertEqual(read(dst.appendingPathComponent("tools/a.py")), "kept")
        let siblings = try fm.contentsOfDirectory(atPath: tmp.path).sorted()
        XCTAssertEqual(siblings, ["dst", "src"])
    }

    func testWorkspaceCopiesOnlyBundledEntries() throws {
        let src = tmp.appendingPathComponent("repo"), dst = tmp.appendingPathComponent("ws")
        for entry in ["build.sh", "requirements.txt", "tools/a.py", "runtime/r.c", "launcher/l.c",
                      "gen/big.bin", "out/o.bin", ".venv/bin/python", "tools/__pycache__/x.pyc",
                      "runtime/__pycache__/y.pyc", "README.md"] {
            try write("x", to: src.appendingPathComponent(entry))
        }
        XCTAssertEqual(bundledSourceEntries, ["build.sh", "requirements.txt", "tools", "runtime", "launcher", "third_party"])
        try prepareWorkspace(sources: src, destination: dst, version: "2")
        let top = try fm.contentsOfDirectory(atPath: dst.path).sorted()
        XCTAssertEqual(top, [".builder-version", "build.sh", "launcher", "requirements.txt", "runtime", "tools"])
        XCTAssertFalse(fm.fileExists(atPath: dst.appendingPathComponent("tools/__pycache__").path))
        XCTAssertFalse(fm.fileExists(atPath: dst.appendingPathComponent("runtime/__pycache__").path))
        XCTAssertTrue(fm.fileExists(atPath: dst.appendingPathComponent("tools/a.py").path))
    }

    func testPythonPinLooksSane() {
        XCTAssertTrue(PythonRuntime.url.absoluteString.hasPrefix("https://github.com/astral-sh/python-build-standalone/releases/download/"))
        XCTAssertTrue(PythonRuntime.url.absoluteString.hasSuffix("aarch64-apple-darwin-install_only.tar.gz"))
        XCTAssertEqual(PythonRuntime.sha256.count, 64)
    }

    private func installResult(_ paths: BuilderPaths, sha: String? = nil,
                               download: (URL, @escaping (Result<URL, Error>) -> Void) -> Void) -> Result<Void, Error> {
        var result: Result<Void, Error>?
        let done = expectation(description: "install")
        PythonRuntime.install(paths, sha256: sha ?? PythonRuntime.sha256, download: download) {
            result = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
        return result!
    }

    func testPythonInstallRejectsBadChecksumAndLeavesNothing() throws {
        let support = tmp.appendingPathComponent("support")
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        let paths = BuilderPaths(support: support)
        let bad = tmp.appendingPathComponent("bad.tgz")
        try write("not python", to: bad)
        let result = installResult(paths) { _, done in done(.success(bad)) }
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertTrue("\(error.localizedDescription)".lowercased().contains("checksum"))
        XCTAssertFalse(fm.fileExists(atPath: paths.python.path))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: support.path), [])
        XCTAssertFalse(PythonRuntime.isInstalled(paths))
    }

    func testPythonInstallReportsDownloadFailure() throws {
        let support = tmp.appendingPathComponent("support")
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        let paths = BuilderPaths(support: support)
        let result = installResult(paths) { _, done in done(.failure(URLError(.notConnectedToInternet))) }
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: support.path), [])
    }

    func testPythonInstallExtractsVerifiedArchive() throws {
        let support = tmp.appendingPathComponent("support")
        let paths = BuilderPaths(support: support)
        let stage = tmp.appendingPathComponent("stage")
        let exe = stage.appendingPathComponent("python/bin/python3")
        try write("#!/bin/sh\n", to: exe)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        let archive = tmp.appendingPathComponent("py.tar.gz")
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-czf", archive.path, "-C", stage.path, "python"]
        try tar.run()
        tar.waitUntilExit()
        let sha = try sha256Hex(of: archive)
        let result = installResult(paths, sha: sha) { _, done in done(.success(archive)) }
        guard case .success = result else { return XCTFail("\(result)") }
        XCTAssertTrue(PythonRuntime.isInstalled(paths))
        XCTAssertTrue(fm.isExecutableFile(atPath: paths.pythonExecutable.path))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: support.path), ["python"])
    }

    func testBuildToolsReadyOnlyWhenRequirementsHashMatches() throws {
        let paths = BuilderPaths(support: tmp)
        let ws = paths.workspace(version: "1")
        let req = ws.appendingPathComponent("requirements.txt")
        try write("numpy\n", to: req)
        if case .automatic = buildToolsCheck(paths: paths, version: "1") {} else { XCTFail("no venv yet") }
        try write("", to: paths.venvPython(version: "1"))
        try write(try sha256Hex(of: req) + "\n", to: ws.appendingPathComponent(".venv/.build-requirements-sha256"))
        XCTAssertTrue(buildToolsCheck(paths: paths, version: "1").isReady)
        try write("numpy\nscipy\n", to: req)
        XCTAssertFalse(buildToolsCheck(paths: paths, version: "1").isReady)
    }

    func testRemoveQuarantineRecursive() throws {
        let dir = tmp.appendingPathComponent("q")
        let file = dir.appendingPathComponent("sub/f.txt")
        try write("x", to: file)
        let value = Array("0081;00000000;Test;".utf8)
        for url in [dir, file] {
            XCTAssertEqual(setxattr(url.path, "com.apple.quarantine", value, value.count, 0, 0), 0)
        }
        try removeQuarantine(at: dir)
        for url in [dir, file] {
            errno = 0
            XCTAssertEqual(getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0), -1)
            XCTAssertEqual(errno, ENOATTR)
        }
        // No attribute present: still fine.
        try removeQuarantine(at: dir)
    }
}
