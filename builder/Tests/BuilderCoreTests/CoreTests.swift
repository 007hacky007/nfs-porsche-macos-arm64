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
        if case .blocked = macCheck(isAppleSilicon: true, version: .init(majorVersion: 11, minorVersion: 7, patchVersion: 0)) {} else { XCTFail() }
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
    func testProgressAndDisk() {
        XCTAssertEqual(progressFraction(atStart: "extract"), 0)
        XCTAssertEqual(progressFraction(atStart: "compile"), 0.60, accuracy: 0.001)
        if case .blocked = diskSpaceCheck(available: 2_999_999_999) {} else { XCTFail() }
        if case .ready = diskSpaceCheck(available: 3_000_000_000) {} else { XCTFail() }
    }
}
