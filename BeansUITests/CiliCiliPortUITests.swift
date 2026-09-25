import XCTest

@MainActor
final class CiliCiliPortUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testUpstreamChannelsInsideBeansLayout() {
        let app = XCUIApplication()
        app.launchArguments = ["--beans-ui-smoke"]
        app.launch()
        defer { capture(app, name: "Beans-CiliCili-home-final") }
        dismissStartupOverlays(in: app)
        XCTAssertTrue(app.buttons["beans.bilibili.channel.home"].waitForExistence(timeout: 20))
        for tab in ["dynamic", "live", "search", "mine", "home"] {
            let channel = hittableChannel(app, tab: tab)
            XCTAssertTrue(channel.isHittable)
            channel.tap()
            XCTAssertTrue(waitForSelectedChannel(app, tab: tab))
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
        defer { capture(app, name: "CiliCili-detail-final") }
        dismissStartupOverlays(in: app)
        let picker = app.descendants(matching: .any)["video.detail.toolbar-picker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 25))
        XCTAssertEqual(picker.buttons.count, 2)
        for _ in 0..<4 {
            dismissStartupOverlays(in: app)
            XCTAssertTrue(picker.isHittable)
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

    private func dismissStartupOverlays(in app: XCUIApplication) {
        // These are Beans' ordinary first-launch screens, not Bilibili errors.
        // Close them through their real buttons; never suppress alerts/sheets
        // in production or change the Bilibili test assertions.
        for _ in 0..<2 {
            let announcement = app.buttons["知道了"].firstMatch
            if announcement.waitForExistence(timeout: 1), announcement.isHittable { announcement.tap() }
            let changelog = app.buttons["开始使用"].firstMatch
            if changelog.waitForExistence(timeout: 1), changelog.isHittable { changelog.tap() }
        }
    }

    private func hittableChannel(_ app: XCUIApplication, tab: String) -> XCUIElement {
        let channels = app.buttons.matching(identifier: "beans.bilibili.channel.\(tab)")
        for index in 0..<channels.count {
            let candidate = channels.element(boundBy: index)
            if candidate.isHittable { return candidate }
        }
        return channels.firstMatch
    }

    private func waitForSelectedChannel(_ app: XCUIApplication, tab: String) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        let channels = app.buttons.matching(identifier: "beans.bilibili.channel.\(tab)")
        while Date() < deadline {
            for index in 0..<channels.count {
                let candidate = channels.element(boundBy: index)
                if candidate.isHittable && candidate.isSelected { return true }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
