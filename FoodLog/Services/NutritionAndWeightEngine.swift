import Foundation

public struct DailyNutritionMetrics: Equatable, Sendable {
    public var dayKey: String
    public var totalCalories: Double
    public var totalProteinGrams: Double
    public var totalFatGrams: Double
    public var totalCarbGrams: Double
    public var targetCalories: Double
    public var targetProteinGrams: Double
    public var targetFatGrams: Double
    public var targetCarbGrams: Double
    public var entriesByMeal: [MealType: [FoodEntrySnapshot]]

    public var totalCount: Int {
        entriesByMeal.values.reduce(0) { $0 + $1.count }
    }

    public var remainingCalories: Double {
        targetCalories - totalCalories
    }

    public var remainingProteinGrams: Double {
        targetProteinGrams - totalProteinGrams
    }

    public var calorieProgress: Double {
        guard targetCalories > 0 else { return 0 }
        return min(1.5, max(0, totalCalories / targetCalories))
    }

    public var proteinProgress: Double {
        guard targetProteinGrams > 0 else { return 0 }
        return min(1.5, max(0, totalProteinGrams / targetProteinGrams))
    }

    public var fatProgress: Double {
        guard targetFatGrams > 0 else { return 0 }
        return min(1.5, max(0, totalFatGrams / targetFatGrams))
    }

    public var carbProgress: Double {
        guard targetCarbGrams > 0 else { return 0 }
        return min(1.5, max(0, totalCarbGrams / targetCarbGrams))
    }

    public func calories(for meal: MealType) -> Double {
        (entriesByMeal[meal] ?? []).reduce(0) { $0 + $1.calories }
    }
}

public enum EnergyUnit: String, CaseIterable, Codable, Identifiable, Sendable {
    case kilojoule = "kJ"
    case kilocalorie = "kcal"

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .kilojoule: return "千焦 (kJ) — 国标包装常见"
        case .kilocalorie: return "千卡 (kcal)"
        }
    }
}

public struct NutritionLabelInput: Equatable, Sendable {
    public var energyPerBasis: Double
    public var energyUnit: EnergyUnit
    public var basisGrams: Double
    public var proteinPerBasis: Double
    public var fatPerBasis: Double
    public var carbPerBasis: Double
    public var packageNetWeightGrams: Double
    public var consumedServingsRatio: Double

    public init(
        energyPerBasis: Double,
        energyUnit: EnergyUnit = .kilojoule,
        basisGrams: Double = 100.0,
        proteinPerBasis: Double,
        fatPerBasis: Double,
        carbPerBasis: Double,
        packageNetWeightGrams: Double,
        consumedServingsRatio: Double = 1.0
    ) {
        self.energyPerBasis = max(0, energyPerBasis)
        self.energyUnit = energyUnit
        self.basisGrams = max(1, basisGrams)
        self.proteinPerBasis = max(0, proteinPerBasis)
        self.fatPerBasis = max(0, fatPerBasis)
        self.carbPerBasis = max(0, carbPerBasis)
        self.packageNetWeightGrams = max(1, packageNetWeightGrams)
        self.consumedServingsRatio = max(0.05, consumedServingsRatio)
    }
}

public struct NutritionLabelResult: Equatable, Sendable {
    public var consumedGrams: Double
    public var calories: Double
    public var proteinGrams: Double
    public var fatGrams: Double
    public var carbGrams: Double
    public var explanation: String
}

public enum NutritionAndWeightEngine {
    /// Aggregates actual saved food entries for the given dayKey. Never invents or randomizes numbers.
    public static func calculateDailyMetrics(
        for dayKey: String,
        entries: [FoodEntrySnapshot],
        profile: UserProfileSettings
    ) -> DailyNutritionMetrics {
        let dayEntries = entries
            .filter { $0.dayKey == dayKey }
            .sorted { $0.eatenAt < $1.eatenAt }

        var totalCalories = 0.0
        var totalProtein = 0.0
        var totalFat = 0.0
        var totalCarbs = 0.0
        var grouped: [MealType: [FoodEntrySnapshot]] = [:]
        for meal in MealType.allCases {
            grouped[meal] = []
        }

        for item in dayEntries {
            totalCalories += item.calories
            totalProtein += item.proteinGrams
            totalFat += item.fatGrams
            totalCarbs += item.carbGrams
            grouped[item.mealType, default: []].append(item)
        }

        return DailyNutritionMetrics(
            dayKey: dayKey,
            totalCalories: (totalCalories * 10).rounded() / 10,
            totalProteinGrams: (totalProtein * 10).rounded() / 10,
            totalFatGrams: (totalFat * 10).rounded() / 10,
            totalCarbGrams: (totalCarbs * 10).rounded() / 10,
            targetCalories: profile.targetCalories,
            targetProteinGrams: profile.targetProteinGrams,
            targetFatGrams: profile.targetFatGrams,
            targetCarbGrams: profile.targetCarbGrams,
            entriesByMeal: grouped
        )
    }

    /// Converts nutrition facts table values (per 100g or per serving, in kJ or kcal) + package net weight into exact intake values.
    public static func calculateFromNutritionLabel(_ input: NutritionLabelInput) -> NutritionLabelResult {
        let consumedGrams = (input.packageNetWeightGrams * input.consumedServingsRatio * 10).rounded() / 10
        let multiplier = consumedGrams / input.basisGrams
        let kcalPerBasis: Double
        switch input.energyUnit {
        case .kilojoule:
            kcalPerBasis = input.energyPerBasis / 4.184
        case .kilocalorie:
            kcalPerBasis = input.energyPerBasis
        }

        let calories = (kcalPerBasis * multiplier * 10).rounded() / 10
        let protein = (input.proteinPerBasis * multiplier * 10).rounded() / 10
        let fat = (input.fatPerBasis * multiplier * 10).rounded() / 10
        let carbs = (input.carbPerBasis * multiplier * 10).rounded() / 10

        let unitNote = input.energyUnit == .kilojoule
            ? "每 \(Int(input.basisGrams))g 含 \(Int(input.energyPerBasis)) kJ（折合 \(Int(kcalPerBasis.rounded())) kcal）"
            : "每 \(Int(input.basisGrams))g 含 \(Int(input.energyPerBasis)) kcal"
        let explanation = "依据包装营养成分表计算：\(unitNote)，整包净含量 \(Int(input.packageNetWeightGrams))g，本次食用 \(Int(consumedGrams))g。"

        return NutritionLabelResult(
            consumedGrams: consumedGrams,
            calories: calories,
            proteinGrams: protein,
            fatGrams: fat,
            carbGrams: carbs,
            explanation: explanation
        )
    }

    /// Selects a single consistent daily representative weight when a user weighs in multiple times on the same day.
    public static func selectDailyRepresentativeWeight(
        from sameDayRecords: [WeightRecordSnapshot],
        rule: DailyRepresentativeRule
    ) -> Double? {
        guard !sameDayRecords.isEmpty else { return nil }
        let sortedByTime = sameDayRecords.sorted { $0.measuredAt < $1.measuredAt }

        switch rule {
        case .morningFastingFirst:
            if let overrideItem = sortedByTime.first(where: { $0.isRepresentativeOverride }) {
                return overrideItem.weightKg
            }
            if let morning = sortedByTime.first(where: { $0.slot == .morningFasting }) {
                return morning.weightKg
            }
            return sortedByTime.first?.weightKg
        case .lowestOfDay:
            return sortedByTime.map(\.weightKg).min()
        case .latestOfDay:
            return sortedByTime.last?.weightKg
        case .averageOfDay:
            let sum = sortedByTime.reduce(0.0) { $0 + $1.weightKg }
            return ((sum / Double(sortedByTime.count)) * 100).rounded() / 100
        }
    }

    /// Computes daily points, 7-day rolling averages, weekly averages, and weekly change rate for a date range.
    public static func buildWeightTrend(
        records: [WeightRecordSnapshot],
        rule: DailyRepresentativeRule,
        startDate: Date? = nil,
        endDate: Date? = nil,
        calendar: Calendar = .current
    ) -> WeightTrendSummary {
        let grouped = Dictionary(grouping: records, by: \.dayKey)
        let sortedKeys = grouped.keys.sorted()

        var rawPoints: [DailyWeightPoint] = []
        for key in sortedKeys {
            guard let dayRecords = grouped[key],
                  let repWeight = selectDailyRepresentativeWeight(from: dayRecords, rule: rule),
                  let date = DateKeyHelper.date(fromDayKey: key, calendar: calendar) else {
                continue
            }
            if let startDate {
                let startKey = DateKeyHelper.dayKey(for: startDate, calendar: calendar)
                if key < startKey { continue }
            }
            if let endDate {
                let endKey = DateKeyHelper.dayKey(for: endDate, calendar: calendar)
                if key > endKey { continue }
            }
            rawPoints.append(
                DailyWeightPoint(
                    dayKey: key,
                    date: date,
                    weightKg: repWeight,
                    sampleCount: dayRecords.count,
                    ruleUsed: rule,
                    rolling7DayAverageKg: nil
                )
            )
        }

        // Fill 7-day rolling average
        for index in rawPoints.indices {
            let windowStart = max(0, index - 6)
            let slice = rawPoints[windowStart...index]
            let avg = slice.reduce(0.0) { $0 + $1.weightKg } / Double(slice.count)
            rawPoints[index].rolling7DayAverageKg = (avg * 100).rounded() / 100
        }

        // Weekly averages grouped by ISO year-week
        var weekBuckets: [String: [DailyWeightPoint]] = [:]
        for point in rawPoints {
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: point.date)
            let label = String(format: "%04d-W%02d", comps.yearForWeekOfYear ?? 2026, comps.weekOfYear ?? 1)
            weekBuckets[label, default: []].append(point)
        }

        let sortedWeekLabels = weekBuckets.keys.sorted()
        var weeklyAverages: [WeeklyWeightAverage] = []
        var previousAvg: Double? = nil
        for label in sortedWeekLabels {
            guard let pts = weekBuckets[label], let first = pts.first, let last = pts.last else { continue }
            let avg = ((pts.reduce(0.0) { $0 + $1.weightKg } / Double(pts.count)) * 100).rounded() / 100
            let delta = previousAvg.map { ((avg - $0) * 100).rounded() / 100 }
            weeklyAverages.append(
                WeeklyWeightAverage(
                    weekLabel: label,
                    startDate: first.date,
                    endDate: last.date,
                    averageKg: avg,
                    deltaFromPreviousWeekKg: delta,
                    sampleDays: pts.count
                )
            )
            previousAvg = avg
        }

        let startWeight = rawPoints.first?.weightKg
        let latestWeight = rawPoints.last?.weightKg
        let totalChange: Double?
        let weeklyRate: Double?
        if let first = rawPoints.first, let last = rawPoints.last, rawPoints.count >= 2 {
            let diff = ((last.weightKg - first.weightKg) * 100).rounded() / 100
            totalChange = diff
            let daysBetween = max(1.0, last.date.timeIntervalSince(first.date) / 86_400.0)
            weeklyRate = (((diff / daysBetween) * 7.0) * 100).rounded() / 100
        } else {
            totalChange = nil
            weeklyRate = nil
        }

        return WeightTrendSummary(
            dailyPoints: rawPoints,
            weeklyAverages: weeklyAverages,
            latestWeightKg: latestWeight,
            startWeightKg: startWeight,
            totalChangeKg: totalChange,
            weeklyRateKg: weeklyRate,
            minWeightKg: rawPoints.map(\.weightKg).min(),
            maxWeightKg: rawPoints.map(\.weightKg).max()
        )
    }

    /// Generates the objective dataset digest for AI comprehensive analysis.
    public static func buildObjectiveDigest(
        span: AnalysisTimeSpan,
        foodEntries: [FoodEntrySnapshot],
        weightRecords: [WeightRecordSnapshot],
        profile: UserProfileSettings,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> ObjectiveDatasetDigest {
        let endKey = DateKeyHelper.dayKey(for: referenceDate, calendar: calendar)
        let startKey: String
        if let limit = span.dayLimit {
            let startDate = DateKeyHelper.shiftingDays(referenceDate, by: -(limit - 1), calendar: calendar)
            startKey = DateKeyHelper.dayKey(for: startDate, calendar: calendar)
        } else {
            let earliestFood = foodEntries.map(\.dayKey).min()
            let earliestWeight = weightRecords.map(\.dayKey).min()
            startKey = [earliestFood, earliestWeight].compactMap { $0 }.min() ?? endKey
        }

        let filteredFoods = foodEntries.filter { $0.dayKey >= startKey && $0.dayKey <= endKey }
        let filteredWeights = weightRecords.filter { $0.dayKey >= startKey && $0.dayKey <= endKey }

        let foodsByDay = Dictionary(grouping: filteredFoods, by: \.dayKey)
        let weightsByDay = Dictionary(grouping: filteredWeights, by: \.dayKey)
        let allDays = Set(foodsByDay.keys).union(weightsByDay.keys).sorted()

        var dailySeries: [DailyCalorieDigestItem] = []
        var underEatingDays: [String] = []
        var lowProteinDays: [String] = []
        var mealTotals: [MealType: Double] = [:]
        var foodFrequency: [String: Int] = [:]

        for item in filteredFoods {
            mealTotals[item.mealType, default: 0] += item.calories
            if !item.name.isEmpty {
                foodFrequency[item.name, default: 0] += 1
            }
        }

        for day in allDays {
            let dayFoods = foodsByDay[day] ?? []
            let dayWeights = weightsByDay[day] ?? []
            let kcal = dayFoods.reduce(0.0) { $0 + $1.calories }
            let protein = dayFoods.reduce(0.0) { $0 + $1.proteinGrams }
            let fat = dayFoods.reduce(0.0) { $0 + $1.fatGrams }
            let carb = dayFoods.reduce(0.0) { $0 + $1.carbGrams }
            let repW = selectDailyRepresentativeWeight(from: dayWeights, rule: profile.representativeWeightRule)

            if !dayFoods.isEmpty {
                if kcal < profile.targetCalories * 0.85 {
                    underEatingDays.append(day)
                }
                if protein < profile.targetProteinGrams * 0.85 {
                    lowProteinDays.append(day)
                }
            }

            dailySeries.append(
                DailyCalorieDigestItem(
                    dayKey: day,
                    calories: (kcal * 10).rounded() / 10,
                    proteinGrams: (protein * 10).rounded() / 10,
                    fatGrams: (fat * 10).rounded() / 10,
                    carbGrams: (carb * 10).rounded() / 10,
                    entryCount: dayFoods.count,
                    representativeWeightKg: repW
                )
            )
        }

        let loggedFoodItems = dailySeries.filter { $0.entryCount > 0 }
        let loggedFoodCount = max(1, loggedFoodItems.count)
        let avgCalories = loggedFoodItems.isEmpty ? 0 : loggedFoodItems.reduce(0.0) { $0 + $1.calories } / Double(loggedFoodCount)
        let avgProtein = loggedFoodItems.isEmpty ? 0 : loggedFoodItems.reduce(0.0) { $0 + $1.proteinGrams } / Double(loggedFoodCount)
        let avgFat = loggedFoodItems.isEmpty ? 0 : loggedFoodItems.reduce(0.0) { $0 + $1.fatGrams } / Double(loggedFoodCount)
        let avgCarb = loggedFoodItems.isEmpty ? 0 : loggedFoodItems.reduce(0.0) { $0 + $1.carbGrams } / Double(loggedFoodCount)

        let totalMealCalories = max(1.0, mealTotals.values.reduce(0.0, +))
        var mealShares: [String: Double] = [:]
        for meal in MealType.allCases {
            let share = ((mealTotals[meal] ?? 0) / totalMealCalories) * 100.0
            mealShares[meal.title] = (share * 10).rounded() / 10
        }

        let topFoods = foodFrequency
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { "\($0.key)×\($0.value)" }

        let weightTrend = buildWeightTrend(
            records: filteredWeights,
            rule: profile.representativeWeightRule,
            calendar: calendar
        )

        let startDateObj = DateKeyHelper.date(fromDayKey: startKey, calendar: calendar) ?? referenceDate
        let endDateObj = DateKeyHelper.date(fromDayKey: endKey, calendar: calendar) ?? referenceDate
        let calendarSpanDays = max(1, Int((endDateObj.timeIntervalSince(startDateObj) / 86_400.0).rounded()) + 1)

        return ObjectiveDatasetDigest(
            span: span,
            startDayKey: startKey,
            endDayKey: endKey,
            totalCalendarDays: calendarSpanDays,
            loggedFoodDays: loggedFoodItems.count,
            loggedWeightDays: weightTrend.dailyPoints.count,
            averageDailyCalories: (avgCalories * 10).rounded() / 10,
            averageDailyProteinGrams: (avgProtein * 10).rounded() / 10,
            averageDailyFatGrams: (avgFat * 10).rounded() / 10,
            averageDailyCarbGrams: (avgCarb * 10).rounded() / 10,
            targetCalories: profile.targetCalories,
            targetProteinGrams: profile.targetProteinGrams,
            goalMode: profile.goalMode,
            startWeightKg: weightTrend.startWeightKg,
            endWeightKg: weightTrend.latestWeightKg,
            weightChangeKg: weightTrend.totalChangeKg,
            weeklyWeightRateKg: weightTrend.weeklyRateKg,
            underEatingDayKeys: underEatingDays,
            lowProteinDayKeys: lowProteinDays,
            mealSharePercentages: mealShares,
            topFoods: topFoods,
            dailySeries: dailySeries
        )
    }
}
