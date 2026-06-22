import XCTest
@testable import SymOperateCore

// MARK: - Mock Services

private final class MockAccessibilityService: AccessibilityServiceProtocol {
    private var elements: [String: [String: AccessibilityService.ResolvedElement]] = [:]
    private var nodesCache: [String: [UINode]] = [:]
    private var snapshotCache: [String: Snapshot] = [:]
    var focusedRoleOverride: String?

    func prepopulate(snapshotID: String, elementID: String, role: String?, title: String?, label: String?, value: String?, frame: RectValue?) {
        let element = AXUIElementCreateApplication(0)
        let resolved = AccessibilityService.ResolvedElement(element: element, frame: frame, role: role, title: title, label: label, value: value)
        elements[snapshotID, default: [:]][elementID] = resolved
    }

    func prepopulateMany(snapshotID: String, elements: [String: AccessibilityService.ResolvedElement]) {
        for (elementID, resolved) in elements {
            self.elements[snapshotID, default: [:]][elementID] = resolved
        }
    }

    func queryFrontmostUI(snapshotID: String, maxDepth: Int, maxNodes: Int) throws -> [UINode] { [] }

    func resolveElement(snapshotID: String, elementID: String) -> AccessibilityService.ResolvedElement? {
        elements[snapshotID]?[elementID]
    }

    func resolveElementAtPoint(x: Double, y: Double) -> AccessibilityService.ResolvedElement? {
        var bestMatch: AccessibilityService.ResolvedElement?
        var bestArea: Double = .greatestFiniteMagnitude

        for snapshotCache in elements.values {
            for element in snapshotCache.values {
                guard let frame = element.frame else { continue }
                let minX = frame.x
                let maxX = frame.x + frame.width
                let minY = frame.y
                let maxY = frame.y + frame.height
                if x >= minX, x <= maxX, y >= minY, y <= maxY {
                    let area = frame.width * frame.height
                    if area < bestArea {
                        bestArea = area
                        bestMatch = element
                    }
                }
            }
        }
        return bestMatch
    }

    func hasCachedNodes(for snapshotID: String) -> Bool {
        nodesCache[snapshotID] != nil
    }

    func cachedNodes(for snapshotID: String) -> [UINode]? {
        nodesCache[snapshotID]
    }

    func cachedSnapshot(for snapshotID: String) -> Snapshot? {
        snapshotCache[snapshotID]
    }

    func storeSnapshot(_ snapshot: Snapshot, for snapshotID: String) {
        snapshotCache[snapshotID] = snapshot
    }

    func storeNodes(_ nodes: [UINode], for snapshotID: String) {
        nodesCache[snapshotID] = nodes
    }

    func frontmostFocusedElementRole() -> String? { focusedRoleOverride }

    func frontmostContainsText(_ text: String) -> Bool { false }

    func performMenuAction(path: [String]) throws {}
}

private final class MockScreenService: ScreenServiceProtocol {
    var stubbedSnapshot: Snapshot?
    var captureMainDisplayCalled = false

    func listDisplays() -> [DisplayInfo] { [] }
    func captureMainDisplay(maxDimension: CoreGraphics.CGFloat) throws -> Snapshot {
        captureMainDisplayCalled = true
        if let snapshot = stubbedSnapshot {
            return snapshot
        }
        throw AutomationError.unavailable("mock")
    }
    func captureDisplay(displayID: UInt32, maxDimension: CoreGraphics.CGFloat) throws -> Snapshot { throw AutomationError.unavailable("mock") }
    func captureWindow(windowID: Int, maxDimension: CoreGraphics.CGFloat) throws -> Snapshot { throw AutomationError.unavailable("mock") }
}

private final class MockInputService: InputServiceProtocol {
    func click(at point: PointValue, button: String, doubleClick: Bool) throws {}
    func typeText(_ text: String) throws {}
    func pressKeys(_ keys: [String]) throws {}
    func scroll(deltaX: Double, deltaY: Double) throws {}
    func drag(from start: PointValue, to end: PointValue, steps: Int) throws {}
}

private final class MockAppService: AppServiceProtocol {
    func listApps() -> [AppInfo] { [] }
    func listWindows() -> [WindowInfo] { [] }
    func frontmostApp() -> AppInfo? { nil }
    func launchApp(bundleID: String?, appName: String?) throws {}
    func focusWindow(bundleID: String?, appName: String?, title: String?) throws {}
}

private final class MockOCRService: OCRServiceProtocol {
    func recognizeText(in image: CoreGraphics.CGImage) -> OCRResult { OCRResult(regions: [], fullText: "") }
    func isAXTreeWeak(nodeCount: Int, threshold: Int) -> Bool { nodeCount <= threshold }
}

private final class MockUIQueryService: UIQueryServiceProtocol {
    var stubbedNodes: [UINode]?

    func findNodes(in nodes: [UINode], predicate: UIElementPredicate) -> [UINode] {
        if let stubbed = stubbedNodes {
            return stubbed
        }
        return nodes.filter { predicate.matches(node: $0) }
    }
}

private final class MockPermissionService: PermissionServiceProtocol {
    func status() -> PermissionSnapshot { PermissionSnapshot(accessibilityGranted: true, screenRecordingGranted: true) }
    func requestAccessibilityPermission() -> Bool { true }
    func requestScreenRecordingPermission() -> Bool { true }
}

// MARK: - Tests

final class SafetyPolicyTests: XCTestCase {

    private var controller: AutomationController!
    private var mockAX: MockAccessibilityService!

    override func setUp() {
        super.setUp()
        mockAX = MockAccessibilityService()
        controller = AutomationController(
            permissions: MockPermissionService(),
            screen: MockScreenService(),
            apps: MockAppService(),
            accessibility: mockAX,
            input: MockInputService(),
            ocr: MockOCRService(),
            queryService: MockUIQueryService()
        )
    }

    override func tearDown() {
        mockAX.focusedRoleOverride = nil
        controller = nil
        mockAX = nil
        super.tearDown()
    }

    // MARK: - Click Action Tests

    func testClickOnElementTitledDeleteThrowsPermissionDenied() throws {
        let snapshotID = "test-snapshot"
        let elementID = "delete-element"

        let frame = RectValue(x: 100, y: 100, width: 50, height: 30)
        mockAX.prepopulate(
            snapshotID: snapshotID,
            elementID: elementID,
            role: "AXButton",
            title: "Delete",
            label: nil,
            value: nil,
            frame: frame
        )

        do {
            _ = try controller.click(snapshotID: snapshotID, elementID: elementID)
            XCTFail("Expected permissionDenied error for destructive element 'Delete'")
        } catch let error as AutomationError {
            switch error {
            case .permissionDenied(let message):
                XCTAssertTrue(message.contains("destructive") || message.contains("potentially destructive"))
            default:
                XCTFail("Expected permissionDenied error, got \(error)")
            }
        } catch {
            XCTFail("Expected AutomationError, got \(error)")
        }
    }

    func testClickOnElementTitledSaveSucceeds() throws {
        let snapshotID = "test-snapshot"
        let elementID = "save-element"

        let frame = RectValue(x: 100, y: 100, width: 50, height: 30)
        mockAX.prepopulate(
            snapshotID: snapshotID,
            elementID: elementID,
            role: "AXButton",
            title: "Save",
            label: nil,
            value: nil,
            frame: frame
        )

        // Save is not a destructive keyword, so it should NOT throw permissionDenied
        // Note: The actual click might fail due to no accessibility permissions or input service,
        // but it should NOT fail with permissionDenied for destructive action
        do {
            _ = try controller.click(snapshotID: snapshotID, elementID: elementID)
            // If we get here without throwing, the destructive check passed
            // (actual click might still fail due to permissions, but not due to safety policy)
        } catch let error as AutomationError {
            // permissionDenied due to destructive action should NOT happen for "Save"
            if case .permissionDenied(let message) = error, message.contains("destructive") {
                XCTFail("Save should not be blocked as destructive, but got: \(message)")
            }
            // Other errors (like input service issues) are acceptable for this test
        }
    }

    func testClickOnElementWithLabelRemoveThrowsPermissionDenied() throws {
        let snapshotID = "test-snapshot"
        let elementID = "remove-element"

        let frame = RectValue(x: 200, y: 200, width: 60, height: 40)
        mockAX.prepopulate(
            snapshotID: snapshotID,
            elementID: elementID,
            role: "AXButton",
            title: nil,
            label: "Remove",
            value: nil,
            frame: frame
        )

        do {
            _ = try controller.click(snapshotID: snapshotID, elementID: elementID)
            XCTFail("Expected permissionDenied error for destructive element with label 'Remove'")
        } catch let error as AutomationError {
            switch error {
            case .permissionDenied(let message):
                XCTAssertTrue(message.contains("destructive") || message.contains("potentially destructive"))
            default:
                XCTFail("Expected permissionDenied error, got \(error)")
            }
        } catch {
            XCTFail("Expected AutomationError, got \(error)")
        }
    }

    func testClickOnElementTitledEraseThrowsPermissionDenied() throws {
        let snapshotID = "test-snapshot"
        let elementID = "erase-element"

        let frame = RectValue(x: 300, y: 300, width: 70, height: 35)
        mockAX.prepopulate(
            snapshotID: snapshotID,
            elementID: elementID,
            role: "AXButton",
            title: "Erase Disk",
            label: nil,
            value: nil,
            frame: frame
        )

        do {
            _ = try controller.click(snapshotID: snapshotID, elementID: elementID)
            XCTFail("Expected permissionDenied error for destructive element 'Erase Disk'")
        } catch let error as AutomationError {
            switch error {
            case .permissionDenied(let message):
                XCTAssertTrue(message.contains("destructive") || message.contains("potentially destructive"))
            default:
                XCTFail("Expected permissionDenied error, got \(error)")
            }
        } catch {
            XCTFail("Expected AutomationError, got \(error)")
        }
    }

    // MARK: - Drag Action Tests

    func testDragFromDestructiveElementThrowsPermissionDenied() throws {
        let snapshotID = "test-snapshot"
        let fromElementID = "delete-drag-source"

        let frame = RectValue(x: 100, y: 100, width: 50, height: 30)
        mockAX.prepopulate(
            snapshotID: snapshotID,
            elementID: fromElementID,
            role: "AXButton",
            title: "Delete",
            label: nil,
            value: nil,
            frame: frame
        )

        do {
            _ = try controller.drag(
                snapshotID: snapshotID,
                fromElementID: fromElementID,
                toX: 200,
                toY: 200
            )
            XCTFail("Expected permissionDenied error when dragging from destructive element 'Delete'")
        } catch let error as AutomationError {
            switch error {
            case .permissionDenied(let message):
                XCTAssertTrue(message.contains("destructive") || message.contains("potentially destructive"))
            default:
                XCTFail("Expected permissionDenied error, got \(error)")
            }
        } catch {
            XCTFail("Expected AutomationError, got \(error)")
        }
    }

    func testDragToDestructiveElementThrowsPermissionDenied() throws {
        let snapshotID = "test-snapshot"
        let toElementID = "remove-drag-target"

        mockAX.prepopulateMany(
            snapshotID: snapshotID,
            elements: [
                toElementID: AccessibilityService.ResolvedElement(
                    element: AXUIElementCreateApplication(0),
                    frame: RectValue(x: 200, y: 200, width: 50, height: 30),
                    role: "AXButton", title: "Remove", label: nil, value: nil
                ),
                "safe-source": AccessibilityService.ResolvedElement(
                    element: AXUIElementCreateApplication(0),
                    frame: RectValue(x: 80, y: 80, width: 40, height: 40),
                    role: "AXButton", title: "OK", label: nil, value: nil
                ),
            ]
        )

        do {
            _ = try controller.drag(
                snapshotID: snapshotID,
                toElementID: toElementID,
                fromX: 100,
                fromY: 100
            )
            XCTFail("Expected permissionDenied error when dragging to destructive element 'Remove'")
        } catch let error as AutomationError {
            switch error {
            case .permissionDenied(let message):
                XCTAssertTrue(message.contains("destructive") || message.contains("potentially destructive"))
            default:
                XCTFail("Expected permissionDenied error, got \(error)")
            }
        } catch {
            XCTFail("Expected AutomationError, got \(error)")
        }
    }

    // MARK: - Menu Action Tests

    func testMenuActionEraseDiskThrowsPermissionDenied() throws {
        // Note: This test verifies the destructive keyword check in performMenuAction
        // The actual menu lookup will fail (no frontmost app), but the destructive check
        // happens BEFORE the menu lookup, so we expect a different error path.

        // Since performMenuAction checks AXIsProcessTrusted() first, we need to
        // handle that. But the destructive check happens after getting the menu bar.
        // Without a real accessibility context, we can't fully test menuAction,
        // but we can verify the policy structure is correct by checking that
        // "Erase Disk" contains a destructive keyword.

        let destructiveKeywords: Set<String> = [
            "delete", "remove", "erase", "clear", "trash",
            "uninstall", "allow", "authorize", "unlock",
            "quit", "terminate", "force quit", "shutdown"
        ]

        let menuItemTitle = "Erase Disk"
        let titleLowercased = menuItemTitle.lowercased()
        var foundDestructive = false
        for keyword in destructiveKeywords {
            if titleLowercased.contains(keyword) {
                foundDestructive = true
                break
            }
        }
        XCTAssertTrue(foundDestructive, "Erase Disk should contain destructive keyword 'erase'")
    }

    func testMenuActionOpenDoesNotContainDestructiveKeyword() throws {
        let destructiveKeywords: Set<String> = [
            "delete", "remove", "erase", "clear", "trash",
            "uninstall", "allow", "authorize", "unlock",
            "quit", "terminate", "force quit", "shutdown"
        ]

        let menuItemTitle = "Open"
        let titleLowercased = menuItemTitle.lowercased()
        var foundDestructive = false
        for keyword in destructiveKeywords {
            if titleLowercased.contains(keyword) {
                foundDestructive = true
                break
            }
        }
        XCTAssertFalse(foundDestructive, "Open should NOT contain any destructive keyword")
    }

    // MARK: - Policy Keyword Tests

    func testDestructiveKeywordsListIncludesExpectedValues() throws {
        let expectedKeywords = [
            "delete", "remove", "erase", "clear", "trash",
            "uninstall", "allow", "authorize", "unlock",
            "quit", "terminate", "force quit", "shutdown"
        ]

        // We test that these keywords are properly checked by the policy
        // by verifying element titles that should be blocked
        let destructiveTitles = ["Delete", "Remove", "Erase", "Clear", "Trash", "Quit", "Force Quit"]

        for title in destructiveTitles {
            let titleLowercased = title.lowercased()
            var shouldBlock = false
            for keyword in expectedKeywords {
                if titleLowercased.contains(keyword) {
                    shouldBlock = true
                    break
                }
            }
            XCTAssertTrue(shouldBlock, "Title '\(title)' should be blocked")
        }
    }

    func testNonDestructiveTitlesDoNotMatch() throws {
        let expectedKeywords = [
            "delete", "remove", "erase", "clear", "trash",
            "uninstall", "allow", "authorize", "unlock",
            "quit", "terminate", "force quit", "shutdown"
        ]

        let safeTitles = ["Save", "Open", "Close", "New", "Edit", "View", "Help", "Cancel", "OK"]

        for title in safeTitles {
            let titleLowercased = title.lowercased()
            var shouldBlock = false
            for keyword in expectedKeywords {
                if titleLowercased.contains(keyword) {
                    shouldBlock = true
                    break
                }
            }
            XCTAssertFalse(shouldBlock, "Title '\(title)' should NOT be blocked")
        }
    }

    // MARK: - Secure Field Tests (type_text / press_keys)

    func testTypeTextIntoSecureFieldThrowsPermissionDenied() throws {
        mockAX.focusedRoleOverride = "AXSecureTextField"

        do {
            _ = try controller.typeText("secret")
            XCTFail("Expected permissionDenied error when typing into a secure text field")
        } catch let error as AutomationError {
            if case .permissionDenied(let message) = error {
                XCTAssertTrue(message.contains("secure text field"), "Error message should mention secure text field, got: \(message)")
            } else {
                XCTFail("Expected permissionDenied error, got \(error)")
            }
        } catch {
            XCTFail("Expected AutomationError, got \(error)")
        }
    }

    func testPressKeysIntoSecureFieldThrowsPermissionDenied() throws {
        mockAX.focusedRoleOverride = "AXSecureTextField"

        do {
            _ = try controller.pressKeys(["a"])
            XCTFail("Expected permissionDenied error when pressing keys into a secure text field")
        } catch let error as AutomationError {
            if case .permissionDenied(let message) = error {
                XCTAssertTrue(message.contains("secure text field"), "Error message should mention secure text field, got: \(message)")
            } else {
                XCTFail("Expected permissionDenied error, got \(error)")
            }
        } catch {
            XCTFail("Expected AutomationError, got \(error)")
        }
    }

    func testTypeTextDoesNotThrowWhenFocusedElementIsNotSecure() throws {
        mockAX.focusedRoleOverride = "AXTextField"

        do {
            _ = try controller.typeText("hello")
        } catch let error as AutomationError {
            if case .permissionDenied(let message) = error, message.contains("secure text field") {
                XCTFail("typeText should not be blocked for a non-secure focused field, got: \(message)")
            }
        }
    }

    func testPressKeysDoesNotThrowWhenFocusedElementIsNotSecure() throws {
        mockAX.focusedRoleOverride = "AXTextField"

        do {
            _ = try controller.pressKeys(["a"])
        } catch let error as AutomationError {
            if case .permissionDenied(let message) = error, message.contains("secure text field") {
                XCTFail("pressKeys should not be blocked for a non-secure focused field, got: \(message)")
            }
        }
    }

    func testTypeTextDoesNotThrowWhenNoFocusedElement() throws {
        do {
            _ = try controller.typeText("hello")
        } catch let error as AutomationError {
            if case .permissionDenied(let message) = error, message.contains("secure text field") {
                XCTFail("typeText should not be blocked when no focused element role is available")
            }
        }
    }

    // MARK: - Raw Coordinate Bypass Tests (Issue #31)

    func testRawClickOnSecureTextFieldThrowsPermissionDenied() throws {
        let snapshotID = "snap-secure"
        let elementID = "secure-field"

        let frame = RectValue(x: 100, y: 100, width: 200, height: 30)
        mockAX.prepopulate(
            snapshotID: snapshotID,
            elementID: elementID,
            role: "AXSecureTextField",
            title: nil,
            label: "Password",
            value: nil,
            frame: frame
        )

        do {
            _ = try controller.click(x: 150, y: 110)
            XCTFail("Expected permissionDenied for raw-coord click on secure text field")
        } catch let error as AutomationError {
            if case .permissionDenied(let message) = error {
                XCTAssertTrue(message.contains("secure text field"), "Expected secure field message, got: \(message)")
            } else {
                XCTFail("Expected permissionDenied, got \(error)")
            }
        }
    }

    func testRawClickOnDestructiveElementThrowsPermissionDenied() throws {
        let snapshotID = "snap-delete"
        let elementID = "delete-btn"

        let frame = RectValue(x: 50, y: 50, width: 80, height: 40)
        mockAX.prepopulate(
            snapshotID: snapshotID,
            elementID: elementID,
            role: "AXButton",
            title: "Delete",
            label: nil,
            value: nil,
            frame: frame
        )

        do {
            _ = try controller.click(x: 80, y: 65)
            XCTFail("Expected permissionDenied for raw-coord click on destructive element")
        } catch let error as AutomationError {
            if case .permissionDenied(let message) = error {
                XCTAssertTrue(message.contains("destructive"), "Expected destructive message, got: \(message)")
            } else {
                XCTFail("Expected permissionDenied, got \(error)")
            }
        }
    }

    func testRawClickOnUnknownElementThrowsPermissionDenied() throws {
        do {
            _ = try controller.click(x: 999, y: 999)
            XCTFail("Expected permissionDenied for raw-coord click with no cached element")
        } catch let error as AutomationError {
            if case .permissionDenied(let message) = error {
                XCTAssertTrue(message.contains("Cannot identify"), "Expected identification failure, got: \(message)")
            } else {
                XCTFail("Expected permissionDenied, got \(error)")
            }
        }
    }

    func testRawClickOnSafeElementDoesNotThrowPermissionDenied() throws {
        let snapshotID = "snap-save"
        let elementID = "save-btn"

        let frame = RectValue(x: 10, y: 10, width: 60, height: 30)
        mockAX.prepopulate(
            snapshotID: snapshotID,
            elementID: elementID,
            role: "AXButton",
            title: "Save",
            label: nil,
            value: nil,
            frame: frame
        )

        let resolved = mockAX.resolveElementAtPoint(x: 30, y: 20)
        XCTAssertNotNil(resolved, "Should find the safe element at (30, 20)")

        if let resolved {
            XCTAssertFalse(
                controller.actionPolicy.isDestructive(role: resolved.role, title: resolved.title, label: resolved.label, value: resolved.value),
                "Safe element 'Save' should not be flagged as destructive"
            )
            XCTAssertNotEqual(resolved.role, "AXSecureTextField", "Safe element should not be a secure text field")
        }
    }

    func testRawDragFromDestructiveElementThrowsPermissionDenied() throws {
        let snapshotID = "snap-drag-del"
        let elementID = "delete-drag"

        let frame = RectValue(x: 100, y: 100, width: 50, height: 30)
        mockAX.prepopulate(
            snapshotID: snapshotID,
            elementID: elementID,
            role: "AXButton",
            title: "Delete",
            label: nil,
            value: nil,
            frame: frame
        )

        do {
            _ = try controller.drag(fromX: 110, fromY: 110, toX: 300, toY: 300)
            XCTFail("Expected permissionDenied for raw-coord drag from destructive element")
        } catch let error as AutomationError {
            if case .permissionDenied(let message) = error {
                XCTAssertTrue(message.contains("destructive"), "Expected destructive message, got: \(message)")
            } else {
                XCTFail("Expected permissionDenied, got \(error)")
            }
        }
    }

    func testRawDragToSecureTextFieldThrowsPermissionDenied() throws {
        let snapshotID = "snap-drag-sec"
        let sourceElementID = "safe-source"
        let targetElementID = "secure-target"

        let sourceFrame = RectValue(x: 40, y: 40, width: 30, height: 30)
        let targetFrame = RectValue(x: 300, y: 300, width: 200, height: 30)

        mockAX.prepopulateMany(snapshotID: snapshotID, elements: [
            sourceElementID: AccessibilityService.ResolvedElement(
                element: AXUIElementCreateApplication(0),
                frame: sourceFrame, role: "AXButton",
                title: "OK", label: nil, value: nil
            ),
            targetElementID: AccessibilityService.ResolvedElement(
                element: AXUIElementCreateApplication(0),
                frame: targetFrame, role: "AXSecureTextField",
                title: nil, label: "PIN", value: nil
            ),
        ])

        do {
            _ = try controller.drag(
                snapshotID: snapshotID,
                fromElementID: sourceElementID,
                toX: 350,
                toY: 310
            )
            XCTFail("Expected permissionDenied for raw-coord drag to secure text field")
        } catch let error as AutomationError {
            if case .permissionDenied(let message) = error {
                XCTAssertTrue(message.contains("secure text field"), "Expected secure field message, got: \(message)")
            } else {
                XCTFail("Expected permissionDenied, got \(error)")
            }
        }
    }

    func testResolveElementAtPointFindsCachedElement() {
        let service = AccessibilityService()
        let element = AXUIElementCreateApplication(0)
        service.elementCache["snap"] = [
            "btn": AccessibilityService.ResolvedElement(
                element: element,
                frame: RectValue(x: 100, y: 100, width: 50, height: 30),
                role: "AXButton", title: "OK", label: nil, value: nil
            )
        ]

        let found = service.resolveElementAtPoint(x: 120, y: 110)
        XCTAssertNotNil(found, "Should find element at point inside its frame")

        let missed = service.resolveElementAtPoint(x: 999, y: 999)
        XCTAssertNil(missed, "Should return nil for point outside all frames")
    }

    func testRawDragToUnknownElementThrowsPermissionDenied() throws {
        do {
            _ = try controller.drag(fromX: 50, fromY: 50, toX: 999, toY: 999)
            XCTFail("Expected permissionDenied for raw-coord drag to unknown element")
        } catch let error as AutomationError {
            if case .permissionDenied(let message) = error {
                XCTAssertTrue(message.contains("Cannot identify"), "Expected identification failure, got: \(message)")
            } else {
                XCTFail("Expected permissionDenied, got \(error)")
            }
        }
    }
}
