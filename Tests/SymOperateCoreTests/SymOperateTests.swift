// swiftlint:disable:next for_where
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
}
