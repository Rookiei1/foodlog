import XCTest
import SwiftData
@testable import FoodLog

final class DataExportAndBackupTests: XCTestCase {
    func testFoodAndWeightCSVExportsIncludeUTF8BOMAndAllFields() {
        let food = FoodEntrySnapshot(
            name: "烤鸡胸肉,配西兰花",
            mealType: .lunch,
            dayKey: "2026-11-14",
            grams: 220,
            estimatedMinGrams: 200,
            estimatedMaxGrams: 240,
            calories: 340,
            proteinGrams: 45,
            fatGrams: 9,
            carbGrams: 18,
            isFromNutritionLabel: false,
            aiAnalysisBasis: "视觉估算",
            uncertaintyNote: "±10%",
            userNote: "少盐"
        )
        let csvData = DataExportService.exportFoodEntriesCSV(entries: [food])
        XCTAssertTrue(csvData.starts(with: [0xEF, 0xBB, 0xBF]))
        let text = String(decoding: csvData.dropFirst(3), as: UTF8.self)
        XCTAssertTrue(text.contains("\"烤鸡胸肉,配西兰花\""))
        XCTAssertTrue(text.contains("340.0"))

        let weight = WeightRecordSnapshot(
            dayKey: "2026-11-14",
            weightKg: 62.35,
            slot: .morningFasting,
            isRepresentativeOverride: true,
            note: "空腹"
        )
        let weightCSV = DataExportService.exportWeightRecordsCSV(records: [weight])
        XCTAssertTrue(weightCSV.starts(with: [0xEF, 0xBB, 0xBF]))
        let weightText = String(decoding: weightCSV.dropFirst(3), as: UTF8.self)
        XCTAssertTrue(weightText.contains("62.35"))
        XCTAssertTrue(weightText.contains("晨起空腹"))
    }

    @MainActor
    func testFullBackupJSONExcludesAPIKeysAndRestoresIntoSwiftData() throws {
        var profile = UserProfileSettings()
        profile.targetCalories = 2750
        profile.targetWeightKg = 70.0

        let food = FoodEntrySnapshot(
            name: "全麦三明治",
            mealType: .breakfast,
            dayKey: "2026-11-14",
            grams: 180,
            calories: 410,
            proteinGrams: 22,
            fatGrams: 14,
            carbGrams: 48
        )
        let fav = FavoriteFoodSnapshot.fromEntry(food)
        let weight = WeightRecordSnapshot(dayKey: "2026-11-14", weightKg: 63.2, slot: .morningFasting)
        let report = AIComprehensiveReport(
            spanTitle: "最近 7 天",
            dateRangeText: "2026-11-08 ~ 2026-11-14",
            providerName: "Mock",
            modelName: "foodlog-vision-mock-v1",
            objectiveSummarySection: "日均 2500 kcal",
            estimationAndFluctuationDisclaimer: "短期水分波动不等于纯肌肉增长",
            calorieAndWeightAnalysis: "稳定增长",
            surplusEvaluation: "盈余达标",
            underEatingDaysReview: "无漏餐",
            dietStructureIssues: ["加餐偏少"],
            nextWeekActionSuggestions: ["增加下午加餐"],
            weightGoalAdjustmentAdvice: "维持 2750 kcal"
        )

        let jsonData = try DataExportService.exportFullBackupJSON(
            profile: profile,
            foodEntries: [food],
            favoriteFoods: [fav],
            weightRecords: [weight],
            savedReports: [report],
            includePhotos: false
        )

        let rawJSONString = String(decoding: jsonData, as: UTF8.self)
        XCTAssertTrue(rawJSONString.contains("\"schemaVersion\" : \"1.0\""))
        XCTAssertFalse(rawJSONString.contains("apiKey"))
        XCTAssertFalse(rawJSONString.contains("sk-"))

        let container = try PersistenceController.makeContainer(inMemory: true)
        let (summary, restoredProfile) = try DataExportService.restoreBackup(
            from: jsonData,
            into: container.mainContext
        )

        XCTAssertEqual(summary.schemaVersion, "1.0")
        XCTAssertEqual(summary.importedFoodsCount, 1)
        XCTAssertEqual(summary.importedFavoritesCount, 1)
        XCTAssertEqual(summary.importedWeightsCount, 1)
        XCTAssertEqual(summary.importedReportsCount, 1)
        XCTAssertEqual(restoredProfile.targetCalories, 2750)
        XCTAssertEqual(restoredProfile.targetWeightKg, 70.0)

        // Second restore of the same backup should deduplicate by UUID
        let (secondSummary, _) = try DataExportService.restoreBackup(
            from: jsonData,
            into: container.mainContext
        )
        XCTAssertEqual(secondSummary.importedFoodsCount, 0)
    }

    func testPDFReportRendererProducesValidPDFDocument() {
        let report = AIComprehensiveReport(
            spanTitle: "最近 30 天",
            dateRangeText: "2026-10-16 ~ 2026-11-14",
            providerName: "内置离线演示",
            modelName: "foodlog-vision-mock-v1",
            objectiveSummarySection: "日均热量 2620 kcal，日均蛋白质 128g",
            estimationAndFluctuationDisclaimer: "严格区分客观数据、估算区间与短期水分波动。",
            calorieAndWeightAnalysis: "30 天内体重从 61.2kg 上升至 62.4kg。",
            surplusEvaluation: "平均每日盈余约 +300 kcal。",
            underEatingDaysReview: "仅 2 天摄入低于目标 85%。",
            dietStructureIssues: ["训练日碳水可适当增加"],
            nextWeekActionSuggestions: ["保持每日晨起空腹称重"],
            weightGoalAdjustmentAdvice: "继续执行当前热量目标。"
        )
        let pdfData = DataExportService.renderAnalysisReportPDF(report: report)
        XCTAssertGreaterThan(pdfData.count, 500)
        let header = String(decoding: pdfData.prefix(5), as: UTF8.self)
        XCTAssertEqual(header, "%PDF-")
    }
}
