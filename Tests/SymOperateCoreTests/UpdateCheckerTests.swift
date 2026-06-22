import XCTest
@testable import SymOperateCore

final class UpdateCheckerTests: XCTestCase {
    override func setUpWithError() throws {
        UpdateChecker.clearCache()
    }

    func testUpdateInfoErrorFieldIsNilByDefault() {
        let info = UpdateChecker.UpdateInfo(
            updateAvailable: false,
            latestVersion: nil,
            currentVersion: "1.0.0",
            releaseURL: nil
        )
        XCTAssertNil(info.error)
    }

    func testUpdateInfoErrorFieldRoundTripsThroughCodable() throws {
        let info = UpdateChecker.UpdateInfo(
            updateAvailable: false,
            latestVersion: nil,
            currentVersion: "1.0.0",
            releaseURL: nil,
            error: "Update check timed out after 8s"
        )
        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(UpdateChecker.UpdateInfo.self, from: data)
        XCTAssertEqual(decoded.error, "Update check timed out after 8s")
        XCTAssertFalse(decoded.updateAvailable)
    }

    func testCheckForUpdateReturnsErrorForInvalidRepo() async {
        let checker = UpdateChecker(
            currentVersion: "1.0.0",
            repoOwner: "nonexistent-owner-xyz-999",
            repoName: "nonexistent-repo-xyz-999"
        )
        let info = await checker.checkForUpdate()
        XCTAssertNotNil(info.error, "Expected error for nonexistent repo")
        XCTAssertFalse(info.updateAvailable)
        XCTAssertEqual(info.currentVersion, "1.0.0")
    }

    func testCheckForUpdateReturnsCachedResultOnSecondCall() async {
        let checker = UpdateChecker(
            currentVersion: "1.0.0",
            repoOwner: "nonexistent-owner-xyz-999",
            repoName: "nonexistent-repo-xyz-999"
        )
        let first = await checker.checkForUpdate()
        let second = await checker.checkForUpdate()
        XCTAssertEqual(first.error, second.error)
        XCTAssertEqual(first.currentVersion, second.currentVersion)
    }

    func testClearCacheAllowsFreshCheck() async {
        let checker = UpdateChecker(
            currentVersion: "1.0.0",
            repoOwner: "nonexistent-owner-xyz-999",
            repoName: "nonexistent-repo-xyz-999"
        )
        let first = await checker.checkForUpdate()
        UpdateChecker.clearCache()
        let second = await checker.checkForUpdate()
        XCTAssertEqual(first.error, second.error)
    }

    func testTimeoutIntervalIsEightSeconds() {
        XCTAssertEqual(UpdateChecker.timeoutInterval, 8)
    }

    func testCheckForUpdateWithTimeoutError() async {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1
        config.timeoutIntervalForResource = 1
        let session = URLSession(configuration: config)

        let checker = UpdateChecker(
            currentVersion: "1.0.0",
            repoOwner: "nonexistent-owner-xyz-999",
            repoName: "nonexistent-repo-xyz-999",
            session: session
        )
        let info = await checker.checkForUpdate()
        XCTAssertNotNil(info.error, "Expected error for connection failure")
        XCTAssertFalse(info.updateAvailable)
    }
}
