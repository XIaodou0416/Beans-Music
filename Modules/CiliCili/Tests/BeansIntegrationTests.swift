import XCTest
@testable import CiliCiliKit

@MainActor
final class BeansIntegrationTests: XCTestCase {
    func testCredentialComparisonIgnoresOrderingAndAnonymousFingerprint() {
        let first = CiliCiliRuntime.cookieValues("SESSDATA=token==; DedeUserID=1; bili_jct=csrf; buvid3=a")
        let second = CiliCiliRuntime.cookieValues("buvid3=b; bili_jct=csrf; DedeUserID=1; SESSDATA=token==")
        XCTAssertEqual(first["SESSDATA"], "token==")
        XCTAssertEqual(CiliCiliRuntime.credentialIdentity(first), CiliCiliRuntime.credentialIdentity(second))
    }

    func testAccountSwitchAndLogoutChangeCredentialIdentity() {
        let first = CiliCiliRuntime.cookieValues("SESSDATA=a; DedeUserID=1")
        let second = CiliCiliRuntime.cookieValues("SESSDATA=b; DedeUserID=2")
        XCTAssertNotEqual(CiliCiliRuntime.credentialIdentity(first), CiliCiliRuntime.credentialIdentity(second))
        XCTAssertNotEqual(CiliCiliRuntime.credentialIdentity(first), CiliCiliRuntime.credentialIdentity([:]))
    }

    func testIndependentNavigationHostsCannotDismissEachOther() {
        let runtime = CiliCiliRuntime.shared
        let home = UUID(), history = UUID()
        defer {
            runtime.setNavigationActive(false, owner: home)
            runtime.setNavigationActive(false, owner: history)
        }
        runtime.setNavigationActive(true, owner: home)
        runtime.setNavigationActive(true, owner: home)
        runtime.setNavigationActive(true, owner: history)
        runtime.setNavigationActive(false, owner: home)
        XCTAssertTrue(runtime.isDetailActive)
        runtime.setNavigationActive(false, owner: history)
        XCTAssertFalse(runtime.isDetailActive)
    }

    func testPlaybackOwnershipFollowsPlayerReplacementAndStop() {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()
        let first = PlayerStateViewModel(videoURL: nil, audioURL: nil, title: "first", referer: "https://www.bilibili.com")
        let second = PlayerStateViewModel(videoURL: nil, audioURL: nil, title: "second", referer: "https://www.bilibili.com")
        defer { coordinator.stopActivePlayback() }
        coordinator.activate(first)
        XCTAssertTrue(CiliCiliRuntime.hasActivePlayback)
        coordinator.activate(second)
        coordinator.unregister(first)
        XCTAssertTrue(CiliCiliRuntime.hasActivePlayback)
        coordinator.deactivate(second)
        XCTAssertFalse(CiliCiliRuntime.hasActivePlayback)
    }
}
