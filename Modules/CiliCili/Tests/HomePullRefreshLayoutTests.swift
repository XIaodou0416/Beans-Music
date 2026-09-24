import XCTest
import SwiftUI
@testable import CiliCiliKit

final class HomePullRefreshLayoutTests: XCTestCase {
    @MainActor
    func testRefreshingReservesStableTopInset() {
        XCTAssertEqual(
            HomePullRefreshLayout.topInset(isRefreshing: true),
            HomePullRefreshLayout.refreshingTopInset
        )
        XCTAssertEqual(HomePullRefreshLayout.refreshingTopInset, 52)
    }

    @MainActor
    func testIdleLayoutDoesNotReserveSpace() {
        XCTAssertEqual(HomePullRefreshLayout.topInset(isRefreshing: false), 0)
    }

    func testCustomIndicatorClampsPullProgress() {
        XCTAssertEqual(
            HomePullRefreshIndicator.normalizedProgress(
                pullDistance: -20,
                triggerDistance: 100
            ),
            0
        )
        XCTAssertEqual(
            HomePullRefreshIndicator.normalizedProgress(
                pullDistance: 50,
                triggerDistance: 100
            ),
            0.5
        )
        XCTAssertEqual(
            HomePullRefreshIndicator.normalizedProgress(
                pullDistance: 120,
                triggerDistance: 100
            ),
            1
        )
    }

    func testCustomIndicatorDoesNotReappearWhileRefreshLayoutSettles() {
        XCTAssertFalse(
            HomePullRefreshIndicator.shouldShowIndicator(
                progress: 0.74,
                isRefreshing: false,
                suppressesPullProgress: true
            )
        )
        XCTAssertTrue(
            HomePullRefreshIndicator.shouldShowIndicator(
                progress: 0.74,
                isRefreshing: false,
                suppressesPullProgress: false
            )
        )
        XCTAssertTrue(
            HomePullRefreshIndicator.shouldShowIndicator(
                progress: 0,
                isRefreshing: true,
                suppressesPullProgress: true
            )
        )
    }

    func testRelativePullDistanceUsesContentOffsetAndTopInset() {
        XCTAssertEqual(
            HomePullRefreshGeometry.distance(contentOffsetY: -140, contentInsetTop: 100),
            40
        )
        XCTAssertEqual(
            HomePullRefreshGeometry.distance(contentOffsetY: -100, contentInsetTop: 100),
            0
        )
        XCTAssertEqual(
            HomePullRefreshGeometry.distance(contentOffsetY: 20, contentInsetTop: 100),
            0
        )
    }

    func testOnlyTrackingAndInteractingPhasesCountAsUserInteraction() {
        XCTAssertTrue(HomePullRefreshGeometry.isUserInteracting(.tracking))
        XCTAssertTrue(HomePullRefreshGeometry.isUserInteracting(.interacting))
        XCTAssertFalse(HomePullRefreshGeometry.isUserInteracting(.decelerating))
        XCTAssertFalse(HomePullRefreshGeometry.isUserInteracting(.animating))
        XCTAssertFalse(HomePullRefreshGeometry.isUserInteracting(.idle))
    }

    @MainActor
    func testArmedRefreshCanBeCancelledAndRearmedBeforeRelease() {
        let actions = HomeFeedRefreshActions()

        actions.handleConfiguredPullRefresh(
            pullDistance: 100,
            triggerDistance: 100,
            isUserInteracting: true,
            isRefreshing: false
        ) { true }
        XCTAssertEqual(actions.phase, .armed)

        actions.handleConfiguredPullRefresh(
            pullDistance: 90,
            triggerDistance: 100,
            isUserInteracting: true,
            isRefreshing: false
        ) { true }
        XCTAssertEqual(actions.phase, .dragging)

        actions.handleConfiguredPullRefresh(
            pullDistance: 110,
            triggerDistance: 100,
            isUserInteracting: true,
            isRefreshing: false
        ) { true }
        XCTAssertEqual(actions.phase, .armed)
    }

    @MainActor
    func testConfiguredRefreshRequiresDragAndTriggersOnceOnRelease() async {
        let actions = HomeFeedRefreshActions()
        var refreshCount = 0
        let firstRefresh = expectation(description: "first refresh")

        actions.handleConfiguredPullRefresh(
            pullDistance: 120,
            triggerDistance: 100,
            isUserInteracting: false,
            isRefreshing: false
        ) {
            XCTFail("Non-user geometry changes must not refresh")
            return true
        }
        XCTAssertEqual(actions.phase, .idle)

        actions.handleConfiguredPullRefresh(
            pullDistance: 40,
            triggerDistance: 100,
            isUserInteracting: true,
            isRefreshing: false
        ) {
            XCTFail("A sub-threshold drag must not refresh")
            return true
        }
        XCTAssertEqual(actions.phase, .dragging)

        actions.handleConfiguredPullRefresh(
            pullDistance: 100,
            triggerDistance: 100,
            isUserInteracting: true,
            isRefreshing: false
        ) {
            XCTFail("Crossing the threshold must wait for release")
            return true
        }
        XCTAssertEqual(actions.phase, .armed)

        actions.handleConfiguredPullRefresh(
            pullDistance: 100,
            triggerDistance: 100,
            isUserInteracting: false,
            isRefreshing: false
        ) {
            refreshCount += 1
            firstRefresh.fulfill()
            return true
        }
        XCTAssertEqual(actions.phase, .refreshing)
        await fulfillment(of: [firstRefresh], timeout: 1)
        await Task.yield()
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(actions.phase, .settling)

        actions.handleConfiguredPullRefresh(
            pullDistance: 140,
            triggerDistance: 100,
            isUserInteracting: true,
            isRefreshing: false
        ) {
            refreshCount += 1
            return true
        }
        XCTAssertEqual(refreshCount, 1)

        try? await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(actions.phase, .settling)

        actions.handleConfiguredPullRefresh(
            pullDistance: 0,
            triggerDistance: 100,
            isUserInteracting: false,
            isRefreshing: false
        ) {
            refreshCount += 1
            return true
        }
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(actions.phase, .idle)

        let secondRefresh = expectation(description: "second refresh")
        actions.handleConfiguredPullRefresh(
            pullDistance: 110,
            triggerDistance: 100,
            isUserInteracting: true,
            isRefreshing: false
        ) {
            refreshCount += 1
            secondRefresh.fulfill()
            return true
        }
        actions.handleConfiguredPullRefresh(
            pullDistance: 110,
            triggerDistance: 100,
            isUserInteracting: false,
            isRefreshing: false
        ) {
            refreshCount += 1
            secondRefresh.fulfill()
            return true
        }
        await fulfillment(of: [secondRefresh], timeout: 1)
        XCTAssertEqual(refreshCount, 2)
    }

    func testProgrammaticNativeRefreshUsesSingleRevealDistance() {
        XCTAssertEqual(
            HomeNativeRefreshLayout.targetOffsetY(restingTopOffsetY: -96),
            -140
        )
    }

    @MainActor
    func testProgrammaticRefreshRequestsAreDistinct() {
        let actions = HomeFeedScrollActions()

        actions.requestProgrammaticRefresh()
        XCTAssertEqual(actions.programmaticRefreshRequestID, 1)

        actions.requestProgrammaticRefresh()
        XCTAssertEqual(actions.programmaticRefreshRequestID, 2)
    }

    @MainActor
    func testNativeRefreshModeIsControlledOnlyByFormalSetting() {
        let suiteName = "cc.bili.tests.native-pull-refresh-mode.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LibraryStore(userDefaults: defaults)

        XCTAssertTrue(store.usesNativePullRefresh)
        XCTAssertFalse(store.usesCustomPullRefresh)

        store.setNativePullRefreshEnabled(false)
        store.setHomeRefreshTriggerDistance(LibraryStore.defaultHomeRefreshTriggerDistance)

        XCTAssertFalse(store.usesNativePullRefresh)
        XCTAssertTrue(store.usesCustomPullRefresh)
    }

    @MainActor
    func testStoredCustomDistanceIsPreservedWhileNativeRefreshDefaultsOn() {
        let suiteName = "cc.bili.tests.native-pull-refresh-distance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(140.0, forKey: "cc.bili.home.refreshTriggerDistance.v1")

        let store = LibraryStore(userDefaults: defaults)

        XCTAssertTrue(store.usesNativePullRefresh)
        XCTAssertEqual(store.homeRefreshTriggerDistance, 140)

        store.setNativePullRefreshEnabled(false)

        XCTAssertTrue(store.usesCustomPullRefresh)
        XCTAssertEqual(store.homeRefreshTriggerDistance, 140)
    }

}
