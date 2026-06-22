import XCTest
@testable import SymOperateCore

final class SymOperateTests: XCTestCase {
    func testSnapshotTransformMapsImageCoordinatesToDisplaySpace() {
        let transform = SnapshotTransform(
            displayID: 1,
            displayBounds: RectValue(x: 0, y: 0, width: 1440, height: 900),
            imageSize: SizeValue(width: 720, height: 450)
        )

        let point = transform.imageToDisplay(point: PointValue(x: 360, y: 225))
        XCTAssertEqual(point.x, 720, accuracy: 0.01)
        XCTAssertEqual(point.y, 450, accuracy: 0.01)
    }

    func testKeyboardShortcutParsesCommandShortcut() {
        let shortcut = KeyboardShortcut.parse(["cmd", "s"])
        XCTAssertTrue(shortcut.flags.contains(.maskCommand))
        XCTAssertEqual(shortcut.keyCode, 1)
        XCTAssertNil(shortcut.fallbackText)
    }

    func testKeyboardShortcutFallsBackToText() {
        let shortcut = KeyboardShortcut.parse(["ß"])
        XCTAssertNil(shortcut.keyCode)
        XCTAssertEqual(shortcut.fallbackText, "ß")
    }

    func testListDisplaysReturnsAtLeastOneDisplay() {
        let service = ScreenService()
        let displays = service.listDisplays()
        XCTAssertFalse(displays.isEmpty, "Should enumerate at least one display")
        XCTAssertTrue(displays.contains { $0.isMain }, "Should identify the main display")
    }

    func testDisplayInfoCodable() throws {
        let display = DisplayInfo(displayID: 1, bounds: RectValue(x: 0, y: 0, width: 1920, height: 1080), isMain: true)
        let data = try JSONEncoder().encode(display)
        let decoded = try JSONDecoder().decode(DisplayInfo.self, from: data)
        XCTAssertEqual(decoded.displayID, 1)
        XCTAssertEqual(decoded.bounds.width, 1920)
        XCTAssertTrue(decoded.isMain)
    }

    // MARK: - Snapshot security: debugImagePath omitted from JSON when nil

    func testSnapshotJSONOmitsDebugImagePathWhenNil() throws {
        let snapshot = Snapshot(
            id: "test-id",
            createdAt: "2026-01-01T00:00:00.000Z",
            imageBase64PNG: "iVBORw0KGgo=",
            imageSize: SizeValue(width: 100, height: 100),
            displayBounds: RectValue(x: 0, y: 0, width: 1920, height: 1080),
            displayID: 1,
            transform: SnapshotTransform(displayID: 1, displayBounds: RectValue(x: 0, y: 0, width: 1920, height: 1080), imageSize: SizeValue(width: 100, height: 100))
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(snapshot)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNil(json["debugImagePath"], "debugImagePath must be absent when nil")
        XCTAssertNotNil(json["id"])
        XCTAssertNotNil(json["imageBase64PNG"])
        XCTAssertNotNil(json["transform"])
    }

    func testSnapshotJSONIncludesDebugImagePathWhenSet() throws {
        let snapshot = Snapshot(
            id: "test-id",
            createdAt: "2026-01-01T00:00:00.000Z",
            imageBase64PNG: "iVBORw0KGgo=",
            imageSize: SizeValue(width: 100, height: 100),
            displayBounds: RectValue(x: 0, y: 0, width: 1920, height: 1080),
            displayID: 1,
            debugImagePath: "/tmp/snapshots/abc.png",
            transform: SnapshotTransform(displayID: 1, displayBounds: RectValue(x: 0, y: 0, width: 1920, height: 1080), imageSize: SizeValue(width: 100, height: 100))
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(snapshot)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["debugImagePath"] as? String, "/tmp/snapshots/abc.png")
    }

    // MARK: - Snapshot cleanup: 5-minute retention

    func testScreenServiceCleanupRemovesOldPNGs() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-cleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let oldFile = tmpDir.appendingPathComponent("old-snapshot.png")
        let recentFile = tmpDir.appendingPathComponent("recent-snapshot.png")
        let nonPNG = tmpDir.appendingPathComponent("readme.txt")

        try Data("old".utf8).write(to: oldFile)
        let oldAttrs: [FileAttributeKey: Any] = [.creationDate: Date().addingTimeInterval(-600)]
        try FileManager.default.setAttributes(oldAttrs, ofItemAtPath: oldFile.path)

        try Data("recent".utf8).write(to: recentFile)
        try Data("readme".utf8).write(to: nonPNG)

        // ScreenService init triggers cleanupOldSnapshots()
        _ = ScreenService(snapshotDirectory: tmpDir)

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile.path), "Old PNG should be cleaned up")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentFile.path), "Recent PNG should be kept")
        XCTAssertTrue(FileManager.default.fileExists(atPath: nonPNG.path), "Non-PNG files should be kept")
    }

    func testScreenServiceCleanupRetainsPNGsWithinWindow() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-cleanup-recent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let recentFile = tmpDir.appendingPathComponent("fresh.png")
        try Data("fresh".utf8).write(to: recentFile)

        _ = ScreenService(snapshotDirectory: tmpDir)

        XCTAssertTrue(FileManager.default.fileExists(atPath: recentFile.path), "PNGs within the 5-minute window should be kept")
    }
}
