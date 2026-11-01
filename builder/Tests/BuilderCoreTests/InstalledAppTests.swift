import XCTest
@testable import BuilderCore

final class InstalledAppTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("installed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeApp(in directory: URL, stamp: String?) throws -> URL {
        let app = directory.appendingPathComponent("NFSV.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/Resources/Game"),
                                                withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundleIdentifier": "org.nfsv.local"]
        if let stamp = stamp { plist["NFSBuilderVersion"] = stamp }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    func testFindsTheAppInTheSavedDestinationThenTheFallback() throws {
        let saved = root.appendingPathComponent("Games")
        let fallback = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: saved, withIntermediateDirectories: true)
        XCTAssertNil(findInstalledApp(destination: saved, fallback: fallback))
        let inFallback = try makeApp(in: fallback, stamp: nil)
        XCTAssertEqual(findInstalledApp(destination: saved, fallback: fallback)?.path, inFallback.path)
        XCTAssertEqual(findInstalledApp(destination: nil, fallback: fallback)?.path, inFallback.path)
        let inSaved = try makeApp(in: saved, stamp: "1.2.0")
        XCTAssertEqual(findInstalledApp(destination: saved, fallback: fallback)?.path, inSaved.path)
    }

    func testReadsTheBuilderStampAndNamesTheButton() throws {
        let stamped = try makeApp(in: root.appendingPathComponent("a"), stamp: "1.2.0")
        let terminal = try makeApp(in: root.appendingPathComponent("b"), stamp: nil)
        XCTAssertEqual(builderStamp(ofApp: stamped), "1.2.0")
        XCTAssertNil(builderStamp(ofApp: terminal))
        XCTAssertNil(builderStamp(ofApp: root.appendingPathComponent("missing.app")))
        XCTAssertEqual(buildButtonTitle(game: stamped, oldStamp: "1.2.0", newVersion: "1.3.0"),
                       "Update NFSV.app (1.2.0 -> 1.3.0)")
        XCTAssertEqual(buildButtonTitle(game: terminal, oldStamp: nil, newVersion: "1.3.0"), "Update NFSV.app")
        XCTAssertEqual(buildButtonTitle(game: URL(fileURLWithPath: "/Games/NFS5"), oldStamp: nil, newVersion: "1.3.0"),
                       "Build NFSV.app")
        XCTAssertEqual(buildButtonTitle(game: nil, oldStamp: nil, newVersion: "1.3.0"), "Build NFSV.app")
    }

    func testGameRowNamesTheCurrentApp() {
        let destination = URL(fileURLWithPath: "/Applications")
        XCTAssertEqual(appGameMessage(version: "USA v3.2", app: destination.appendingPathComponent("NFSV.app"), destination: destination),
                       "USA v3.2, using the game inside the current NFSV.app")
        XCTAssertEqual(appGameMessage(version: "USA v3.4", app: URL(fileURLWithPath: "/Volumes/Old/NFSV.app"), destination: destination),
                       "USA v3.4, using the game inside /Volumes/Old/NFSV.app")
    }

    /// An update installs over the app it read its game from; the old app stays until the new one is in place.
    func testUpdateKeepsTheOldAppUntilTheNewOneIsComplete() throws {
        let destination = root.appendingPathComponent("Applications")
        let old = try makeApp(in: destination, stamp: "1.2.0")
        try "old".write(to: old.appendingPathComponent("Contents/Resources/Game/marker"), atomically: true, encoding: .utf8)
        let incomplete = root.appendingPathComponent("build/missing/NFSV.app")
        XCTAssertThrowsError(try installApp(incomplete, into: destination, isRunning: { false }))
        XCTAssertEqual(builderStamp(ofApp: old), "1.2.0")
        XCTAssertEqual(try String(contentsOf: old.appendingPathComponent("Contents/Resources/Game/marker"), encoding: .utf8), "old")
        let built = try makeApp(in: root.appendingPathComponent("build/out"), stamp: "1.3.0")
        let installed = try installApp(built, into: destination, isRunning: { false })
        XCTAssertEqual(builderStamp(ofApp: installed), "1.3.0")
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.appendingPathComponent("Contents/Resources/Game/marker").path))
        XCTAssertEqual(builderStamp(ofApp: built), "1.3.0")
    }
}
