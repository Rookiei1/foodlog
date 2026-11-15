import Foundation
import SwiftData

public enum PersistenceController {
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            FoodEntryRecord.self,
            FavoriteFoodTemplate.self,
            WeightRecord.self,
            SavedAnalysisReportRecord.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @MainActor
    public static func seedSampleDataIfEmpty(in context: ModelContext, now: Date = Date()) {
        let existingFoods = (try? context.fetchCount(FetchDescriptor<FoodEntryRecord>())) ?? 0
        guard existingFoods == 0 else { return }

        let cal = Calendar.current
        let breakfastTime = cal.date(bySettingHour: 8, minute: 15, second: 0, of: now) ?? now
        let lunchTime = cal.date(bySettingHour: 12, minute: 30, second: 0, of: now) ?? now
        let snackTime = cal.date(bySettingHour: 16, minute: 10, second: 0, of: now) ?? now

        let todayBreakfast = FoodEntrySnapshot(
            name: "全麦吐司配水煮蛋与全脂牛奶",
            mealType: .breakfast,
            eatenAt: breakfastTime,
            dayKey: DateKeyHelper.dayKey(for: now),
            grams: 360,
            calories: 485,
            proteinGrams: 26.5,
            fatGrams: 16.0,
            carbGrams: 56.0,
            isFromNutritionLabel: true,
            aiAnalysisBasis: "牛奶按包装营养成分表（250ml 净含量）计算，鸡蛋与全麦吐司按标准分量计算",
            uncertaintyNote: "吐司单片厚度略有差异，误差约 ±25 kcal",
            userNote: "晨练后早餐",
            isFavorite: true
        )
        let todayLunch = FoodEntrySnapshot(
            name: "香煎鸡胸肉藜麦饭配西兰花",
            mealType: .lunch,
            eatenAt: lunchTime,
            dayKey: DateKeyHelper.dayKey(for: now),
            grams: 450,
            estimatedMinGrams: 410,
            estimatedMaxGrams: 490,
            calories: 690,
            proteinGrams: 48.0,
            fatGrams: 18.5,
            carbGrams: 78.0,
            isFromNutritionLabel: false,
            aiAnalysisBasis: "AI 视觉分项识别：熟鸡胸肉约 160g、杂粮米饭约 200g、西兰花约 90g 及烹饪油",
            uncertaintyNote: "外卖底部油脂含量存在不确定性，热量估算区间 640–740 kcal",
            aiProviderName: "内置离线演示 (Mock)",
            aiModelName: "foodlog-vision-mock-v1"
        )
        let todaySnack = FoodEntrySnapshot(
            name: "希腊酸奶配香蕉与乳清蛋白",
            mealType: .snack,
            eatenAt: snackTime,
            dayKey: DateKeyHelper.dayKey(for: now),
            grams: 280,
            calories: 365,
            proteinGrams: 32.0,
            fatGrams: 5.5,
            carbGrams: 46.0,
            isFromNutritionLabel: true,
            aiAnalysisBasis: "蛋白粉与希腊酸奶按包装营养成分表计算",
            uncertaintyNote: "香蕉按中等大小 120g 计",
            userNote: "下午练前加餐"
        )
        context.insert(FoodEntryRecord(snapshot: todayBreakfast))
        context.insert(FoodEntryRecord(snapshot: todayLunch))
        context.insert(FoodEntryRecord(snapshot: todaySnack))

        let fav1 = FavoriteFoodSnapshot(
            name: "纯牛奶 250ml",
            defaultMealType: .breakfast,
            defaultGrams: 250,
            caloriesPer100g: 65,
            proteinPer100g: 3.2,
            fatPer100g: 3.6,
            carbPer100g: 4.8,
            note: "营养成分表标准值"
        )
        let fav2 = FavoriteFoodSnapshot(
            name: "香煎鸡胸肉",
            defaultMealType: .lunch,
            defaultGrams: 150,
            caloriesPer100g: 133,
            proteinPer100g: 24.6,
            fatPer100g: 3.2,
            carbPer100g: 1.2,
            note: "常吃高蛋白主菜"
        )
        let fav3 = FavoriteFoodSnapshot(
            name: "熟白米饭",
            defaultMealType: .dinner,
            defaultGrams: 200,
            caloriesPer100g: 116,
            proteinPer100g: 2.6,
            fatPer100g: 0.3,
            carbPer100g: 25.9,
            note: "一平碗约 200g"
        )
        context.insert(FavoriteFoodTemplate(snapshot: fav1))
        context.insert(FavoriteFoodTemplate(snapshot: fav2))
        context.insert(FavoriteFoodTemplate(snapshot: fav3))

        let sampleWeights: [(Int, Double)] = [
            (-6, 61.60),
            (-5, 61.72),
            (-4, 61.68),
            (-3, 61.82),
            (-2, 61.90),
            (-1, 62.05),
            (0, 62.15)
        ]
        for (dayOffset, kg) in sampleWeights {
            let date = DateKeyHelper.shiftingDays(now, by: dayOffset)
            let record = WeightRecordSnapshot(
                measuredAt: date,
                weightKg: kg,
                slot: .morningFasting,
                isRepresentativeOverride: true,
                note: dayOffset == 0 ? "晨起空腹" : "晨起称重"
            )
            context.insert(WeightRecord(snapshot: record))
        }

        let sampleReport = AIComprehensiveReport(
            spanTitle: "最近 7 天",
            dateRangeText: "\(DateKeyHelper.dayKey(for: DateKeyHelper.shiftingDays(now, by: -6))) ~ \(DateKeyHelper.dayKey(for: now))",
            providerName: "内置演示",
            modelName: "foodlog-vision-mock-v1",
            objectiveSummarySection: "记录 7 天 · 日均 2,640 kcal · 日均蛋白质 126g · 体重 +0.55 kg",
            estimationAndFluctuationDisclaimer: "日间 0.3–0.6 kg 波动多为糖原与水分变化，请以周均体重斜率评估增肌进展。",
            calorieAndWeightAnalysis: "近 7 天平均每日盈余约 +280 kcal，蛋白质达 2.0g/kg 体重，周均体重稳步上升。",
            surplusEvaluation: "当前处于温和热量盈余区间（+250 ~ +350 kcal/天），增重速度科学可控。",
            underEatingDaysReview: "周三、周五晚餐碳水略低，其余 5 天均达成热量与蛋白质目标。",
            dietStructureIssues: [
                "训练日晚餐碳水占比偏低，不利于糖原恢复",
                "下午 15:00–17:00 可固定一次高蛋白加餐"
            ],
            nextWeekActionSuggestions: [
                "训练日午餐与晚餐各增加 50g 熟米饭或燕麦",
                "下午固定补充 250ml 牛奶 + 1 根香蕉（约 +260 kcal）",
                "保持每日晨起排空后空腹称重"
            ],
            weightGoalAdjustmentAdvice: "维持当前 2,828 kcal 目标 2 周，若周增幅低于 +0.15 kg 再上调 150 kcal。"
        )
        context.insert(SavedAnalysisReportRecord(report: sampleReport))

        try? context.save()
    }
}
