import Foundation

public struct ActionPolicy: Codable, Sendable {
    public var extraDenyKeywords: Set<String>
    public var allowedKeywords: Set<String>
    public var allowedBundleIDs: Set<String>

    public init(
        extraDenyKeywords: Set<String> = [],
        allowedKeywords: Set<String> = [],
        allowedBundleIDs: Set<String> = []
    ) {
        self.extraDenyKeywords = extraDenyKeywords
        self.allowedKeywords = allowedKeywords
        self.allowedBundleIDs = allowedBundleIDs
    }

    static let defaultDenyKeywords: Set<String> = [
        "delete", "remove", "erase", "clear", "trash",
        "uninstall", "allow", "authorize", "unlock",
        "quit", "terminate", "force quit", "shutdown"
    ]

    public func isDestructive(role: String?, title: String?, label: String?, value: String?, bundleID: String? = nil) -> Bool {
        if let bundleID, allowedBundleIDs.contains(bundleID) {
            return false
        }

        let allDenyKeywords = Self.defaultDenyKeywords.union(extraDenyKeywords)
        let inputs = [role, title, label, value].compactMap { $0?.lowercased() }
        for input in inputs {
            for keyword in allDenyKeywords {
                if input.contains(keyword) {
                    let keywordBase = String(keyword.prefix(while: { $0 != " " }))
                    if allowedKeywords.contains(keywordBase) {
                        continue
                    }
                    return true
                }
            }
        }
        return false
    }

    public mutating func addDenyKeyword(_ keyword: String) {
        extraDenyKeywords.insert(keyword.lowercased())
    }

    public mutating func allowKeyword(_ keyword: String) {
        allowedKeywords.insert(keyword.lowercased())
    }

    public mutating func allowBundleID(_ bundleID: String) {
        allowedBundleIDs.insert(bundleID)
    }
}
