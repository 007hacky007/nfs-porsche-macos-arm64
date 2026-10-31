import XCTest
@testable import BuilderCore

final class CoreTests: XCTestCase {
    func testBuildBlockedWhileAnyRowRedOrChecking() {
        var s = Dictionary(uniqueKeysWithValues: CheckID.allCases.map { ($0, CheckState.ready("ok")) })
        XCTAssertTrue(canBuild(s))
        s[.patches] = .automatic("downloaded during the build"); XCTAssertTrue(canBuild(s))
        s[.gameCopy] = .checking("checking"); XCTAssertFalse(canBuild(s))
        s[.gameCopy] = .blocked("choose"); XCTAssertFalse(canBuild(s))
        s.removeValue(forKey: .diskSpace); s[.gameCopy] = .ready("ok"); XCTAssertFalse(canBuild(s))
    }
    func testMacCheck() {
        XCTAssertEqual(macCheck(isAppleSilicon: true, version: .init(majorVersion: 12, minorVersion: 0, patchVersion: 0)).isReady, true)
        if case .blocked = macCheck(isAppleSilicon: false, version: .init(majorVersion: 15, minorVersion: 0, patchVersion: 0)) {} else { XCTFail() }
        XCTAssertEqual(macCheck(isAppleSilicon: true, version: .init(majorVersion: 11, minorVersion: 7, patchVersion: 0)),
                       .blocked("NFSV Builder needs macOS 12 or newer. On macOS 11, build from Terminal."))
    }
    func testParsePipelineLines() {
        XCTAssertEqual(parsePipelineLine(#"NFSV-EVENT {"step":"compile","title":"Compiling native ARM64 code"}"#), .step(id: "compile", title: "Compiling native ARM64 code"))
        XCTAssertEqual(parsePipelineLine(#"NFSV-EVENT {"done":"/tmp/w/out/NFSV.app"}"#), .done(URL(fileURLWithPath: "/tmp/w/out/NFSV.app")))
        XCTAssertEqual(parsePipelineLine(#"NFSV-EVENT {"error":"bad"}"#), .error("bad"))
        XCTAssertEqual(parsePipelineLine(#"NFSV-EVENT {"game":"ok","version":"USA v3.2"}"#), .game(version: "USA v3.2"))
        XCTAssertEqual(parsePipelineLine(#"NFSV-EVENT {"patches":"missing"}"#), .patches(ready: false))
        XCTAssertEqual(parsePipelineLine("NFSV-EVENT {broken"), .log("NFSV-EVENT {broken"))
        XCTAssertEqual(parsePipelineLine("plain"), .log("plain"))
    }
    func testParseSupportedCopies() {
        let line = #"NFSV-EVENT {"supported": {"summary": "Choose a folder.", "data": [{"version": "USA v3.2", "files": 1568, "bytes": 528771197, "sha256": "e5b1"}], "executables": [{"version": "USA v3.2 disc loader", "name": "Porsche.exe", "bytes": 249119, "sha256": "6c86"}]}}"#
        XCTAssertEqual(parsePipelineLine(line), .supported(SupportedCopies(
            summary: "Choose a folder.",
            data: [.init(version: "USA v3.2", files: 1568, bytes: 528_771_197, sha256: "e5b1")],
            executables: [.init(version: "USA v3.2 disc loader", name: "Porsche.exe", bytes: 249_119, sha256: "6c86")])))
        guard case let .supported(copies) = parsePipelineLine(line) else { return XCTFail() }
        XCTAssertEqual(copies.plainText, """
            Choose a folder.
            Game data (GameData, FEData, fe.txt and install.txt), one of:
            - USA v3.2: 1568 files, 528771197 bytes, SHA-256 e5b1
            Porsche.exe, one of:
            - USA v3.2 disc loader: 249119 bytes, SHA-256 6c86
            \(SupportedCopies.checksumNote)
            """)
        let broken = #"NFSV-EVENT {"supported": {"summary": "x"}}"#
        XCTAssertEqual(parsePipelineLine(broken), .log(broken))
    }
    func testGameCheckDetailsKeepMessageAndDetectedChecksums() {
        let log = ["", "Detected game-data fingerprint: 2b0e (4 files)", "  ", "Detected Porsche.exe SHA-256: 6c86"]
        XCTAssertEqual(gameCheckDetails(message: "This copy's game data does not match.", log: log), """
            This copy's game data does not match.
            Detected game-data fingerprint: 2b0e (4 files)
            Detected Porsche.exe SHA-256: 6c86
            """)
        XCTAssertEqual(gameCheckDetails(message: "Bad.", log: []), "Bad.")
    }
    func testProgressAndDisk() {
        XCTAssertEqual(progressFraction(atStart: "extract"), 0)
        XCTAssertEqual(progressFraction(atStart: "compile"), 0.60, accuracy: 0.001)
        if case .blocked = diskSpaceCheck(available: 2_999_999_999) {} else { XCTFail() }
        if case .ready = diskSpaceCheck(available: 3_000_000_000) {} else { XCTFail() }
    }
}
