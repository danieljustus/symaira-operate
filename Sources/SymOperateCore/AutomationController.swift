import AppKit
import CoreGraphics
import Foundation

public final class AutomationController {
    private let permissions = PermissionService()
    private let screen = ScreenService()
    private let apps = AppService()
    let accessibility = AccessibilityService()
    private let input = InputService()
    private let ocr = OCRService()
    public var actionPolicy = ActionPolicy()

    public init() {}

    public func permissionsStatus() -> PermissionSnapshot {
        permissions.status()
    }

    @discardableResult
    public func requestAccessibilityPermission() -> Bool {
        permissions.requestAccessibilityPermission()
    }

    @discardableResult
    public func requestScreenRecordingPermission() -> Bool {
        permissions.requestScreenRecordingPermission()
    }

    public func listApps() -> [AppInfo] {
        apps.listApps()
    }

    public func listWindows() -> [WindowInfo] {
        apps.listWindows()
    }

    public func listDisplays() -> [DisplayInfo] {
        screen.listDisplays()
    }

    public func snapshot(displayID: UInt32? = nil, windowID: Int? = nil) throws -> Snapshot {
        if let windowID {
            return try screen.captureWindow(windowID: windowID)
        }
        if let displayID {
            return try screen.captureDisplay(displayID: displayID)
        }
        return try screen.captureMainDisplay()
    }

    public func queryUI(maxDepth: Int = 4, maxNodes: Int = 200, displayID: UInt32? = nil, windowID: Int? = nil) throws -> UIQueryResult {
        let snapshot = try self.snapshot(displayID: displayID, windowID: windowID)
        let nodes = try accessibility.queryFrontmostUI(snapshotID: snapshot.id, maxDepth: maxDepth, maxNodes: maxNodes)
        return UIQueryResult(snapshot: snapshot, app: apps.frontmostApp(), nodes: nodes)
    }

    public func queryUIWithOCR(maxDepth: Int = 4, maxNodes: Int = 200, displayID: UInt32? = nil, windowID: Int? = nil) throws -> UIQueryResultWithOCR {
        let snapshot = try self.snapshot(displayID: displayID, windowID: windowID)
        let nodes = try accessibility.queryFrontmostUI(snapshotID: snapshot.id, maxDepth: maxDepth, maxNodes: maxNodes)
        let isWeak = ocr.isAXTreeWeak(nodeCount: countNodes(nodes))

        var ocrResult: OCRResult?
        if isWeak, let imageData = Data(base64Encoded: snapshot.imageBase64PNG) {
            if let bitmapRep = NSBitmapImageRep(data: imageData),
               let cgImage = bitmapRep.cgImage {
                ocrResult = ocr.recognizeText(in: cgImage)
            }
        }

        return UIQueryResultWithOCR(
            snapshot: snapshot,
            app: apps.frontmostApp(),
            nodes: nodes,
            ocrResult: ocrResult,
            axTreeWeak: isWeak
        )
    }

    private func countNodes(_ nodes: [UINode]) -> Int {
        var count = 0
        var stack = nodes
        while !stack.isEmpty {
            let node = stack.removeLast()
            count += 1
            stack.append(contentsOf: node.children)
        }
        return count
    }

    public func findUI(
        predicate: UIElementPredicate,
        snapshotID: String? = nil,
        maxDepth: Int = 4,
        maxNodes: Int = 200,
        displayID: UInt32? = nil,
        windowID: Int? = nil
    ) throws -> UIQueryResult {
        let queryResult: UIQueryResult
        if let snapshotID, let existing = accessibility.resolveElement(snapshotID: snapshotID, elementID: "") {
            _ = existing
            // Reuse existing snapshot — just re-run the query against cached tree
            queryResult = try queryUI(maxDepth: maxDepth, maxNodes: maxNodes, displayID: displayID, windowID: windowID)
        } else {
            queryResult = try queryUI(maxDepth: maxDepth, maxNodes: maxNodes, displayID: displayID, windowID: windowID)
        }
        let queryService = UIQueryService()
        let matched = queryService.findNodes(in: queryResult.nodes, predicate: predicate)
        return UIQueryResult(snapshot: queryResult.snapshot, app: queryResult.app, nodes: matched)
    }

    public func click(
        snapshotID: String? = nil,
        elementID: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        button: String = "left",
        doubleClick: Bool = false
    ) throws -> ActionResult {
        let target = try resolvePoint(snapshotID: snapshotID, elementID: elementID, x: x, y: y)
        try input.click(at: target, button: button, doubleClick: doubleClick)
        return ActionResult(ok: true, message: "Click delivered at (\(Int(target.x)), \(Int(target.y))).", snapshot: try? screen.captureMainDisplay())
    }

    public func typeText(_ text: String) throws -> ActionResult {
        guard !text.isEmpty else {
            throw AutomationError.invalidArgument("type_text requires a non-empty text argument.")
        }
        try input.typeText(text)
        return ActionResult(ok: true, message: "Typed \(text.count) characters.", snapshot: try? screen.captureMainDisplay())
    }

    public func pressKeys(_ keys: [String]) throws -> ActionResult {
        try input.pressKeys(keys)
        return ActionResult(ok: true, message: "Pressed keys: \(keys.joined(separator: "+")).", snapshot: try? screen.captureMainDisplay())
    }

    public func scroll(deltaX: Double = 0, deltaY: Double) throws -> ActionResult {
        try input.scroll(deltaX: deltaX, deltaY: deltaY)
        return ActionResult(ok: true, message: "Scrolled by (\(deltaX), \(deltaY)).", snapshot: try? screen.captureMainDisplay())
    }

    public func drag(
        snapshotID: String? = nil,
        fromElementID: String? = nil,
        toElementID: String? = nil,
        fromX: Double? = nil,
        fromY: Double? = nil,
        toX: Double? = nil,
        toY: Double? = nil
    ) throws -> ActionResult {
        let start = try resolvePoint(snapshotID: snapshotID, elementID: fromElementID, x: fromX, y: fromY)
        let end = try resolvePoint(snapshotID: snapshotID, elementID: toElementID, x: toX, y: toY)
        try input.drag(from: start, to: end)
        return ActionResult(ok: true, message: "Dragged from (\(Int(start.x)), \(Int(start.y))) to (\(Int(end.x)), \(Int(end.y))).", snapshot: try? screen.captureMainDisplay())
    }

    public func launchApp(bundleID: String? = nil, appName: String? = nil) throws -> ActionResult {
        try apps.launchApp(bundleID: bundleID, appName: appName)
        return ActionResult(ok: true, message: "Application launch requested.", snapshot: try? screen.captureMainDisplay())
    }

    public func focusWindow(bundleID: String? = nil, appName: String? = nil, title: String? = nil) throws -> ActionResult {
        try apps.focusWindow(bundleID: bundleID, appName: appName, title: title)
        return ActionResult(ok: true, message: "Window focus updated.", snapshot: try? screen.captureMainDisplay())
    }

    public func menuAction(path: [String]) throws -> ActionResult {
        try accessibility.performMenuAction(path: path)
        return ActionResult(ok: true, message: "Menu action triggered: \(path.joined(separator: " > ")).", snapshot: try? screen.captureMainDisplay())
    }

    public func waitFor(text: String?, app: String?, timeoutSeconds: Double = 10) async throws -> ActionResult {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let app, !app.isEmpty {
                let exists = apps.listApps().contains {
                    $0.localizedName.localizedCaseInsensitiveContains(app) || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(app) ?? false)
                }
                if exists {
                    return ActionResult(ok: true, message: "Observed app '\(app)'.", snapshot: try? screen.captureMainDisplay())
                }
            }

            if let text, !text.isEmpty, accessibility.frontmostContainsText(text) {
                return ActionResult(ok: true, message: "Observed text '\(text)'.", snapshot: try? screen.captureMainDisplay())
            }

            try await Task.sleep(nanoseconds: 400_000_000) // 0.4 seconds
        }

        throw AutomationError.operationFailed("Condition was not met within \(timeoutSeconds) seconds.")
    }

    private func resolvePoint(snapshotID: String?, elementID: String?, x: Double?, y: Double?) throws -> PointValue {
        if let snapshotID, let elementID {
            if let resolved = accessibility.resolveElement(snapshotID: snapshotID, elementID: elementID) {
                if let role = resolved.role, role == "AXSecureTextField" {
                    throw AutomationError.permissionDenied("Refusing to target a secure text field.")
                }

                if actionPolicy.isDestructive(role: resolved.role, title: resolved.title, label: resolved.label, value: resolved.value) {
                    throw AutomationError.permissionDenied("Refusing to target a potentially destructive UI element.")
                }

                if let frame = resolved.frame {
                    return frame.center
                }
                throw AutomationError.unavailable("The target element does not expose a clickable frame.")
            }
            throw AutomationError.staleReference("The referenced snapshot has expired or the element no longer exists.")
        }

        if let x, let y {
            return PointValue(x: x, y: y)
        }

        throw AutomationError.invalidArgument("Provide either x/y coordinates or snapshot_id + element_id.")
    }
}
