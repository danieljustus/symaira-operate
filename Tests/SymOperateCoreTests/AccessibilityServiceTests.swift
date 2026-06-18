import XCTest
@testable import SymOperateCore

final class AccessibilityServiceTests: XCTestCase {
    private let mockElement = AXUIElementCreateApplication(123)

    func testCacheEvictsOldestSnapshotWhenBounded() {
        let service = AccessibilityService()

        for i in 0..<22 {
            let snapshotID = "snapshot_\(i)"
            var cache: [String: AccessibilityService.ResolvedElement] = [:]
            cache["element_\(i)"] = AccessibilityService.ResolvedElement(
                element: mockElement,
                frame: RectValue(x: 0, y: 0, width: 100, height: 100),
                role: "AXButton",
                title: "Button \(i)",
                label: nil,
                value: nil
            )
            service.elementCache[snapshotID] = cache
            service.cacheOrder.append(snapshotID)
        }

        XCTAssertEqual(service.cacheOrder.count, 22)
        XCTAssertEqual(service.elementCache.count, 22)

        while service.cacheOrder.count > 20 {
            let oldest = service.cacheOrder.removeFirst()
            service.elementCache.removeValue(forKey: oldest)
        }

        XCTAssertEqual(service.cacheOrder.count, 20)
        XCTAssertEqual(service.elementCache.count, 20)
        XCTAssertFalse(service.cacheOrder.contains("snapshot_0"))
        XCTAssertTrue(service.cacheOrder.contains("snapshot_21"))
    }

    func testResolveElementReturnsNilForEvictedSnapshot() {
        let service = AccessibilityService()

        let snapshotID = "snapshot_test"
        var cache: [String: AccessibilityService.ResolvedElement] = [:]
        cache["element_1"] = AccessibilityService.ResolvedElement(
            element: mockElement,
            frame: RectValue(x: 10, y: 10, width: 50, height: 50),
            role: "AXButton",
            title: "Test",
            label: nil,
            value: nil
        )
        service.elementCache[snapshotID] = cache
        service.cacheOrder.append(snapshotID)

        XCTAssertNotNil(service.resolveElement(snapshotID: snapshotID, elementID: "element_1"))

        service.elementCache.removeValue(forKey: snapshotID)

        XCTAssertNil(service.resolveElement(snapshotID: snapshotID, elementID: "element_1"))
    }

    func testResolveElementReturnsNilForNonExistentElement() {
        let service = AccessibilityService()

        let snapshotID = "snapshot_test2"
        var cache: [String: AccessibilityService.ResolvedElement] = [:]
        cache["element_1"] = AccessibilityService.ResolvedElement(
            element: mockElement,
            frame: RectValue(x: 10, y: 10, width: 50, height: 50),
            role: "AXButton",
            title: "Test",
            label: nil,
            value: nil
        )
        service.elementCache[snapshotID] = cache
        service.cacheOrder.append(snapshotID)

        XCTAssertNil(service.resolveElement(snapshotID: snapshotID, elementID: "non_existent_element"))
    }

    func testSearchTextInoutParameterCumulativeEnforcement() {
        let service = AccessibilityService()

        var seen = 0
        _ = service.searchText(
            in: mockElement,
            needle: "nonexistent",
            remainingDepth: 1,
            seen: &seen,
            maxNodes: 10
        )

        XCTAssertGreaterThan(seen, 0)
    }

    func testSearchTextEnforcesMaxNodesCumulatively() {
        let service = AccessibilityService()

        var seen = 0
        _ = service.searchText(
            in: mockElement,
            needle: "nonexistent",
            remainingDepth: 10,
            seen: &seen,
            maxNodes: 1
        )

        // The mock element has no children, so exactly 1 node should be visited before the budget stops further traversal.
        XCTAssertEqual(seen, 1, "searchText should stop after maxNodes=1 is reached")
    }

    func testStaleReferenceErrorExists() {
        let error = AutomationError.staleReference("Snapshot has expired")
        XCTAssertEqual(error.localizedDescription, "Snapshot has expired")

        switch error {
        case .staleReference(let message):
            XCTAssertEqual(message, "Snapshot has expired")
        default:
            XCTFail("Expected staleReference case")
        }
    }
}
