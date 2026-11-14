import Foundation
import SwiftData

public enum AIFoodSourceType: String, Codable, Equatable, Sendable {
    case nutritionLabel = "nutrition_label"
    case visualEstimate = "visual_estimate"

    public var badgeTitle: String {
        switch self {
        case .nutritionLabel: return "营养成分表优先"
        case .visualEstimate: return "视觉分量估算"
        }
    }
}

public struct AIFoodRecognizedItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var estimatedGrams: Double
    public var minGrams: Double?
    public var maxGrams: Double?
    public var calories: Double
    public var proteinGrams: Double
    public var fatGrams: Double
    public var carbGrams: Double
    public var sourceType: AIFoodSourceType
    public var packageNetWeightGrams: Double?
    public var basis: String
    public var uncertainty: String
    public var isSelected: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        estimatedGrams: Double,
        minGrams: Double? = nil,
        maxGrams: Double? = nil,
        calories: Double,
        proteinGrams: Double,
        fatGrams: Double,
        carbGrams: Double,
        sourceType: AIFoodSourceType = .visualEstimate,
        packageNetWeightGrams: Double? = nil,
        basis: String,
        uncertainty: String,
        isSelected: Bool = true
    ) {
        self.id = id
        self.name = name
        self.estimatedGrams = max(1, estimatedGrams)
        self.minGrams = minGrams
        self.maxGrams = maxGrams
        self.calories = max(0, calories)
        self.proteinGrams = max(0, proteinGrams)
        self.fatGrams = max(0, fatGrams)
        self.carbGrams = max(0, carbGrams)
        self.sourceType = sourceType
        self.packageNetWeightGrams = packageNetWeightGrams
        self.basis = basis
        self.uncertainty = uncertainty
        self.isSelected = isSelected
    }

    public var weightRangeDescription: String? {
        guard let minGrams, let maxGrams, maxGrams > minGrams else { return nil }
        return "\(Int(minGrams))–\(Int(maxGrams))g"
    }

    public func toFoodEntrySnapshot(
        mealType: MealType,
        eatenAt: Date,
        photoFilenames: [String],
        providerName: String,
        modelName: String
    ) -> FoodEntrySnapshot {
        FoodEntrySnapshot(
            name: name,
            mealType: mealType,
            eatenAt: eatenAt,
            dayKey: DateKeyHelper.dayKey(for: eatenAt),
            grams: estimatedGrams,
            estimatedMinGrams: minGrams,
            estimatedMaxGrams: maxGrams,
            calories: calories,
            proteinGrams: proteinGrams,
            fatGrams: fatGrams,
            carbGrams: carbGrams,
            photoFilenames: photoFilenames,
            isFromNutritionLabel: sourceType == .nutritionLabel,
            aiAnalysisBasis: basis,
            uncertaintyNote: uncertainty,
            aiProviderName: providerName,
            aiModelName: modelName
        )
    }
}

public struct AIFoodRecognitionResponse: Codable, Equatable, Sendable {
    public var mealSummary: String
    public var deduplicationNote: String
    public var overallUncertaintyBanner: String
    public var items: [AIFoodRecognizedItem]

    public init(
        mealSummary: String,
        deduplicationNote: String,
        overallUncertaintyBanner: String,
        items: [AIFoodRecognizedItem]
    ) {
        self.mealSummary = mealSummary
        self.deduplicationNote = deduplicationNote
        self.overallUncertaintyBanner = overallUncertaintyBanner
        self.items = items
    }
}

public enum AnalysisTimeSpan: String, CaseIterable, Codable, Identifiable, Sendable {
    case days7 = "days7"
    case days30 = "days30"
    case days90 = "days90"
    case allHistory = "allHistory"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .days7: return "最近 7 天"
        case .days30: return "最近 30 天"
        case .days90: return "最近 90 天"
        case .allHistory: return "全部历史记录"
        }
    }

    public var dayLimit: Int? {
        switch self {
        case .days7: return 7
        case .days30: return 30
        case .days90: return 90
        case .allHistory: return nil
        }
    }
}

public struct DailyCalorieDigestItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String { dayKey }
    public var dayKey: String
    public var calories: Double
    public var proteinGrams: Double
    public var fatGrams: Double
    public var carbGrams: Double
    public var entryCount: Int
    public var representativeWeightKg: Double?
}

public struct ObjectiveDatasetDigest: Codable, Equatable, Sendable {
    public var span: AnalysisTimeSpan
    public var startDayKey: String
    public var endDayKey: String
    public var totalCalendarDays: Int
    public var loggedFoodDays: Int
    public var loggedWeightDays: Int
    public var averageDailyCalories: Double
    public var averageDailyProteinGrams: Double
    public var averageDailyFatGrams: Double
    public var averageDailyCarbGrams: Double
    public var targetCalories: Double
    public var targetProteinGrams: Double
    public var goalMode: GoalMode
    public var startWeightKg: Double?
    public var endWeightKg: Double?
    public var weightChangeKg: Double?
    public var weeklyWeightRateKg: Double?
    public var underEatingDayKeys: [String]
    public var lowProteinDayKeys: [String]
    public var mealSharePercentages: [String: Double]
    public var topFoods: [String]
    public var dailySeries: [DailyCalorieDigestItem]

    public var promptReadyText: String {
        var lines: [String] = []
        lines.append("【统计范围】\(span.title)（\(startDayKey) 至 \(endDayKey)，共 \(totalCalendarDays) 天）")
        lines.append("【实际记录天数】饮食记录 \(loggedFoodDays) 天，体重记录 \(loggedWeightDays) 天")
        lines.append("【当前目标】\(goalMode.title)，每日目标热量 \(Int(targetCalories)) kcal，目标蛋白质 \(Int(targetProteinGrams)) g")
        lines.append("【客观摄入均值（按已记录饮食日）】日均热量 \(Int(averageDailyCalories.rounded())) kcal，日均蛋白质 \(String(format: "%.1f", averageDailyProteinGrams)) g，日均脂肪 \(String(format: "%.1f", averageDailyFatGrams)) g，日均碳水 \(String(format: "%.1f", averageDailyCarbGrams)) g")
        if let startW = startWeightKg, let endW = endWeightKg, let delta = weightChangeKg {
            let rateText = weeklyWeightRateKg.map { String(format: "%+.2f kg/周", $0) } ?? "样本不足"
            lines.append("【客观体重变化】期初代表体重 \(String(format: "%.2f", startW)) kg → 期末代表体重 \(String(format: "%.2f", endW)) kg（变化 \(String(format: "%+.2f", delta)) kg，速率 \(rateText)）")
        } else {
            lines.append("【客观体重变化】所选范围内有效称重不足 2 天，无法计算趋势变化率")
        }
        lines.append("【摄入明显不足日期（低于目标 85%）】\(underEatingDayKeys.isEmpty ? "无" : underEatingDayKeys.joined(separator: "、"))")
        lines.append("【蛋白质未达标日期（低于目标 85%）】\(lowProteinDayKeys.isEmpty ? "无" : lowProteinDayKeys.joined(separator: "、"))")
        if !topFoods.isEmpty {
            lines.append("【高频记录食物】\(topFoods.joined(separator: "、"))")
        }
        return lines.joined(separator: "\n")
    }
}

public struct AIComprehensiveReport: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var spanTitle: String
    public var dateRangeText: String
    public var providerName: String
    public var modelName: String
    public var objectiveSummarySection: String
    public var estimationAndFluctuationDisclaimer: String
    public var calorieAndWeightAnalysis: String
    public var surplusEvaluation: String
    public var underEatingDaysReview: String
    public var dietStructureIssues: [String]
    public var nextWeekActionSuggestions: [String]
    public var weightGoalAdjustmentAdvice: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        spanTitle: String,
        dateRangeText: String,
        providerName: String,
        modelName: String,
        objectiveSummarySection: String,
        estimationAndFluctuationDisclaimer: String,
        calorieAndWeightAnalysis: String,
        surplusEvaluation: String,
        underEatingDaysReview: String,
        dietStructureIssues: [String],
        nextWeekActionSuggestions: [String],
        weightGoalAdjustmentAdvice: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.spanTitle = spanTitle
        self.dateRangeText = dateRangeText
        self.providerName = providerName
        self.modelName = modelName
        self.objectiveSummarySection = objectiveSummarySection
        self.estimationAndFluctuationDisclaimer = estimationAndFluctuationDisclaimer
        self.calorieAndWeightAnalysis = calorieAndWeightAnalysis
        self.surplusEvaluation = surplusEvaluation
        self.underEatingDaysReview = underEatingDaysReview
        self.dietStructureIssues = dietStructureIssues
        self.nextWeekActionSuggestions = nextWeekActionSuggestions
        self.weightGoalAdjustmentAdvice = weightGoalAdjustmentAdvice
    }

    public var formattedMarkdownText: String {
        var sections: [String] = []
        sections.append("# 食刻 FoodLog · 饮食与体重综合分析报告")
        sections.append("生成时间：\(DateKeyHelper.dayKey(for: createdAt)) \(DateKeyHelper.timeString(for: createdAt))  |  范围：\(spanTitle)（\(dateRangeText)）  |  模型：\(providerName) (\(modelName))")
        sections.append("## 一、客观统计数据（基于本机真实记录）\n\(objectiveSummarySection)")
        sections.append("## 二、估算误差与体重短期波动说明\n\(estimationAndFluctuationDisclaimer)")
        sections.append("## 三、热量摄入与体重趋势关系\n\(calorieAndWeightAnalysis)")
        sections.append("## 四、热量盈余 / 缺口评估\n\(surplusEvaluation)")
        sections.append("## 五、摄入不足日期复盘\n\(underEatingDaysReview)")
        let issuesText = dietStructureIssues.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        sections.append("## 六、当前饮食结构存在的问题\n\(issuesText)")
        let nextWeekText = nextWeekActionSuggestions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        sections.append("## 七、下一周饮食执行建议\n\(nextWeekText)")
        sections.append("## 八、针对目标的调整建议\n\(weightGoalAdjustmentAdvice)")
        return sections.joined(separator: "\n\n")
    }
}

@Model
public final class SavedAnalysisReportRecord {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var spanTitle: String
    public var dateRangeText: String
    public var providerName: String
    public var modelName: String
    public var payloadJSON: Data

    public init(report: AIComprehensiveReport) {
        self.id = report.id
        self.createdAt = report.createdAt
        self.spanTitle = report.spanTitle
        self.dateRangeText = report.dateRangeText
        self.providerName = report.providerName
        self.modelName = report.modelName
        self.payloadJSON = (try? JSONEncoder().encode(report)) ?? Data()
    }

    public var decodedReport: AIComprehensiveReport? {
        try? JSONDecoder().decode(AIComprehensiveReport.self, from: payloadJSON)
    }
}
