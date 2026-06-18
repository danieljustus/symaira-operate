import Foundation

public struct UpdateChecker {
    private let currentVersion: String
    private let repoOwner: String
    private let repoName: String

    public init(currentVersion: String = SymOperateVersion.current, repoOwner: String = "danieljustus", repoName: String = "symaira-operate") {
        self.currentVersion = currentVersion
        self.repoOwner = repoOwner
        self.repoName = repoName
    }

    public struct UpdateInfo: Codable, Sendable {
        public let updateAvailable: Bool
        public let latestVersion: String?
        public let currentVersion: String
        public let releaseURL: String?

        public init(updateAvailable: Bool, latestVersion: String?, currentVersion: String, releaseURL: String?) {
            self.updateAvailable = updateAvailable
            self.latestVersion = latestVersion
            self.currentVersion = currentVersion
            self.releaseURL = releaseURL
        }
    }

    public func checkForUpdate() -> UpdateInfo {
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else {
            return UpdateInfo(updateAvailable: false, latestVersion: nil, currentVersion: currentVersion, releaseURL: nil)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result = UpdateInfo(updateAvailable: false, latestVersion: nil, currentVersion: currentVersion, releaseURL: nil)

        let task = URLSession.shared.dataTask(with: url) { data, _, _ in
            defer { semaphore.signal() }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else { return }

            let latest = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            let available = self.isNewer(latest, than: self.currentVersion)
            let htmlURL = json["html_url"] as? String

            result = UpdateInfo(updateAvailable: available, latestVersion: latest, currentVersion: self.currentVersion, releaseURL: htmlURL)
        }
        task.resume()
        semaphore.wait()

        return result
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
