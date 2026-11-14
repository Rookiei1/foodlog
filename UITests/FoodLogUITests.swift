import XCTest

final class FoodLogUITests: XCTestCase {
    func testFiveTabsAndCameraRecognitionSheetLaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-FoodLogInMemoryStore", "-FoodLogSeedSample"]
        app.launch()

        // Verify Home dashboard and floating camera button
        let cameraButton = app.buttons["floating-camera-record-button"]
        XCTAssertTrue(cameraButton.waitForExistence(timeout: 8))

        cameraButton.tap()
        let closeButton = app.buttons["关闭"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        closeButton.tap()

        // Navigate across all 5 bottom tabs
        app.tabBars.buttons["饮食"].tap()
        XCTAssertTrue(app.navigationBars["饮食记录"].waitForExistence(timeout: 4))

        app.tabBars.buttons["体重"].tap()
        XCTAssertTrue(app.navigationBars["每日体重"].waitForExistence(timeout: 4))

        app.tabBars.buttons["AI 分析"].tap()
        XCTAssertTrue(app.navigationBars["AI 综合分析"].waitForExistence(timeout: 4))

        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.navigationBars["设置与数据管理"].waitForExistence(timeout: 4))

        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(cameraButton.waitForExistence(timeout: 4))
    }
}
