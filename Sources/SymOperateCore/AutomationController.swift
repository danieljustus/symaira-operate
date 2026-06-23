import AppKit
import CoreGraphics
import Foundation

public final class AutomationController {
    private let permissions: any PermissionServiceProtocol
    private let screen: any ScreenServiceProtocol
    private let apps: any AppServiceProtocol
    let accessibility: any AccessibilityServiceProtocol
    private let input: any InputServiceProtocol
    private let ocr: any OCRServiceProtocol
    private let queryService: any UIQueryServiceProtocol
    public var actionPolicy: ActionPolicy

    public init(
        permissions: any PermissionServiceProtocol = PermissionService(),
        screen: any ScreenServiceProtocol = ScreenService(),
        apps: any AppServiceProtocol = AppService(),
        accessibility: any AccessibilityServiceProtocol = AccessibilityService(),
        input: any InputServiceProtocol = InputService(),
        ocr: any OCRServiceProtocol = OCRService(),
        queryService: any UIQueryServiceProtocol = UIQueryService(),
        actionPolicy: ActionPolicy = ActionPolicy()
    ) {
        self.permissions = permissions
        self.screen = screen
        self.apps = apps
        self.accessibility = accessibility
        self.input = input
        self.ocr = ocr
        self.queryService = queryService
        self.actionPolicy = actionPolicy
    }

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
        accessibility.storeSnapshot(snapshot, for: snapshot.id)
        let nodes = try accessibility.queryFrontmostUI(snapshotID: snapshot.id, maxDepth: maxDepth, maxNodes: maxNodes)
        return UIQueryResult(snapshot: snapshot, app: apps.frontmostApp(), nodes: nodes)
    }

    public func queryUIWithOCR(maxDepth: Int = 4, maxNodes: Int = 200, displayID: UInt32? = nil, windowID: Int? = nil) throws -> UIQueryResultWithOCR {
        let snapshot = try self.snapshot(displayID: displayID, windowID: windowID)
        accessibility.storeSnapshot(snapshot, for: snapshot.id)
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
        if let snapshotID, accessibility.hasCachedNodes(for: snapshotID),
           let cachedNodes = accessibility.cachedNodes(for: snapshotID),
           let cachedSnapshot = accessibility.cachedSnapshot(for: snapshotID) {
            // Reuse existing snapshot — run the query against cached tree
            let matched = queryService.findNodes(in: cachedNodes, predicate: predicate)
            return UIQueryResult(snapshot: cachedSnapshot, app: apps.frontmostApp(), nodes: matched)
        } else {
            queryResult = try queryUI(maxDepth: maxDepth, maxNodes: maxNodes, displayID: displayID, windowID: windowID)
        }
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
        try guardAgainstSecureField()
        try input.typeText(text)
        return ActionResult(ok: true, message: "Typed \(text.count) characters.", snapshot: try? screen.captureMainDisplay())
    }

    public func pressKeys(_ keys: [String]) throws -> ActionResult {
        try guardAgainstSecureField()
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
        try input.drag(from: start, to: end, steps: 24)
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
        accessibility.invalidatePollingCache()

        let observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [accessibility] _ in
            accessibility.invalidatePollingCache()
        }
        defer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }

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

            if let text, !text.isEmpty, accessibility.frontmostContainsTextPolling(text) {
                return ActionResult(ok: true, message: "Observed text '\(text)'.", snapshot: try? screen.captureMainDisplay())
            }

            try await Task.sleep(nanoseconds: 400_000_000) // 0.4 seconds
        }

        throw AutomationError.operationFailed("Condition was not met within \(timeoutSeconds) seconds.")
    }

    private func guardAgainstSecureField() throws {
        if let role = accessibility.frontmostFocusedElementRole(), role == "AXSecureTextField" {
            throw AutomationError.permissionDenied("Refusing to type into a secure text field.")
        }
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
            if let resolved = accessibility.resolveElementAtPoint(x: x, y: y) {
                if let role = resolved.role, role == "AXSecureTextField" {
                    throw AutomationError.permissionDenied("Refusing to target a secure text field via raw coordinates.")
                }
                if actionPolicy.isDestructive(role: resolved.role, title: resolved.title, label: resolved.label, value: resolved.value) {
                    throw AutomationError.permissionDenied("Refusing to target a potentially destructive UI element via raw coordinates.")
                }
                return PointValue(x: x, y: y)
            }
            throw AutomationError.permissionDenied("Cannot identify the element at the given coordinates. Use snapshot_id + element_id instead, or take a snapshot first to enable coordinate-based targeting.")
        }

        throw AutomationError.invalidArgument("Provide either x/y coordinates or snapshot_id + element_id.")
    }
}
