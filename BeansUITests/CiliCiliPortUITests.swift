import XCTest

@MainActor
final class CiliCiliPortUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testUpstreamChannelsInsideBeansLayout() {
        let app = XCUIApplication()
        app.launchArguments = ["--beans-ui-smoke"]
        app.launch()
        XCTAssertTrue(app.buttons["beans.bilibili.channel.home"].waitForExistence(timeout: 20))
        for tab in ["dynamic", "live", "search", "mine", "home"] {
            let channel = app.buttons["beans.bilibili.channel.\(tab)"]
            XCTAssertTrue(channel.isHittable)
            channel.tap()
            XCTAssertTrue(app.buttons["beans.bilibili.channel.\(tab)"].isSelected)
        }
        XCTAssertEqual(app.tabBars.count, 1, "Beans 应只有一套底栏")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Beans-CiliCili-home"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLoadingDetailTabsDoNotPresentRepeatedSheets() {
        let app = XCUIApplication()
        app.launchArguments = ["--beans-ui-smoke", "--start-bvid", "BV1xx411c7mD"]
        app.launch()
        let picker = app.descendants(matching: .any)["video.detail.toolbar-picker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 25))
        XCTAssertEqual(picker.buttons.count, 2)
        for _ in 0..<4 {
            picker.buttons.element(boundBy: 1).tap()
            XCTAssertTrue(app.buttons["video.detail.toolbar-comment-compose"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.sheets.count, 0)
            XCTAssertEqual(app.alerts.count, 0)
            picker.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(picker.isHittable)
        }
        picker.buttons.element(boundBy: 1).tap()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "CiliCili-detail-comments"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertLessThanOrEqual(picker.frame.maxY, app.windows.firstMatch.frame.maxY)
        XCTAssertGreaterThan(picker.frame.minY, app.windows.firstMatch.frame.midY)
    }
}
