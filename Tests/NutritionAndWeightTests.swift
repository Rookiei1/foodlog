import XCTest
@testable import FoodLog

final class NutritionAndWeightTests: XCTestCase {
    func testDailyMetricsAggregatesOnlyTargetDateAndMeals() {
        var profile = UserProfileSettings()
        profile.targetCalories = 2500
        profile.targetProteinGrams = 130
        profile.targetFatGrams = 70
        profile.targetCarbGrams = 320

        let entries: [FoodEntrySnapshot] = [
            FoodEntrySnapshot(
                name: "燕麦牛奶鸡蛋",
                mealType: .breakfast,
                dayKey: "2026-11-14",
                grams: 350,
                calories: 520,
                proteinGrams: 28,
                fatGrams: 16,
                carbGrams: 64
            ),
            FoodEntrySnapshot(
                name: "香煎鸡排饭",
                mealType: .lunch,
                dayKey: "2026-11-14",
                grams: 480,
                calories: 780,
                proteinGrams: 46,
                fatGrams: 22,
                carbGrams: 92
            ),
            FoodEntrySnapshot(
                name: "前一天夜宵面",
                mealType: .lateNight,
                dayKey: "2026-11-13",
                grams: 300,
                calories: 610,
                proteinGrams: 18,
                fatGrams: 20,
                carbGrams: 85
            )
        ]

        let metrics = NutritionAndWeightEngine.calculateDailyMetrics(
            for: "2026-11-14",
            entries: entries,
            profile: profile
        )

        XCTAssertEqual(metrics.totalCalories, 1300, accuracy: 0.01)
        XCTAssertEqual(metrics.totalProteinGrams, 74, accuracy: 0.01)
        XCTAssertEqual(metrics.totalFatGrams, 38, accuracy: 0.01)
        XCTAssertEqual(metrics.totalCarbGrams, 156, accuracy: 0.01)
        XCTAssertEqual(metrics.remainingCalories, 1200, accuracy: 0.01)
        XCTAssertEqual(metrics.calories(for: .breakfast), 520, accuracy: 0.01)
        XCTAssertEqual(metrics.calories(for: .lunch), 780, accuracy: 0.01)
        XCTAssertEqual(metrics.calories(for: .lateNight), 0, accuracy: 0.01)
    }

    func testNutritionLabelCalculationConvertsKilojoulesToKilocalories() {
        let input = NutritionLabelInput(
            energyPerBasis: 1046.0, // 1046 kJ == 250 kcal per 100g
            energyUnit: .kilojoule,
            basisGrams: 100.0,
            proteinPerBasis: 15.0,
            fatPerBasis: 5.0,
            carbPerBasis: 35.0,
            packageNetWeightGrams: 200.0,
            consumedServingsRatio: 1.0
        )

        let result = NutritionAndWeightEngine.calculateFromNutritionLabel(input)
        XCTAssertEqual(result.consumedGrams, 200.0, accuracy: 0.1)
        XCTAssertEqual(result.calories, 500.0, accuracy: 0.5)
        XCTAssertEqual(result.proteinGrams, 30.0, accuracy: 0.1)
        XCTAssertEqual(result.fatGrams, 10.0, accuracy: 0.1)
        XCTAssertEqual(result.carbGrams, 70.0, accuracy: 0.1)
        XCTAssertTrue(result.explanation.contains("营养成分表"))
    }

    func testFavoriteFoodTemplateScalesToCustomGramWeight() {
        let fav = FavoriteFoodSnapshot(
            name: "去皮熟鸡胸肉",
            defaultMealType: .lunch,
            defaultGrams: 100,
            caloriesPer100g: 133,
            proteinPer100g: 24.6,
            fatPer100g: 3.2,
            carbPer100g: 1.2
        )

        let entry = fav.makeEntrySnapshot(grams: 200, mealType: .dinner)
        XCTAssertEqual(entry.grams, 200, accuracy: 0.01)
        XCTAssertEqual(entry.calories, 266, accuracy: 0.1)
        XCTAssertEqual(entry.proteinGrams, 49.2, accuracy: 0.1)
        XCTAssertEqual(entry.mealType, .dinner)
    }

    func testDailyRepresentativeWeightRulesAreConsistent() {
        let baseDate = Date(timeIntervalSince1970: 1_760_000_000)
        let records: [WeightRecordSnapshot] = [
            WeightRecordSnapshot(
                measuredAt: baseDate,
                dayKey: "2026-11-10",
                weightKg: 62.10,
                slot: .morningFasting,
                isRepresentativeOverride: false
            ),
            WeightRecordSnapshot(
                measuredAt: baseDate.addingTimeInterval(3600 * 6),
                dayKey: "2026-11-10",
                weightKg: 62.80,
                slot: .postMeal,
                isRepresentativeOverride: false
            ),
            WeightRecordSnapshot(
                measuredAt: baseDate.addingTimeInterval(3600 * 14),
                dayKey: "2026-11-10",
                weightKg: 61.90,
                slot: .evening,
                isRepresentativeOverride: false
            )
        ]

        XCTAssertEqual(
            NutritionAndWeightEngine.selectDailyRepresentativeWeight(from: records, rule: .morningFastingFirst) ?? 0,
            62.10,
            accuracy: 0.01
        )
        XCTAssertEqual(
            NutritionAndWeightEngine.selectDailyRepresentativeWeight(from: records, rule: .lowestOfDay) ?? 0,
            61.90,
            accuracy: 0.01
        )
        XCTAssertEqual(
            NutritionAndWeightEngine.selectDailyRepresentativeWeight(from: records, rule: .latestOfDay) ?? 0,
            61.90,
            accuracy: 0.01
        )
        XCTAssertEqual(
            NutritionAndWeightEngine.selectDailyRepresentativeWeight(from: records, rule: .averageOfDay) ?? 0,
            62.27,
            accuracy: 0.02
        )
    }

    func testWeightTrendCalculatesRollingAverageWeeklySummaryAndRate() {
        let calendar = Calendar(identifier: .gregorian)
        let start = DateKeyHelper.date(fromDayKey: "2026-11-01", calendar: calendar)!
        var records: [WeightRecordSnapshot] = []
        for dayIndex in 0..<8 {
            let date = DateKeyHelper.shiftingDays(start, by: dayIndex, calendar: calendar)
            let kg = 60.0 + Double(dayIndex) * 0.1 // +0.7 kg over 7 days == +0.70 kg/week
            records.append(
                WeightRecordSnapshot(
                    measuredAt: date,
                    dayKey: DateKeyHelper.dayKey(for: date, calendar: calendar),
                    weightKg: kg,
                    slot: .morningFasting
                )
            )
        }

        let summary = NutritionAndWeightEngine.buildWeightTrend(
            records: records,
            rule: .morningFastingFirst,
            calendar: calendar
        )
        XCTAssertEqual(summary.dailyPoints.count, 8)
        XCTAssertEqual(summary.startWeightKg ?? 0, 60.0, accuracy: 0.01)
        XCTAssertEqual(summary.latestWeightKg ?? 0, 60.7, accuracy: 0.01)
        XCTAssertEqual(summary.totalChangeKg ?? 0, 0.7, accuracy: 0.01)
        XCTAssertEqual(summary.weeklyRateKg ?? 0, 0.7, accuracy: 0.02)
        XCTAssertNotNil(summary.dailyPoints.last?.rolling7DayAverageKg)
    }
}
