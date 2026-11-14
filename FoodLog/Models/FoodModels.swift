import Foundation
import SwiftData

public enum MealType: String, CaseIterable, Codable, Identifiable, Sendable {
    case breakfast = "breakfast"
    case lunch = "lunch"
    case dinner = "dinner"
    case lateNight = "lateNight"
    case snack = "snack"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .breakfast: return "早餐"
        case .lunch: return "午餐"
        case .dinner: return "晚餐"
        case .lateNight: return "夜宵"
        case .snack: return "加餐"
        }
    }

    public var systemImage: String {
        switch self {
        case .breakfast: return "sun.horizon.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .lateNight: return "sparkles"
        case .snack: return "leaf.fill"
        }
    }

    public var sortOrder: Int {
        switch self {
        case .breakfast: return 0
        case .lunch: return 1
        case .snack: return 2
        case .dinner: return 3
        case .lateNight: return 4
        }
    }

    public static func suggested(for date: Date = Date(), calendar: Calendar = .current) -> MealType {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<10:
            return .breakfast
        case 10..<14:
            return .lunch
        case 14..<17:
            return .snack
        case 17..<21:
            return .dinner
        default:
            return .lateNight
        }
    }
}

public struct FoodEntrySnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var mealType: MealType
    public var eatenAt: Date
    public var dayKey: String
    public var grams: Double
    public var estimatedMinGrams: Double?
    public var estimatedMaxGrams: Double?
    public var calories: Double
    public var proteinGrams: Double
    public var fatGrams: Double
    public var carbGrams: Double
    public var photoFilenames: [String]
    public var isFromNutritionLabel: Bool
    public var aiAnalysisBasis: String
    public var uncertaintyNote: String
    public var aiProviderName: String?
    public var aiModelName: String?
    public var userNote: String
    public var isFavorite: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        mealType: MealType,
        eatenAt: Date = Date(),
        dayKey: String? = nil,
        grams: Double,
        estimatedMinGrams: Double? = nil,
        estimatedMaxGrams: Double? = nil,
        calories: Double,
        proteinGrams: Double,
        fatGrams: Double,
        carbGrams: Double,
        photoFilenames: [String] = [],
        isFromNutritionLabel: Bool = false,
        aiAnalysisBasis: String = "",
        uncertaintyNote: String = "",
        aiProviderName: String? = nil,
        aiModelName: String? = nil,
        userNote: String = "",
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.mealType = mealType
        self.eatenAt = eatenAt
        self.dayKey = dayKey ?? DateKeyHelper.dayKey(for: eatenAt)
        self.grams = max(0, grams)
        self.estimatedMinGrams = estimatedMinGrams
        self.estimatedMaxGrams = estimatedMaxGrams
        self.calories = max(0, calories)
        self.proteinGrams = max(0, proteinGrams)
        self.fatGrams = max(0, fatGrams)
        self.carbGrams = max(0, carbGrams)
        self.photoFilenames = photoFilenames
        self.isFromNutritionLabel = isFromNutritionLabel
        self.aiAnalysisBasis = aiAnalysisBasis
        self.uncertaintyNote = uncertaintyNote
        self.aiProviderName = aiProviderName
        self.aiModelName = aiModelName
        self.userNote = userNote
        self.isFavorite = isFavorite
    }

    public func duplicated(for targetDate: Date, mealType overrideMeal: MealType? = nil) -> FoodEntrySnapshot {
        let mergedDate = DateKeyHelper.combining(day: targetDate, withTimeFrom: Date())
        return FoodEntrySnapshot(
            id: UUID(),
            name: name,
            mealType: overrideMeal ?? mealType,
            eatenAt: mergedDate,
            dayKey: DateKeyHelper.dayKey(for: mergedDate),
            grams: grams,
            estimatedMinGrams: estimatedMinGrams,
            estimatedMaxGrams: estimatedMaxGrams,
            calories: calories,
            proteinGrams: proteinGrams,
            fatGrams: fatGrams,
            carbGrams: carbGrams,
            photoFilenames: photoFilenames,
            isFromNutritionLabel: isFromNutritionLabel,
            aiAnalysisBasis: aiAnalysisBasis,
            uncertaintyNote: uncertaintyNote,
            aiProviderName: aiProviderName,
            aiModelName: aiModelName,
            userNote: userNote,
            isFavorite: isFavorite
        )
    }
}

@Model
public final class FoodEntryRecord {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var mealTypeRaw: String
    public var eatenAt: Date
    public var dayKey: String
    public var grams: Double
    public var estimatedMinGrams: Double?
    public var estimatedMaxGrams: Double?
    public var calories: Double
    public var proteinGrams: Double
    public var fatGrams: Double
    public var carbGrams: Double
    public var photoFilenames: [String]
    public var isFromNutritionLabel: Bool
    public var aiAnalysisBasis: String
    public var uncertaintyNote: String
    public var aiProviderName: String?
    public var aiModelName: String?
    public var userNote: String
    public var isFavorite: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .lunch }
        set { mealTypeRaw = newValue.rawValue }
    }

    public init(snapshot: FoodEntrySnapshot) {
        self.id = snapshot.id
        self.name = snapshot.name
        self.mealTypeRaw = snapshot.mealType.rawValue
        self.eatenAt = snapshot.eatenAt
        self.dayKey = snapshot.dayKey
        self.grams = snapshot.grams
        self.estimatedMinGrams = snapshot.estimatedMinGrams
        self.estimatedMaxGrams = snapshot.estimatedMaxGrams
        self.calories = snapshot.calories
        self.proteinGrams = snapshot.proteinGrams
        self.fatGrams = snapshot.fatGrams
        self.carbGrams = snapshot.carbGrams
        self.photoFilenames = snapshot.photoFilenames
        self.isFromNutritionLabel = snapshot.isFromNutritionLabel
        self.aiAnalysisBasis = snapshot.aiAnalysisBasis
        self.uncertaintyNote = snapshot.uncertaintyNote
        self.aiProviderName = snapshot.aiProviderName
        self.aiModelName = snapshot.aiModelName
        self.userNote = snapshot.userNote
        self.isFavorite = snapshot.isFavorite
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public func update(from snapshot: FoodEntrySnapshot) {
        self.name = snapshot.name
        self.mealTypeRaw = snapshot.mealType.rawValue
        self.eatenAt = snapshot.eatenAt
        self.dayKey = DateKeyHelper.dayKey(for: snapshot.eatenAt)
        self.grams = max(0, snapshot.grams)
        self.estimatedMinGrams = snapshot.estimatedMinGrams
        self.estimatedMaxGrams = snapshot.estimatedMaxGrams
        self.calories = max(0, snapshot.calories)
        self.proteinGrams = max(0, snapshot.proteinGrams)
        self.fatGrams = max(0, snapshot.fatGrams)
        self.carbGrams = max(0, snapshot.carbGrams)
        self.photoFilenames = snapshot.photoFilenames
        self.isFromNutritionLabel = snapshot.isFromNutritionLabel
        self.aiAnalysisBasis = snapshot.aiAnalysisBasis
        self.uncertaintyNote = snapshot.uncertaintyNote
        self.aiProviderName = snapshot.aiProviderName
        self.aiModelName = snapshot.aiModelName
        self.userNote = snapshot.userNote
        self.isFavorite = snapshot.isFavorite
        self.updatedAt = Date()
    }

    public var snapshot: FoodEntrySnapshot {
        FoodEntrySnapshot(
            id: id,
            name: name,
            mealType: mealType,
            eatenAt: eatenAt,
            dayKey: dayKey,
            grams: grams,
            estimatedMinGrams: estimatedMinGrams,
            estimatedMaxGrams: estimatedMaxGrams,
            calories: calories,
            proteinGrams: proteinGrams,
            fatGrams: fatGrams,
            carbGrams: carbGrams,
            photoFilenames: photoFilenames,
            isFromNutritionLabel: isFromNutritionLabel,
            aiAnalysisBasis: aiAnalysisBasis,
            uncertaintyNote: uncertaintyNote,
            aiProviderName: aiProviderName,
            aiModelName: aiModelName,
            userNote: userNote,
            isFavorite: isFavorite
        )
    }
}

public struct FavoriteFoodSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var defaultMealType: MealType
    public var defaultGrams: Double
    public var caloriesPer100g: Double
    public var proteinPer100g: Double
    public var fatPer100g: Double
    public var carbPer100g: Double
    public var note: String
    public var useCount: Int

    public init(
        id: UUID = UUID(),
        name: String,
        defaultMealType: MealType = .breakfast,
        defaultGrams: Double = 100,
        caloriesPer100g: Double,
        proteinPer100g: Double,
        fatPer100g: Double,
        carbPer100g: Double,
        note: String = "",
        useCount: Int = 1
    ) {
        self.id = id
        self.name = name
        self.defaultMealType = defaultMealType
        self.defaultGrams = max(1, defaultGrams)
        self.caloriesPer100g = max(0, caloriesPer100g)
        self.proteinPer100g = max(0, proteinPer100g)
        self.fatPer100g = max(0, fatPer100g)
        self.carbPer100g = max(0, carbPer100g)
        self.note = note
        self.useCount = max(0, useCount)
    }

    public static func fromEntry(_ entry: FoodEntrySnapshot) -> FavoriteFoodSnapshot {
        let baseGrams = max(1.0, entry.grams)
        let factor = 100.0 / baseGrams
        return FavoriteFoodSnapshot(
            name: entry.name,
            defaultMealType: entry.mealType,
            defaultGrams: baseGrams,
            caloriesPer100g: (entry.calories * factor * 10).rounded() / 10,
            proteinPer100g: (entry.proteinGrams * factor * 10).rounded() / 10,
            fatPer100g: (entry.fatGrams * factor * 10).rounded() / 10,
            carbPer100g: (entry.carbGrams * factor * 10).rounded() / 10,
            note: entry.userNote,
            useCount: 1
        )
    }

    public func makeEntrySnapshot(
        grams: Double? = nil,
        mealType: MealType? = nil,
        date: Date = Date()
    ) -> FoodEntrySnapshot {
        let targetGrams = max(1.0, grams ?? defaultGrams)
        let ratio = targetGrams / 100.0
        return FoodEntrySnapshot(
            name: name,
            mealType: mealType ?? defaultMealType,
            eatenAt: date,
            dayKey: DateKeyHelper.dayKey(for: date),
            grams: targetGrams,
            calories: (caloriesPer100g * ratio * 10).rounded() / 10,
            proteinGrams: (proteinPer100g * ratio * 10).rounded() / 10,
            fatGrams: (fatPer100g * ratio * 10).rounded() / 10,
            carbGrams: (carbPer100g * ratio * 10).rounded() / 10,
            isFromNutritionLabel: false,
            aiAnalysisBasis: "来自常吃食物收藏模板（按 \(Int(targetGrams))g 换算）",
            userNote: note,
            isFavorite: true
        )
    }
}

@Model
public final class FavoriteFoodTemplate {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var defaultMealTypeRaw: String
    public var defaultGrams: Double
    public var caloriesPer100g: Double
    public var proteinPer100g: Double
    public var fatPer100g: Double
    public var carbPer100g: Double
    public var note: String
    public var useCount: Int
    public var lastUsedAt: Date

    public init(snapshot: FavoriteFoodSnapshot) {
        self.id = snapshot.id
        self.name = snapshot.name
        self.defaultMealTypeRaw = snapshot.defaultMealType.rawValue
        self.defaultGrams = snapshot.defaultGrams
        self.caloriesPer100g = snapshot.caloriesPer100g
        self.proteinPer100g = snapshot.proteinPer100g
        self.fatPer100g = snapshot.fatPer100g
        self.carbPer100g = snapshot.carbPer100g
        self.note = snapshot.note
        self.useCount = snapshot.useCount
        self.lastUsedAt = Date()
    }

    public var snapshot: FavoriteFoodSnapshot {
        FavoriteFoodSnapshot(
            id: id,
            name: name,
            defaultMealType: MealType(rawValue: defaultMealTypeRaw) ?? .breakfast,
            defaultGrams: defaultGrams,
            caloriesPer100g: caloriesPer100g,
            proteinPer100g: proteinPer100g,
            fatPer100g: fatPer100g,
            carbPer100g: carbPer100g,
            note: note,
            useCount: useCount
        )
    }
}
