import XCTest

final class FoodLogUITests: XCTestCase {
    func testThreeTabsAndRefactoredCoreFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["-FoodLogInMemoryStore", "-FoodLogSeedSample"]
        app.launch()

        // 1. Verify Home dashboard core components
        let cameraButton = app.buttons["floating-camera-record-button"]
        XCTAssertTrue(cameraButton.waitForExistence(timeout: 8), "AI floating camera button must exist")

        let manualAddButton = app.buttons["dashboard-manual-add-button"]
        XCTAssertTrue(manualAddButton.exists, "Manual add button must exist")

        let calorieNumeral = app.staticTexts["today-calories-value"]
        XCTAssertTrue(calorieNumeral.exists, "Magazine calorie numeral must exist")

        // Test opening and closing AI Photo recognition sheet
        cameraButton.tap()
        let closeButton = app.buttons["关闭"]
        if closeButton.waitForExistence(timeout: 5) {
            closeButton.tap()
        }

        // 2. Navigate to History tab (Tab 2)
        let historyTab = app.tabBars.buttons["历史"]
        XCTAssertTrue(historyTab.waitForExistence(timeout: 4), "History tab must exist")
        historyTab.tap()

        let exportCSVButton = app.buttons["history-export-csv-button"]
        XCTAssertTrue(exportCSVButton.waitForExistence(timeout: 4), "History export CSV button must exist")

        // 3. Navigate to Settings tab (Tab 3)
        let settingsTab = app.tabBars.buttons["设置"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 4), "Settings tab must exist")
        settingsTab.tap()

        let testConnectionButton = app.buttons["settings-test-connection-button"]
        XCTAssertTrue(testConnectionButton.waitForExistence(timeout: 4), "Settings DeepSeek test connection button must exist")

        // 4. Return to Home dashboard
        let homeTab = app.tabBars.buttons["首页"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 4), "Dashboard home tab must exist")
        homeTab.tap()
        XCTAssertTrue(cameraButton.waitForExistence(timeout: 4))
    }
}
