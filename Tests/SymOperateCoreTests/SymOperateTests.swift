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
}
