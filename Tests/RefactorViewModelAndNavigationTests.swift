import XCTest
import SwiftUI
@testable import FoodLog

final class RefactorViewModelAndNavigationTests: XCTestCase {

    // MARK: - 1. Three-Tab Navigation Structure Tests (R1)

    @MainActor
    func testThreeTabRootNavigationState() {
        XCTAssertEqual(MainTab.allCases.count, 3, "Root navigation must strictly have 3 tabs: dashboard, history, settings")
        let tabRawValues = MainTab.allCases.map(\.rawValue)
        XCTAssertEqual(tabRawValues, ["dashboard", "history", "settings"])

        let titles = MainTab.allCases.map(\.title)
        XCTAssertEqual(titles, ["首页", "历史", "设置"])

        let suiteName = "foodlog-nav-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let vm = AppStateViewModel(userDefaults: defaults, keychain: InMemoryKeychainStore())
        XCTAssertEqual(vm.activeTab, .dashboard)

        vm.activeTab = .history
        XCTAssertEqual(vm.activeTab, .history)

        vm.activeTab = .settings
        XCTAssertEqual(vm.activeTab, .settings)
    }

    // MARK: - 2. History Segment State Switching Tests (R4)

    func testHistorySegmentCases() {
        XCTAssertEqual(HistoryView.HistorySegment.allCases.count, 2)
        XCTAssertEqual(HistoryView.HistorySegment.food.rawValue, "饮食明细")
        XCTAssertEqual(HistoryView.HistorySegment.weight.rawValue, "体重记录")
    }

    // MARK: - 3. Target Calorie & Biometric Updates & Recalculation (R2)

    func testBiometricRecalculationWithMifflinStJeorFormula() {
        var profile = UserProfileSettings(
            heightCm: 180.0,
            currentWeightKg: 75.0,
            targetWeightKg: 75.0,
            age: 28,
            sex: .male,
            activityLevel: .moderate,
            goalMode: .maintain
        )

        let initialTargets = profile.computeRecommendedTargets()
        // Mifflin-St Jeor: (10 * 75) + (6.25 * 180) - (5 * 28) + 5 = 750 + 1125 - 140 + 5 = 1740 BMR
        // TDEE: 1740 * 1.55 = 2697 kcal
        XCTAssertEqual(initialTargets.bmr, 1740)
        XCTAssertEqual(initialTargets.tdee, 2697)
        XCTAssertEqual(initialTargets.targetCalories, 2697)

        // Apply recommended targets
        profile.applyRecommendedTargets()
        XCTAssertEqual(profile.targetCalories, 2697)
        XCTAssertEqual(profile.targetProteinGrams, (75.0 * 1.6).rounded())

        // Test weight loss mode
        profile.goalMode = .loseFat
        let lossTargets = profile.computeRecommendedTargets()
        XCTAssertEqual(lossTargets.targetCalories, 2697 - 400) // 2297 kcal
        XCTAssertEqual(lossTargets.targetProteinGrams, (75.0 * 2.0).rounded()) // 150g

        // Test weight gain mode
        profile.goalMode = .gainWeight
        let gainTargets = profile.computeRecommendedTargets()
        XCTAssertEqual(gainTargets.targetCalories, 2697 + 350) // 3047 kcal
    }

    // MARK: - 4. DeepSeek Flash Configuration & Smooth Fallback Mock (R3)

    func testDeepSeekDefaultProviderIsFlash() {
        let providers = AIProviderConfig.defaultProviders()
        guard let deepSeek = providers.first(where: { $0.kind == .deepSeek }) else {
            XCTFail("DeepSeek provider must be registered in default providers")
            return
        }
        XCTAssertEqual(deepSeek.modelName, "flash", "Default model for DeepSeek must be flash")
        XCTAssertEqual(deepSeek.baseURL, "https://api.deepseek.com/v1")
        XCTAssertTrue(deepSeek.supportsVision, "DeepSeek flash must support vision")
    }

    func testDeepSeekMissingKeySmoothFallbackToMockWithoutError() async throws {
        let deepSeekConfig = AIProviderConfig(
            id: UUID(),
            name: "DeepSeek API",
            kind: .deepSeek,
            baseURL: "https://api.deepseek.com/v1",
            modelName: "flash"
        )
        let emptyKeychain = InMemoryKeychainStore() // No API key saved

        // Invoking recognition with missing key should smoothly fall back to local mock
        let response = try await AIProviderRouter.recognizeFoodWithValidation(
            images: [],
            mealType: .lunch,
            userHint: "西红柿炒蛋",
            config: deepSeekConfig,
            keychain: emptyKeychain
        )

        XCTAssertFalse(response.items.isEmpty, "Mock fallback should produce parsed food items")
        XCTAssertGreaterThan(response.totalCalories, 0, "Mock fallback should calculate calories")
    }

    // MARK: - 5. 2026 Morandi Visual Theme Tokens (R6)

    func testMorandiThemeTokens() {
        // Hex initializer verification
        let hexColor = Color(hex: 0xFAF8F5)
        XCTAssertNotNil(hexColor)

        // Palette tokens
        let bg = FoodLogTheme.warmBackground
        let surface = FoodLogTheme.warmSurface
        let text = FoodLogTheme.charcoalText
        let button = FoodLogTheme.deepCharcoalButton
        let sage = FoodLogTheme.morandiProteinSage
        let terracotta = FoodLogTheme.morandiCarbTerracotta
        let almond = FoodLogTheme.morandiFatAlmond

        XCTAssertNotNil(bg)
        XCTAssertNotNil(surface)
        XCTAssertNotNil(text)
        XCTAssertNotNil(button)
        XCTAssertNotNil(sage)
        XCTAssertNotNil(terracotta)
        XCTAssertNotNil(almond)

        // Horizon Energy Arc Shape path
        let arc = HorizonEnergyArc(startAngle: .degrees(195), endAngle: .degrees(345))
        let path = arc.path(in: CGRect(x: 0, y: 0, width: 340, height: 70))
        XCTAssertFalse(path.isEmpty, "HorizonEnergyArc must produce a valid non-empty path across the frame")
    }
}
