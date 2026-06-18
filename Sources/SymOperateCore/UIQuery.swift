// swiftlint:disable:next cyclomatic_complexity line_length for_where
import Foundation

public struct UIElementPredicate: Codable, Sendable {
    public let role: String?
    public let title: String?
    public let label: String?
    public let value: String?
    public let subrole: String?
    public let actions: [String]?

    public init(
        role: String? = nil,
        title: String? = nil,
        label: String? = nil,
        value: String? = nil,
        subrole: String? = nil,
        actions: [String]? = nil
    ) {
        self.role = role
        self.title = title
        self.label = label
        self.value = value
        self.subrole = subrole
        self.actions = actions
    }

    public func matches(node: UINode) -> Bool {
        if let role, !matchField(node.role, pattern: role) { return false }
        if let title, !matchField(node.title, pattern: title) { return false }
        if let label, !matchField(node.label, pattern: label) { return false }
        if let value, !matchField(node.value, pattern: value) { return false }
        if let subrole, !matchField(node.subrole, pattern: subrole) { return false }
        if let actions {
            let nodeActions = Set(node.actions)
            for action in actions where !nodeActions.contains(action) { return false }
        }
        return true
    }

    private func matchField(_ field: String?, pattern: String) -> Bool {
        guard let field else { return false }
        if pattern.hasPrefix("/") && pattern.hasSuffix("/") {
            let regex = String(pattern.dropFirst().dropLast())
            return field.range(of: regex, options: .regularExpression) != nil
        }
        return field.localizedCaseInsensitiveContains(pattern)
    }
}

public struct UIQueryService {
    public init() {}

    public func findNodes(in nodes: [UINode], predicate: UIElementPredicate) -> [UINode] {
        var results: [UINode] = []
        for node in nodes {
            if predicate.matches(node: node) {
                results.append(node)
            }
            results.append(contentsOf: findNodes(in: node.children, predicate: predicate))
        }
        return results
    }

    public func findFirstNode(in nodes: [UINode], predicate: UIElementPredicate) -> UINode? {
        for node in nodes {
            if predicate.matches(node: node) { return node }
            if let found = findFirstNode(in: node.children, predicate: predicate) { return found }
        }
        return nil
    }
}
