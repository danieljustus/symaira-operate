import Foundation

public struct UpdateChecker: Sendable {
    private let currentVersion: String
    private let repoOwner: String
    private let repoName: String
    private let session: URLSession

    public init(currentVersion: String = SymOperateVersion.current, repoOwner: String = "danieljustus", repoName: String = "symaira-operate") {
        self.currentVersion = currentVersion
        self.repoOwner = repoOwner
        self.repoName = repoName
        self.session = .shared
    }

    init(currentVersion: String, repoOwner: String, repoName: String, session: URLSession) {
        self.currentVersion = currentVersion
        self.repoOwner = repoOwner
        self.repoName = repoName
        self.session = session
    }

    public struct UpdateInfo: Codable, Sendable {
        public let updateAvailable: Bool
        public let latestVersion: String?
        public let currentVersion: String
        public let releaseURL: String?
        public let error: String?

        public init(updateAvailable: Bool, latestVersion: String?, currentVersion: String, releaseURL: String?, error: String? = nil) {
            self.updateAvailable = updateAvailable
            self.latestVersion = latestVersion
            self.currentVersion = currentVersion
            self.releaseURL = releaseURL
            self.error = error
        }
    }

    private static let cache = UpdateCache()
    static let timeoutInterval: TimeInterval = 8

    static func clearCache() {
        cache.clear()
    }

    public func checkForUpdate() async -> UpdateInfo {
        if let cached = Self.cache.get() {
            return cached
        }

        let result = await performNetworkCheck()
        Self.cache.set(result)
        return result
    }

    private func performNetworkCheck() async -> UpdateInfo {
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else {
            return UpdateInfo(
                updateAvailable: false,
                latestVersion: nil,
                currentVersion: currentVersion,
                releaseURL: nil,
                error: "Invalid release URL"
            )
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Self.timeoutInterval
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await session.data(for: request)

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                return UpdateInfo(
                    updateAvailable: false,
                    latestVersion: nil,
                    currentVersion: currentVersion,
                    releaseURL: nil,
                    error: "Failed to parse release data"
                )
            }

            let latest = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            let available = isNewer(latest, than: currentVersion)
            let htmlURL = json["html_url"] as? String

            return UpdateInfo(
                updateAvailable: available,
                latestVersion: latest,
                currentVersion: currentVersion,
                releaseURL: htmlURL
            )
        } catch let error as URLError where error.code == .timedOut {
            return UpdateInfo(
                updateAvailable: false,
                latestVersion: nil,
                currentVersion: currentVersion,
                releaseURL: nil,
                error: "Update check timed out after \(Int(Self.timeoutInterval))s"
            )
        } catch {
            return UpdateInfo(
                updateAvailable: false,
                latestVersion: nil,
                currentVersion: currentVersion,
                releaseURL: nil,
                error: "Update check failed: \(error.localizedDescription)"
            )
        }
    }

    private func isNewer(_ version: String, than current: String) -> Bool {
        let latestParts = version.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let count = max(latestParts.count, currentParts.count)

        for i in 0..<count {
            let l = i < latestParts.count ? latestParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if l > c { return true }
            if l < c { return false }
        }
        return false
    }
}

// MARK: - Process-lifetime cache

private final class UpdateCache: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UpdateChecker.UpdateInfo?

    func get() -> UpdateChecker.UpdateInfo? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ info: UpdateChecker.UpdateInfo) {
        lock.lock()
        defer { lock.unlock() }
        value = info
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        value = nil
    }
}
