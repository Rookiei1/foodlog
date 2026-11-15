import XCTest
@testable import FoodLog

final class AIProviderAndValidationTests: XCTestCase {
    func testVisionCapabilityCheckerBlocksTextOnlyModels() {
        XCTAssertFalse(AIVisionCapabilityChecker.supportsVision(kind: .deepSeek, modelName: "deepseek-reasoner"))
        XCTAssertFalse(AIVisionCapabilityChecker.supportsVision(kind: .openAI, modelName: "o3-mini"))

        XCTAssertTrue(AIVisionCapabilityChecker.supportsVision(kind: .deepSeek, modelName: "flash"))
        XCTAssertTrue(AIVisionCapabilityChecker.supportsVision(kind: .openAI, modelName: "gpt-4o"))
        XCTAssertTrue(AIVisionCapabilityChecker.supportsVision(kind: .openAI, modelName: "gpt-4o-mini"))
        XCTAssertTrue(AIVisionCapabilityChecker.supportsVision(kind: .gemini, modelName: "gemini-2.5-flash"))
        XCTAssertTrue(AIVisionCapabilityChecker.supportsVision(kind: .deepSeek, modelName: "deepseek-vl2"))
        XCTAssertTrue(
            AIVisionCapabilityChecker.supportsVision(
                kind: .openAICompatible,
                modelName: "custom-model",
                explicitOverride: true
            )
        )
    }

    func testRouterRejectsImageRecognitionOnNonVisionModelBeforeNetwork() async {
        let nonVisionConfig = AIProviderConfig(
            name: "DeepSeek 思考纯文本",
            kind: .deepSeek,
            modelName: "deepseek-reasoner"
        )
        let keychain = InMemoryKeychainStore()
        try? keychain.saveSecret("sk-test-123", forAccount: nonVisionConfig.id.uuidString)

        do {
            _ = try await AIProviderRouter.recognizeFoodWithValidation(
                images: [Data([0x01, 0x02])],
                mealType: .lunch,
                userHint: "",
                config: nonVisionConfig,
                keychain: keychain
            )
            XCTFail("Expected non-vision model to be rejected before network call")
        } catch let error as AIServiceError {
            XCTAssertEqual(error, .modelDoesNotSupportVision(modelName: "deepseek-reasoner"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testJSONValidatorParsesMarkdownFencedMultiItemRecognition() throws {
        let raw = """
        ```json
        {
          "mealSummary": "鸡排烤肠牛奶组合",
          "deduplicationNote": "两张照片中的牛奶为同一盒，已去重",
          "overallUncertaintyBanner": "肉类重量存在 ±15% 浮动",
          "items": [
            {
              "name": "香煎鸡排",
              "estimatedGrams": 160,
              "minGrams": 140,
              "maxGrams": 180,
              "calories": 270,
              "proteinGrams": 35,
              "fatGrams": 11,
              "carbGrams": 5,
              "sourceType": "visual_estimate",
              "basis": "按餐盘比例估算",
              "uncertainty": "油量约 ±25 kcal"
            },
            {
              "name": "盒装纯牛奶",
              "estimatedGrams": 250,
              "calories": 162,
              "proteinGrams": 8.0,
              "fatGrams": 9.0,
              "carbGrams": 12.0,
              "sourceType": "nutrition_label",
              "packageNetWeightGrams": 250,
              "basis": "按营养成分表 × 250ml 计算",
              "uncertainty": "包装标示值"
            }
          ]
        }
        ```
        """

        let parsed = try AIJSONValidator.validateFoodRecognitionJSON(raw)
        XCTAssertEqual(parsed.items.count, 2)
        XCTAssertEqual(parsed.items[0].name, "香煎鸡排")
        XCTAssertEqual(parsed.items[0].weightRangeDescription, "140–180g")
        XCTAssertEqual(parsed.items[1].sourceType, .nutritionLabel)
        XCTAssertEqual(parsed.items[1].packageNetWeightGrams, 250)
    }

    func testMockAdapterSeparatesMultipleFoodsAndSupportsNutritionLabel() async throws {
        let mockConfig = AIProviderConfig(
            name: "Mock",
            kind: .localMock,
            modelName: "foodlog-vision-mock-v1"
        )
        let keychain = InMemoryKeychainStore()

        let multiResponse = try await AIProviderRouter.recognizeFoodWithValidation(
            images: [Data([0xFF, 0xD8]), Data([0xFF, 0xD9])],
            mealType: .dinner,
            userHint: "",
            config: mockConfig,
            keychain: keychain
        )
        XCTAssertGreaterThanOrEqual(multiResponse.items.count, 3)
        XCTAssertTrue(multiResponse.deduplicationNote.contains("同餐照片"))

        let labelResponse = try await AIProviderRouter.recognizeFoodWithValidation(
            images: [Data([0xFF, 0xD8])],
            mealType: .breakfast,
            userHint: "这是包装背面的营养成分表",
            config: mockConfig,
            keychain: keychain
        )
        XCTAssertEqual(labelResponse.items.first?.sourceType, .nutritionLabel)
    }

    @MainActor
    func testKeychainStoreIsolationAndProviderSwitchDoesNotLoseData() throws {
        let suiteName = "foodlog-unit-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keychain = InMemoryKeychainStore()
        let vm = AppStateViewModel(userDefaults: defaults, keychain: keychain)
        let deepSeek = vm.providers.first(where: { $0.kind == .deepSeek })!

        XCTAssertFalse(vm.hasAPIKey(for: deepSeek))
        try vm.saveAPIKey("sk-secret-key-do-not-export", for: deepSeek)
        XCTAssertTrue(vm.hasAPIKey(for: deepSeek))
        XCTAssertEqual(vm.apiKey(for: deepSeek), "sk-secret-key-do-not-export")

        // Switching default provider preserves settings
        vm.defaultVisionProviderID = deepSeek.id
        XCTAssertEqual(vm.defaultVisionProvider.id, deepSeek.id)
    }
}
