import XCTest
@testable import SymOperateCore

final class SmokeTests: XCTestCase {
    private let controller = AutomationController()

    // MARK: - Snapshot

    func testSnapshotReturnsValidImageOrPermissionDenied() throws {
        do {
            let snapshot = try controller.snapshot()
            XCTAssertFalse(snapshot.id.isEmpty)
            XCTAssertFalse(snapshot.imageBase64PNG.isEmpty)
            XCTAssertGreaterThan(snapshot.imageSize.width, 0)
            XCTAssertGreaterThan(snapshot.imageSize.height, 0)
            XCTAssertGreaterThan(snapshot.displayBounds.width, 0)
            XCTAssertGreaterThan(snapshot.displayBounds.height, 0)
        } catch let error as AutomationError {
            if case .permissionDenied = error {
                XCTAssertTrue(error.localizedDescription.lowercased().contains("screen") || error.localizedDescription.lowercased().contains("recording"))
            } else {
                XCTFail("Unexpected error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Query UI

    func testQueryUIReturnsTreeOrPermissionDenied() throws {
        do {
            let query = try controller.queryUI(maxDepth: 2, maxNodes: 50)
            XCTAssertFalse(query.snapshot.id.isEmpty)
            XCTAssertNotNil(query.app)
            XCTAssertGreaterThanOrEqual(query.nodes.count, 0)
        } catch let error as AutomationError {
            switch error {
            case .permissionDenied, .operationFailed, .unavailable, .invalidArgument:
                break
            default:
                XCTFail("Unexpected error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Click

    func testClickDoesNotCrash() throws {
        do {
            _ = try controller.click(x: 10, y: 10)
        } catch let error as AutomationError {
            switch error {
            case .permissionDenied, .operationFailed, .unavailable:
                break
            default:
                XCTFail("Unexpected error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Type text

    func testTypeTextDoesNotCrash() throws {
        do {
            _ = try controller.typeText("hello")
        } catch let error as AutomationError {
            switch error {
            case .permissionDenied, .operationFailed, .unavailable:
                break
            default:
                XCTFail("Unexpected error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Press keys

    func testPressKeysDoesNotCrash() throws {
        do {
            _ = try controller.pressKeys(["return"])
        } catch let error as AutomationError {
            switch error {
            case .permissionDenied, .operationFailed, .unavailable, .invalidArgument:
                break
            default:
                XCTFail("Unexpected error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Wait for

    func testWaitForThrowsWhenConditionNotMet() throws {
        XCTAssertThrowsError(
            try controller.waitFor(text: "XYZ_NONEXISTENT_123", app: nil, timeoutSeconds: 1)
        ) { error in
            guard let autoError = error as? AutomationError else {
                XCTFail("Expected AutomationError, got \(type(of: error))")
                return
            }
            if case .operationFailed = autoError {
                XCTAssertTrue(autoError.localizedDescription.contains("1 seconds") || autoError.localizedDescription.contains("within"))
            } else {
                XCTFail("Expected operationFailed, got \(autoError)")
            }
        }
    }

    // MARK: - Doctor

    func testDoctorOutputsContainProbes() throws {
        let repoRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let binary = repoRoot
            .appendingPathComponent(".build")
            .appendingPathComponent("debug")
            .appendingPathComponent("symoperate")
        let process = Process()
        process.executableURL = binary
        process.arguments = ["doctor"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("doctor did not emit valid JSON")
            return
        }

        XCTAssertNotNil(json["screenshotProbe"], "Expected screenshotProbe in doctor output")
        XCTAssertNotNil(json["accessibilityProbe"], "Expected accessibilityProbe in doctor output")

        if let screenshotProbe = json["screenshotProbe"] as? [String: Any] {
            XCTAssertNotNil(screenshotProbe["ok"])
            XCTAssertNotNil(screenshotProbe["message"])
        }
        if let accessibilityProbe = json["accessibilityProbe"] as? [String: Any] {
            XCTAssertNotNil(accessibilityProbe["ok"])
            XCTAssertNotNil(accessibilityProbe["message"])
        }
    }
}
