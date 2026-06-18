import AppKit
import ApplicationServices
import Foundation

public final class AccessibilityService {
    public struct ResolvedElement {
        public let element: AXUIElement
        public let frame: RectValue?
        public let role: String?
        public let title: String?
        public let label: String?
        public let value: String?
    }

    internal var elementCache: [String: [String: ResolvedElement]] = [:]
    internal var cacheOrder: [String] = []
    private let maxCacheSnapshots = 20

    public init() {}

    private func evictIfNeeded() {
        guard cacheOrder.count >= maxCacheSnapshots else { return }
        let removeCount = cacheOrder.count - maxCacheSnapshots + 1
        let toRemove = Array(cacheOrder.prefix(removeCount))
        cacheOrder.removeFirst(removeCount)
        for snapshotID in toRemove {
            elementCache.removeValue(forKey: snapshotID)
        }
    }

    public func queryFrontmostUI(snapshotID: String, maxDepth: Int = 4, maxNodes: Int = 200) throws -> [UINode] {
        guard AXIsProcessTrusted() else {
            throw AutomationError.permissionDenied("Accessibility permission is required for query_ui.")
        }

        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw AutomationError.notFound("No frontmost application is available.")
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        let roots = preferredRoots(for: axApp)
        var remaining = maxNodes
        var cache: [String: ResolvedElement] = [:]
        let nodes = roots.compactMap { buildNode(element: $0, depth: 0, maxDepth: maxDepth, remainingNodes: &remaining, cache: &cache) }
        evictIfNeeded()
        elementCache[snapshotID] = cache
        cacheOrder.append(snapshotID)
        return nodes
    }

    public func resolveElement(snapshotID: String, elementID: String) -> ResolvedElement? {
        elementCache[snapshotID]?[elementID]
    }

    public func prepopulateForTesting(snapshotID: String, elementID: String, role: String?, title: String?, label: String?, value: String?, frame: RectValue?) {
        let element = AXUIElementCreateApplication(0)
        let resolved = ResolvedElement(element: element, frame: frame, role: role, title: title, label: label, value: value)
        elementCache[snapshotID] = [elementID: resolved]
    }

    public func frontmostContainsText(_ text: String) -> Bool {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return false }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var seen = 0
        return searchText(in: axApp, needle: text.lowercased(), remainingDepth: 6, seen: &seen, maxNodes: 300)
    }

    public func performMenuAction(path: [String]) throws {
        guard AXIsProcessTrusted() else {
            throw AutomationError.permissionDenied("Accessibility permission is required for menu_action.")
        }
        guard !path.isEmpty else {
            throw AutomationError.invalidArgument("menu_action requires a non-empty path.")
        }
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw AutomationError.notFound("No frontmost application is available.")
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let menuBar = copyElement(axApp, attribute: kAXMenuBarAttribute) else {
            throw AutomationError.notFound("The frontmost app does not expose an accessible menu bar.")
        }

        let destructiveKeywords: Set<String> = [
            "delete", "remove", "erase", "clear", "trash",
            "uninstall", "allow", "authorize", "unlock",
            "quit", "terminate", "force quit", "shutdown"
        ]

        var current = menuBar
        for (index, segment) in path.enumerated() {
            guard let next = findMenuChild(parent: current, title: segment) else {
                throw AutomationError.notFound("Menu segment '\(segment)' was not found.")
            }
            current = next
            if index == path.count - 1 {
                if let title = copyString(current, attribute: kAXTitleAttribute)?.lowercased() {
                    for keyword in destructiveKeywords where title.contains(keyword) {
                            throw AutomationError.permissionDenied("Refusing to perform a destructive menu action.")
                        }
                }
                let result = AXUIElementPerformAction(current, kAXPressAction as CFString)
                guard result == .success else {
                    throw AutomationError.operationFailed("Failed to activate menu item '\(segment)'.")
                }
            } else {
                _ = AXUIElementPerformAction(current, kAXPressAction as CFString)
                Thread.sleep(forTimeInterval: 0.12)
            }
        }
    }

    private func preferredRoots(for axApp: AXUIElement) -> [AXUIElement] {
        if let focusedWindow = copyElement(axApp, attribute: kAXFocusedWindowAttribute) {
            return [focusedWindow]
        }
        if let windows = copyElements(axApp, attribute: kAXWindowsAttribute), !windows.isEmpty {
            return windows
        }
        return [axApp]
    }

    private func buildNode(
        element: AXUIElement,
        depth: Int,
        maxDepth: Int,
        remainingNodes: inout Int,
        cache: inout [String: ResolvedElement]
    ) -> UINode? {
        guard remainingNodes > 0 else { return nil }
        remainingNodes -= 1

        let id = UUID().uuidString
        let role = copyString(element, attribute: kAXRoleAttribute)
        let subrole = copyString(element, attribute: kAXSubroleAttribute)
        let title = copyString(element, attribute: kAXTitleAttribute)
        let label = copyString(element, attribute: kAXDescriptionAttribute) ?? copyString(element, attribute: kAXIdentifierAttribute)
        let value = stringify(copyAttribute(element, attribute: kAXValueAttribute))
        let nodeDescription = copyString(element, attribute: kAXHelpAttribute)
        let frame = copyFrame(element)
        let actions = copyActionNames(element)

        cache[id] = ResolvedElement(element: element, frame: frame, role: role, title: title, label: label, value: value)

        let children: [UINode]
        if depth < maxDepth, let rawChildren = copyElements(element, attribute: kAXChildrenAttribute) {
            children = rawChildren.compactMap {
                buildNode(element: $0, depth: depth + 1, maxDepth: maxDepth, remainingNodes: &remainingNodes, cache: &cache)
            }
        } else {
            children = []
        }

        return UINode(
            id: id,
            role: role,
            subrole: subrole,
            title: title,
            label: label,
            value: value,
            nodeDescription: nodeDescription,
            frame: frame,
            actions: actions,
            children: children
        )
    }

    internal func searchText(in element: AXUIElement, needle: String, remainingDepth: Int, seen: inout Int, maxNodes: Int) -> Bool {
        seen += 1
        if seen > maxNodes { return false }
        let haystacks = [
            copyString(element, attribute: kAXTitleAttribute),
            copyString(element, attribute: kAXDescriptionAttribute),
            copyString(element, attribute: kAXHelpAttribute),
            stringify(copyAttribute(element, attribute: kAXValueAttribute)),
        ].compactMap { $0?.lowercased() }

        if haystacks.contains(where: { $0.contains(needle) }) {
            return true
        }

        guard remainingDepth > 0, let children = copyElements(element, attribute: kAXChildrenAttribute) else {
            return false
        }

        for child in children where searchText(in: child, needle: needle, remainingDepth: remainingDepth - 1, seen: &seen, maxNodes: maxNodes) {
            return true
        }
        return false
    }

    private func findMenuChild(parent: AXUIElement, title: String) -> AXUIElement? {
        let normalized = title.lowercased()

        let immediateChildren = (copyElements(parent, attribute: kAXChildrenAttribute) ?? [])
            + (copyElements(parent, attribute: kAXMenuBarAttribute) ?? [])
            + (copyElements(parent, attribute: "AXMenu") ?? [])
            + (copyElements(parent, attribute: kAXContentsAttribute) ?? [])

        for child in immediateChildren {
            let options = [
                copyString(child, attribute: kAXTitleAttribute),
                copyString(child, attribute: kAXDescriptionAttribute),
            ].compactMap { $0?.lowercased() }
            if options.contains(where: { $0 == normalized || $0.contains(normalized) }) {
                return child
            }
            if let submenu = copyElement(child, attribute: "AXMenu") {
                let submenuOptions = [
                    copyString(submenu, attribute: kAXTitleAttribute),
                    copyString(submenu, attribute: kAXDescriptionAttribute),
                ].compactMap { $0?.lowercased() }
                if submenuOptions.contains(where: { $0 == normalized || $0.contains(normalized) }) {
                    return submenu
                }
            }
        }

        return nil
    }
}

private func copyAttribute(_ element: AXUIElement, attribute: String) -> AnyObject? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard result == .success, let value else { return nil }
    return value
}

private func copyElement(_ element: AXUIElement, attribute: String) -> AXUIElement? {
    guard let value = copyAttribute(element, attribute: attribute) else { return nil }
    return (value as! AXUIElement) // swiftlint:disable:this force_cast
}

private func copyElements(_ element: AXUIElement, attribute: String) -> [AXUIElement]? {
    copyAttribute(element, attribute: attribute) as? [AXUIElement]
}

private func copyString(_ element: AXUIElement, attribute: String) -> String? {
    copyAttribute(element, attribute: attribute) as? String
}

private func copyFrame(_ element: AXUIElement) -> RectValue? {
    guard
        let positionValue = copyAttribute(element, attribute: kAXPositionAttribute),
        let sizeValue = copyAttribute(element, attribute: kAXSizeAttribute)
    else {
        return nil
    }

    var point = CGPoint.zero
    var size = CGSize.zero

    guard
        AXValueGetType(positionValue as! AXValue) == .cgPoint, // swiftlint:disable:this force_cast
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &point), // swiftlint:disable:this force_cast
        AXValueGetType(sizeValue as! AXValue) == .cgSize, // swiftlint:disable:this force_cast
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) // swiftlint:disable:this force_cast
    else {
        return nil
    }

    return RectValue(x: point.x, y: point.y, width: size.width, height: size.height)
}

private func copyActionNames(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    let result = AXUIElementCopyActionNames(element, &names)
    guard result == .success, let array = names as? [String] else { return [] }
    return array
}

private func stringify(_ value: AnyObject?) -> String? {
    switch value {
    case let string as String:
        return string
    case let number as NSNumber:
        return number.stringValue
    default:
        return nil
    }
}
