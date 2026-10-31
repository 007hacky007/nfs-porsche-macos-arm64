import XCTest
import BuilderCore

/// Drives the same BuilderCore calls as the Builder window against a real game copy.
/// Skipped unless NFSV_E2E_GAME points at a game folder, .iso, .bin or .cue. Downloads the
/// private Python and the packages, so it needs the network; set NFSV_CACHE_DIR to reuse a
/// verified patch cache.
final class EndToEndTests: XCTestCase {
    private let fm = FileManager.default
    private let version = "0.0.0-e2e"

    func testFullBuildFromWindowCalls() throws {
        guard let gamePath = ProcessInfo.processInfo.environment["NFSV_E2E_GAME"] else {
            throw XCTSkip("set NFSV_E2E_GAME to run the end-to-end build")
        }
        let game = URL(fileURLWithPath: gamePath)
        let tmp = fm.temporaryDirectory.appendingPathComponent("nfsv-e2e-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let paths = BuilderPaths(support: tmp.appendingPathComponent("support"))
        let started = Date()
        func mark(_ what: String) { print("E2E \(String(format: "%7.1f", Date().timeIntervalSince(started))) s: \(what)") }

        try prepareWorkspace(sources: repositoryRoot(), destination: paths.workspace(version: version), version: version)
        mark("workspace prepared")

        let installed = expectation(description: "python")
        var installResult: Result<Void, Error>?
        PythonRuntime.install(paths, download: { url, done in
            URLSession.shared.downloadTask(with: url) { file, response, error in
                if let file = file, (response as? HTTPURLResponse)?.statusCode == 200 {
                    done(.success(file))
                } else {
                    done(.failure(error ?? URLError(.badServerResponse)))
                }
            }.resume()
        }, completion: { result in
            installResult = result
            installed.fulfill()
        })
        wait(for: [installed], timeout: 600)
        try XCTUnwrap(installResult).get()
        XCTAssertTrue(PythonRuntime.isInstalled(paths))
        mark("python installed")

        let setup = try run(.setup(paths: paths, version: version), timeout: 900)
        XCTAssertEqual(setup.status, 0, setup.lines.suffix(30).joined(separator: "\n"))
        XCTAssertEqual(buildToolsCheck(paths: paths, version: version), .ready("Installed"))
        mark("setup done")

        let check = try run(.checkGame(paths: paths, version: version, game: game), timeout: 900)
        XCTAssertEqual(check.status, 0, check.lines.suffix(30).joined(separator: "\n"))
        let detected = check.events.compactMap { event -> String? in
            if case let .game(version) = event { return version }
            return nil
        }
        XCTAssertEqual(detected.count, 1, "expected one game event")
        mark("game checked: \(detected.first ?? "none")")

        // First build: cancel once compiling has started, then nothing from that run may survive.
        let workspace = paths.workspace(version: version).path
        var group: pid_t = 0
        var clangSeen = false
        let cancelled = try run(.build(paths: paths, version: version, game: game), timeout: 3600) { event, runner in
            guard case .step(id: "compile", _) = event else { return }
            group = Self.processGroup(matching: { $0.contains(workspace) && $0.contains("build_app.py") }) ?? 0
            // Give compile.py a moment to launch clang so the cancel really has children to stop.
            let deadline = Date().addingTimeInterval(30)
            while Date() < deadline && !clangSeen {
                clangSeen = Self.processes(inGroup: group).contains { $0.contains("clang") }
                if !clangSeen { usleep(200_000) }
            }
            mark("compile started (group \(group), clang running: \(clangSeen)), cancelling")
            runner.cancel()
        }
        mark("cancelled build exited with \(cancelled.status)")
        XCTAssertNotEqual(group, 0, "found the build's process group")
        XCTAssertTrue(clangSeen, "clang was running when the build was cancelled")
        XCTAssertNotEqual(cancelled.status, 0)
        let deadline = Date().addingTimeInterval(6)
        var leftovers: [String] = []
        repeat {
            leftovers = Self.pgrep("clang").union(Self.pgrep("build_app")).compactMap { pid in
                Self.processGroup(of: pid) == group ? "\(pid)" : nil
            }.sorted()
            if leftovers.isEmpty { break }
            usleep(100_000)
        } while Date() < deadline
        XCTAssertEqual(leftovers, [], "clang or build_app processes from the cancelled build survived")
        mark("no clang or build_app left from the cancelled run")

        // Second build runs to the end and installs.
        let full = try run(.build(paths: paths, version: version, game: game), timeout: 3600)
        let done = full.events.compactMap { event -> URL? in
            if case let .done(url) = event { return url }
            return nil
        }
        XCTAssertEqual(full.status, 0, full.lines.suffix(40).joined(separator: "\n"))
        XCTAssertFalse(full.events.contains { if case .error = $0 { return true } else { return false } })
        let built = try XCTUnwrap(done.first)
        let steps = full.events.compactMap { event -> String? in
            if case let .step(id, _) = event { return id }
            return nil
        }
        mark("full build done, steps \(steps.joined(separator: " ")), \(full.lines.count) lines")

        let destination = tmp.appendingPathComponent("Applications")
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let app = try installApp(built, into: destination, isRunning: { false })
        XCTAssertEqual(app.lastPathComponent, "NFSV.app")
        XCTAssertTrue(fm.fileExists(atPath: app.appendingPathComponent("Contents/Info.plist").path))
        let verify = SystemCommandRunner().run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        XCTAssertEqual(verify.status, 0, verify.output)
        mark("installed and codesign verified: \(app.path)")
    }

    // MARK: - Helpers

    private struct Run {
        var events: [PipelineEvent] = []
        var lines: [String] = []
        var status: Int32 = -1
    }

    private func run(_ runner: PipelineRunner, timeout: TimeInterval,
                     onEvent: ((PipelineEvent, PipelineRunner) -> Void)? = nil) throws -> Run {
        var result = Run()
        let exited = expectation(description: "exit")
        try runner.start(onEvent: { event in
            result.events.append(event)
            switch event {
            case let .log(line): result.lines.append(line)
            case let .step(_, title): result.lines.append(title)
            case let .error(message): result.lines.append("Error: \(message)")
            default: break
            }
            onEvent?(event, runner)
        }, onExit: { status in
            result.status = status
            exited.fulfill()
        })
        wait(for: [exited], timeout: timeout)
        return result
    }

    private func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            url.deleteLastPathComponent()
            if fm.fileExists(atPath: url.appendingPathComponent("build.sh").path) { return url }
        }
        throw XCTSkip("repository root not found")
    }

    private static func ps() -> [(pid: pid_t, pgid: pid_t, command: String)] {
        let output = SystemCommandRunner().run("/bin/ps", ["-axww", "-o", "pid=,pgid=,command="]).output
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = pid_t(parts[0]), let pgid = pid_t(parts[1]) else { return nil }
            return (pid, pgid, String(parts[2]))
        }
    }

    private static func processGroup(matching predicate: (String) -> Bool) -> pid_t? {
        ps().first { predicate($0.command) }?.pgid
    }

    private static func processGroup(of pid: pid_t) -> pid_t? {
        ps().first { $0.pid == pid }?.pgid
    }

    private static func processes(inGroup group: pid_t) -> [String] {
        ps().filter { $0.pgid == group }.map(\.command)
    }

    private static func pgrep(_ pattern: String) -> Set<pid_t> {
        let output = SystemCommandRunner().run("/usr/bin/pgrep", ["-f", pattern]).output
        return Set(output.split(separator: "\n").compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) })
    }
}
