import Foundation

public enum ActivityLevel: String, CaseIterable, Codable, Identifiable, Sendable {
    case sedentary = "sedentary"
    case light = "light"
    case moderate = "moderate"
    case active = "active"
    case veryActive = "veryActive"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sedentary: return "久坐少动（办公室/极少运动）"
        case .light: return "轻度活动（每周运动 1–3 次）"
        case .moderate: return "中度活动（每周运动 3–5 次）"
        case .active: return "高频运动（每周训练 6–7 次）"
        case .veryActive: return "高强度训练（体力劳动或每日双练）"
        }
    }

    public var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .active: return 1.725
        case .veryActive: return 1.9
        }
    }
}

public enum GoalMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case gainWeight = "gainWeight"
    case maintain = "maintain"
    case loseFat = "loseFat"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .gainWeight: return "健康增重 / 增肌"
        case .maintain: return "维持当前体重"
        case .loseFat: return "减脂塑形"
        }
    }

    public var calorieAdjustment: Double {
        switch self {
        case .gainWeight: return 350
        case .maintain: return 0
        case .loseFat: return -400
        }
    }
}

public enum BiologicalSex: String, CaseIterable, Codable, Identifiable, Sendable {
    case male = "male"
    case female = "female"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .male: return "男"
        case .female: return "女"
        }
    }
}

public struct RecommendedTargets: Codable, Equatable, Sendable {
    public var bmr: Double
    public var tdee: Double
    public var targetCalories: Double
    public var targetProteinGrams: Double
    public var targetFatGrams: Double
    public var targetCarbGrams: Double
}

public struct UserProfileSettings: Codable, Equatable, Sendable {
    public var heightCm: Double
    public var currentWeightKg: Double
    public var targetWeightKg: Double
    public var age: Int
    public var sex: BiologicalSex
    public var activityLevel: ActivityLevel
    public var goalMode: GoalMode
    public var useCustomTargets: Bool
    public var targetCalories: Double
    public var targetProteinGrams: Double
    public var targetFatGrams: Double
    public var targetCarbGrams: Double
    public var representativeWeightRule: DailyRepresentativeRule
    public var hasAcceptedPhotoPrivacyNotice: Bool

    public init(
        heightCm: Double = 175.0,
        currentWeightKg: Double = 62.0,
        targetWeightKg: Double = 68.0,
        age: Int = 24,
        sex: BiologicalSex = .male,
        activityLevel: ActivityLevel = .moderate,
        goalMode: GoalMode = .gainWeight,
        useCustomTargets: Bool = false,
        targetCalories: Double = 2650,
        targetProteinGrams: Double = 125,
        targetFatGrams: Double = 75,
        targetCarbGrams: Double = 365,
        representativeWeightRule: DailyRepresentativeRule = .morningFastingFirst,
        hasAcceptedPhotoPrivacyNotice: Bool = false
    ) {
        self.heightCm = heightCm
        self.currentWeightKg = currentWeightKg
        self.targetWeightKg = targetWeightKg
        self.age = age
        self.sex = sex
        self.activityLevel = activityLevel
        self.goalMode = goalMode
        self.useCustomTargets = useCustomTargets
        self.targetCalories = targetCalories
        self.targetProteinGrams = targetProteinGrams
        self.targetFatGrams = targetFatGrams
        self.targetCarbGrams = targetCarbGrams
        self.representativeWeightRule = representativeWeightRule
        self.hasAcceptedPhotoPrivacyNotice = hasAcceptedPhotoPrivacyNotice
    }

    public func computeRecommendedTargets(referenceWeightKg: Double? = nil) -> RecommendedTargets {
        let weight = max(30.0, referenceWeightKg ?? currentWeightKg)
        let height = max(120.0, heightCm)
        let years = Double(max(14, min(100, age)))
        let sexOffset: Double = (sex == .male) ? 5.0 : -161.0
        let bmr = (10.0 * weight) + (6.25 * height) - (5.0 * years) + sexOffset
        let tdee = bmr * activityLevel.multiplier
        let calories = max(1200.0, (tdee + goalMode.calorieAdjustment).rounded())

        let proteinFactor: Double
        switch goalMode {
        case .gainWeight: proteinFactor = 1.9
        case .maintain: proteinFactor = 1.6
        case .loseFat: proteinFactor = 2.0
        }
        let protein = (weight * proteinFactor).rounded()
        let fat = ((calories * 0.26) / 9.0).rounded()
        let remainingKcal = max(200.0, calories - (protein * 4.0) - (fat * 9.0))
        let carbs = (remainingKcal / 4.0).rounded()

        return RecommendedTargets(
            bmr: bmr.rounded(),
            tdee: tdee.rounded(),
            targetCalories: calories,
            targetProteinGrams: protein,
            targetFatGrams: fat,
            targetCarbGrams: carbs
        )
    }

    public mutating func applyRecommendedTargets(referenceWeightKg: Double? = nil) {
        let rec = computeRecommendedTargets(referenceWeightKg: referenceWeightKg)
        self.targetCalories = rec.targetCalories
        self.targetProteinGrams = rec.targetProteinGrams
        self.targetFatGrams = rec.targetFatGrams
        self.targetCarbGrams = rec.targetCarbGrams
    }
}
