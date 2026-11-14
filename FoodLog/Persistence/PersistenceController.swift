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

        let todayBreakfast = FoodEntrySnapshot(
            name: "全麦吐司配水煮蛋与全脂牛奶",
            mealType: .breakfast,
            eatenAt: now.addingTimeInterval(-3600 * 4),
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
            eatenAt: now.addingTimeInterval(-3600 * 1),
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
        context.insert(FoodEntryRecord(snapshot: todayBreakfast))
        context.insert(FoodEntryRecord(snapshot: todayLunch))

        let fav1 = FavoriteFoodSnapshot(
            name: "纯牛奶（盒装 250ml）",
            defaultMealType: .breakfast,
            defaultGrams: 250,
            caloriesPer100g: 65,
            proteinPer100g: 3.2,
            fatPer100g: 3.6,
            carbPer100g: 4.8,
            note: "营养成分表标准值"
        )
        let fav2 = FavoriteFoodSnapshot(
            name: "去皮熟鸡胸肉",
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
            (-6, 61.6),
            (-5, 61.7),
            (-4, 61.8),
            (-3, 61.75),
            (-2, 61.9),
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
                note: dayOffset == 0 ? "今日晨起空腹" : "晨起称重"
            )
            context.insert(WeightRecord(snapshot: record))
        }
        try? context.save()
    }
}
