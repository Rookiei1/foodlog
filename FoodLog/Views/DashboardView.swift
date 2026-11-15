import SwiftUI
import SwiftData
import Charts

public struct DashboardView: View {
    @EnvironmentObject private var appState: AppStateViewModel
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \FoodEntryRecord.eatenAt, order: .forward)
    private var allFoodRecords: [FoodEntryRecord]

    @Query(sort: \FavoriteFoodTemplate.useCount, order: .reverse)
    private var favoriteTemplates: [FavoriteFoodTemplate]

    @Query(sort: \WeightRecord.measuredAt, order: .forward)
    private var allWeightRecords: [WeightRecord]

    @State private var showingCalendarPopover: Bool = false

    public init() {}

    private var dailyMetrics: DailyNutritionMetrics {
        let snapshots = allFoodRecords.map(\.snapshot)
        return NutritionAndWeightEngine.calculateDailyMetrics(
            for: appState.selectedDayKey,
            entries: snapshots,
            profile: appState.profile
        )
    }

    private var recentWeightTrend: WeightTrendSummary {
        let snapshots = allWeightRecords.map(\.snapshot)
        let start = DateKeyHelper.shiftingDays(appState.selectedDate, by: -13)
        return NutritionAndWeightEngine.buildWeightTrend(
            records: snapshots,
            rule: appState.profile.representativeWeightRule,
            startDate: start,
            endDate: appState.selectedDate
        )
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    topDateHeaderBar
                    heroNutritionCard(metrics: dailyMetrics)
                    if !favoriteTemplates.isEmpty {
                        quickFavoritesStrip
                    }
                    mealsSection(metrics: dailyMetrics)
                    compactWeightWidget(trend: recentWeightTrend)
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("食刻")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !Calendar.current.isDateInToday(appState.selectedDate) {
                        Button("回今天") {
                            appState.jumpToToday()
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCalendarPopover.toggle()
                    } label: {
                        Image(systemName: "calendar")
                            .font(.body.weight(.semibold))
                    }
                    .popover(isPresented: $showingCalendarPopover) {
                        VStack(spacing: 12) {
                            DatePicker(
                                "选择日期",
                                selection: $appState.selectedDate,
                                displayedComponents: [.date]
                            )
                            .datePickerStyle(.graphical)
                            .environment(\.locale, Locale(identifier: "zh_CN"))
                            .padding(.horizontal)

                            Button("完成") {
                                showingCalendarPopover = false
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.bottom, 12)
                        }
                        .presentationDetents([.medium])
                    }
                }
            }
        }
    }

    // MARK: - Top Date Bar

    private var topDateHeaderBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(DateKeyHelper.readableChineseDate(appState.selectedDate))
                    .font(.title3.weight(.bold))
                Text("\(appState.profile.goalMode.title) · 目标 \(Int(appState.profile.targetCalories)) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Button {
                    appState.moveSelectedDay(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("前一天")

                Button {
                    appState.moveSelectedDay(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("后一天")
            }
        }
    }

    // MARK: - Hero Card

    private func heroNutritionCard(metrics: DailyNutritionMetrics) -> some View {
        VStack(spacing: 18) {
            HStack(alignment: .center, spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(FoodLogTheme.calorieGreen.opacity(0.14), lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: min(1.0, metrics.calorieProgress))
                        .stroke(
                            AngularGradient(
                                colors: [FoodLogTheme.calorieGreen, Color.mint, FoodLogTheme.calorieGreen],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: metrics.totalCalories)

                    VStack(spacing: 1) {
                        Text("\(Int(metrics.totalCalories.rounded()))")
                            .font(.system(size: 29, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.7)
                            .accessibilityIdentifier("today-calories-value")
                        Text("已摄入 kcal")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                }
                .frame(width: 118, height: 118)

                VStack(alignment: .leading, spacing: 10) {
                    let diff = metrics.remainingCalories
                    VStack(alignment: .leading, spacing: 2) {
                        Text(diff > 0 ? "距离目标还差" : "已超出目标")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(Int(abs(diff).rounded()))")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(diff > 0 ? .primary : FoodLogTheme.calorieGreen)
                            Text("kcal")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 8) {
                        Label(
                            "\(Int((metrics.calorieProgress * 100).rounded()))%",
                            systemImage: diff <= 0 ? "checkmark.seal.fill" : "flame.fill"
                        )
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(FoodLogTheme.calorieGreen.opacity(0.14))
                        .foregroundStyle(FoodLogTheme.calorieGreen)
                        .clipShape(Capsule())

                        Text("目标 \(Int(metrics.targetCalories.rounded()))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                macroStatBox(
                    title: "蛋白质",
                    current: metrics.totalProteinGrams,
                    target: metrics.targetProteinGrams,
                    color: FoodLogTheme.proteinBlue
                )
                macroStatBox(
                    title: "脂肪",
                    current: metrics.totalFatGrams,
                    target: metrics.targetFatGrams,
                    color: FoodLogTheme.fatAmber
                )
                macroStatBox(
                    title: "碳水",
                    current: metrics.totalCarbGrams,
                    target: metrics.targetCarbGrams,
                    color: FoodLogTheme.carbCoral
                )
            }

            HStack(spacing: 10) {
                Button {
                    appState.openPhotoRecognitionSheet()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .font(.headline.weight(.bold))
                        Text("AI 拍照记餐")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [FoodLogTheme.calorieGreen, Color(red: 0.09, green: 0.58, blue: 0.36)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("floating-camera-record-button")

                Button {
                    appState.openNewFoodSheet()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.subheadline.weight(.bold))
                        Text("手动 / 营养表")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.tertiarySystemGroupedBackground))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dashboard-manual-add-button")
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func macroStatBox(title: String, current: Double, target: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(current.rounded()))")
                    .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                Text("/\(Int(target.rounded()))g")
                    .font(.system(size: 11, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.16))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * min(1.0, max(0.0, target > 0 ? current / target : 0)))
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }

    // MARK: - Quick Favorites

    private var quickFavoritesStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(favoriteTemplates.prefix(8)) { fav in
                    Button {
                        quickLogFavorite(fav)
                    } label: {
                        let kcal = Int((fav.caloriesPer100g * fav.defaultGrams / 100.0).rounded())
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(FoodLogTheme.calorieGreen)
                            Text(fav.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("+\(kcal)")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(FoodLogTheme.calorieGreen)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Meals Section (Logged Cards + Compact Unlogged Strip)

    private func mealsSection(metrics: DailyNutritionMetrics) -> some View {
        let loggedMeals = MealType.allCases.filter { !(metrics.entriesByMeal[$0] ?? []).isEmpty }
        let unloggedMeals = MealType.allCases.filter { (metrics.entriesByMeal[$0] ?? []).isEmpty }

        return VStack(spacing: 12) {
            ForEach(loggedMeals) { meal in
                let mealItems = metrics.entriesByMeal[meal] ?? []
                let mealCalories = metrics.calories(for: meal)
                loggedMealCard(meal: meal, items: mealItems, totalCalories: mealCalories)
            }

            if !unloggedMeals.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(loggedMeals.isEmpty ? "点击餐次开始记录" : "待记录餐次")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(unloggedMeals) { meal in
                            Menu {
                                Button {
                                    appState.openPhotoRecognitionSheet(for: meal)
                                } label: {
                                    Label("AI 拍照识别\(meal.title)", systemImage: "camera.fill")
                                }
                                Button {
                                    appState.openNewFoodSheet(for: meal)
                                } label: {
                                    Label("手动添加\(meal.title)", systemImage: "square.and.pencil")
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(FoodLogTheme.mealColor(for: meal).opacity(0.15))
                                        .frame(width: 34, height: 34)
                                        .overlay(
                                            Image(systemName: meal.systemImage)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(FoodLogTheme.mealColor(for: meal))
                                        )
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(meal.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text("点击记录")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .font(.body)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color(.secondarySystemGroupedBackground))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func loggedMealCard(meal: MealType, items: [FoodEntrySnapshot], totalCalories: Double) -> some View {
        let mealTint = FoodLogTheme.mealColor(for: meal)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(mealTint.opacity(0.16))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: meal.systemImage)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(mealTint)
                    )

                Text(meal.title)
                    .font(.headline)

                Spacer()

                Text("\(Int(totalCalories.rounded())) kcal")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(mealTint)

                Menu {
                    Button {
                        appState.openPhotoRecognitionSheet(for: meal)
                    } label: {
                        Label("AI 拍照添加", systemImage: "camera.fill")
                    }
                    Button {
                        appState.openNewFoodSheet(for: meal)
                    } label: {
                        Label("手动添加", systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(spacing: 10) {
                ForEach(items) { item in
                    Button {
                        appState.openEditFoodSheet(item)
                    } label: {
                        HStack(spacing: 12) {
                            FoodThumbnailBadge(
                                photoFilename: item.photoFilenames.first,
                                mealType: item.mealType,
                                size: 44
                            )

                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    Text(item.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    if item.isFromNutritionLabel {
                                        Text("营养表")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.14))
                                            .foregroundStyle(.blue)
                                            .clipShape(Capsule())
                                    }
                                }

                                HStack(spacing: 5) {
                                    Text("\(Int(item.grams))g")
                                        .font(.caption2.weight(.medium).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    MacroTagPill(prefix: "P", grams: item.proteinGrams, color: FoodLogTheme.proteinBlue)
                                    MacroTagPill(prefix: "F", grams: item.fatGrams, color: FoodLogTheme.fatAmber)
                                    MacroTagPill(prefix: "C", grams: item.carbGrams, color: FoodLogTheme.carbCoral)
                                }
                            }

                            Spacer(minLength: 4)

                            VStack(alignment: .trailing, spacing: 1) {
                                Text("\(Int(item.calories.rounded()))")
                                    .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(.primary)
                                Text("kcal")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            duplicateEntry(item)
                        } label: {
                            Label("复制一条", systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            deleteEntry(id: item.id)
                        } label: {
                            Label("删除记录", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Compact Weight Widget

    private func compactWeightWidget(trend: WeightTrendSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(FoodLogTheme.weightPurple.opacity(0.16))
                        .frame(width: 30, height: 30)
                        .overlay(
                            Image(systemName: "scalemass.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(FoodLogTheme.weightPurple)
                        )
                    Text("体重趋势")
                        .font(.headline)
                }
                Spacer()
                Button {
                    appState.openNewWeightSheet()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                        Text("记体重")
                            .font(.caption.weight(.bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(FoodLogTheme.weightPurple.opacity(0.14))
                    .foregroundStyle(FoodLogTheme.weightPurple)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    if let latest = trend.latestWeightKg {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(String(format: "%.2f", latest))
                                .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                            Text("kg")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("暂未记录")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        if let rate = trend.weeklyRateKg {
                            Text(String(format: "%+.2f kg/周", rate))
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(FoodLogTheme.weightPurple.opacity(0.14))
                                .foregroundStyle(FoodLogTheme.weightPurple)
                                .clipShape(Capsule())
                        }
                        Text("目标 \(String(format: "%.1f", appState.profile.targetWeightKg)) kg")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if trend.dailyPoints.count >= 2 {
                    Chart(trend.dailyPoints) { pt in
                        AreaMark(
                            x: .value("日期", pt.date),
                            yStart: .value("底", (trend.minWeightKg ?? pt.weightKg) - 0.3),
                            yEnd: .value("体重", pt.weightKg)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [FoodLogTheme.weightPurple.opacity(0.28), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("日期", pt.date),
                            y: .value("体重", pt.weightKg)
                        )
                        .foregroundStyle(FoodLogTheme.weightPurple)
                        .lineStyle(StrokeStyle(lineWidth: 2.2))
                        .interpolationMethod(.catmullRom)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(width: 130, height: 56)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func quickLogFavorite(_ fav: FavoriteFoodTemplate) {
        let targetDate = DateKeyHelper.combining(day: appState.selectedDate, withTimeFrom: Date())
        let snapshot = fav.snapshot.makeEntrySnapshot(
            mealType: MealType.suggested(for: Date()),
            date: targetDate
        )
        modelContext.insert(FoodEntryRecord(snapshot: snapshot))
        fav.useCount += 1
        fav.lastUsedAt = Date()
        try? modelContext.save()
        appState.showTemporaryBanner("已记「\(fav.name)」+\(Int(snapshot.calories.rounded())) kcal")
    }

    private func duplicateEntry(_ item: FoodEntrySnapshot) {
        let copy = item.duplicated(for: appState.selectedDate)
        modelContext.insert(FoodEntryRecord(snapshot: copy))
        try? modelContext.save()
        appState.showTemporaryBanner("已复制「\(item.name)」")
    }

    private func deleteEntry(id: UUID) {
        if let record = allFoodRecords.first(where: { $0.id == id }) {
            ImageStorageService.shared.deletePhotos(filenames: record.photoFilenames)
            modelContext.delete(record)
            try? modelContext.save()
        }
    }
}
