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
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(spacing: 16) {
                        dateNavigationHeader
                        calorieHeroDashboardCard(metrics: dailyMetrics)
                        if !favoriteTemplates.isEmpty {
                            quickFavoritesStrip
                        }
                        mealsSection(metrics: dailyMetrics)
                        recentWeightCard(trend: recentWeightTrend)
                        Spacer(minLength: 88)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .background(Color(.systemGroupedBackground))

                floatingCameraButton
                    .padding(.trailing, 20)
                    .padding(.bottom, 18)
            }
            .navigationTitle("食刻 FoodLog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        appState.jumpToToday()
                    } label: {
                        Text("今天")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        appState.openNewFoodSheet()
                    } label: {
                        Label("手动记录", systemImage: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("dashboard-manual-add-button")
                }
            }
        }
    }

    private var dateNavigationHeader: some View {
        HStack(spacing: 12) {
            Button {
                appState.moveSelectedDay(by: -1)
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("前一天")

            Spacer()

            Button {
                showingCalendarPopover.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .foregroundStyle(FoodLogTheme.calorieGreen)
                    Text(DateKeyHelper.readableChineseDate(appState.selectedDate))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
            .popover(isPresented: $showingCalendarPopover) {
                VStack(spacing: 12) {
                    DatePicker(
                        "选择记录日期",
                        selection: $appState.selectedDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                    .padding()

                    Button("完成") {
                        showingCalendarPopover = false
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 12)
                }
                .presentationDetents([.medium])
            }

            Spacer()

            Button {
                appState.moveSelectedDay(by: 1)
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("后一天")
        }
    }

    private func calorieHeroDashboardCard(metrics: DailyNutritionMetrics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(FoodLogTheme.calorieGreen.opacity(0.18), lineWidth: 14)
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
                        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: metrics.totalCalories)

                    VStack(spacing: 2) {
                        Text("\(Int(metrics.totalCalories.rounded()))")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.7)
                            .accessibilityIdentifier("today-calories-value")
                        Text("已摄入 kcal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                }
                .frame(width: 118, height: 118)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(appState.profile.goalMode.title)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(FoodLogTheme.calorieGreen.opacity(0.15))
                            .foregroundStyle(FoodLogTheme.calorieGreen)
                            .clipShape(Capsule())
                        Spacer()
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("目标")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(Int(metrics.targetCalories.rounded())) kcal")
                            .font(.headline.monospacedDigit())
                    }

                    let diff = metrics.remainingCalories
                    if diff > 0 {
                        Label("距离目标还差 \(Int(diff.rounded())) kcal", systemImage: "arrow.up.right.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                    } else {
                        Label("已达成今日热量目标（+\(Int(abs(diff).rounded())) kcal）", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FoodLogTheme.calorieGreen)
                    }

                    ProgressView(value: min(1.0, metrics.calorieProgress))
                        .tint(FoodLogTheme.calorieGreen)
                }
            }

            Divider()

            HStack(spacing: 12) {
                macroProgressPill(
                    title: "蛋白质",
                    current: metrics.totalProteinGrams,
                    target: metrics.targetProteinGrams,
                    color: FoodLogTheme.proteinBlue
                )
                macroProgressPill(
                    title: "脂肪",
                    current: metrics.totalFatGrams,
                    target: metrics.targetFatGrams,
                    color: FoodLogTheme.fatAmber
                )
                macroProgressPill(
                    title: "碳水化合物",
                    current: metrics.totalCarbGrams,
                    target: metrics.targetCarbGrams,
                    color: FoodLogTheme.carbCoral
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func macroProgressPill(title: String, current: Double, target: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(current.rounded()))")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                Text("/\(Int(target.rounded()))g")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.18))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * min(1.0, max(0.0, target > 0 ? current / target : 0)))
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }

    private var quickFavoritesStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("常吃收藏 · 一键快记", systemImage: "bolt.heart.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("点按直接记入所选日期")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(favoriteTemplates.prefix(8)) { fav in
                        Button {
                            quickLogFavorite(fav)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(FoodLogTheme.calorieGreen)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fav.name)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    let kcal = Int((fav.caloriesPer100g * fav.defaultGrams / 100.0).rounded())
                                    Text("\(Int(fav.defaultGrams))g · \(kcal) kcal")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func mealsSection(metrics: DailyNutritionMetrics) -> some View {
        VStack(spacing: 12) {
            ForEach(MealType.allCases) { meal in
                let mealItems = metrics.entriesByMeal[meal] ?? []
                let mealCalories = metrics.calories(for: meal)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(meal.title, systemImage: meal.systemImage)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(Int(mealCalories.rounded())) kcal")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(mealCalories > 0 ? FoodLogTheme.calorieGreen : .secondary)

                        Button {
                            appState.openPhotoRecognitionSheet(for: meal)
                        } label: {
                            Image(systemName: "camera.circle.fill")
                                .font(.title3)
                                .foregroundStyle(FoodLogTheme.calorieGreen)
                        }
                        .accessibilityLabel("拍照添加\(meal.title)")

                        Button {
                            appState.openNewFoodSheet(for: meal)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.primary)
                        }
                        .accessibilityLabel("手动添加\(meal.title)")
                    }

                    if mealItems.isEmpty {
                        Text("暂无\(meal.title)记录，点击右侧相机或加号快速添加")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        Divider()
                        ForEach(mealItems) { item in
                            Button {
                                appState.openEditFoodSheet(item)
                            } label: {
                                HStack(alignment: .center, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(item.name)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(.primary)
                                            if item.isFromNutritionLabel {
                                                Text("营养表")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1)
                                                    .background(Color.blue.opacity(0.15))
                                                    .foregroundStyle(.blue)
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        Text("\(Int(item.grams))g · 蛋白 \(String(format: "%.1f", item.proteinGrams))g · 脂肪 \(String(format: "%.1f", item.fatGrams))g · 碳水 \(String(format: "%.1f", item.carbGrams))g")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(Int(item.calories.rounded())) kcal")
                                        .font(.subheadline.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(.primary)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    duplicateEntry(item)
                                } label: {
                                    Label("复制一条到当前日期", systemImage: "doc.on.doc")
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
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
        }
    }

    private func recentWeightCard(trend: WeightTrendSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("近期体重趋势", systemImage: "scalemass.fill")
                    .font(.headline)
                    .foregroundStyle(FoodLogTheme.weightPurple)
                Spacer()
                Button {
                    appState.openNewWeightSheet()
                } label: {
                    Label("记体重", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("最新代表体重")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let latest = trend.latestWeightKg {
                        Text(String(format: "%.2f kg", latest))
                            .font(.title3.weight(.bold).monospacedDigit())
                    } else {
                        Text("暂无记录")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("目标体重")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f kg", appState.profile.targetWeightKg))
                        .font(.title3.weight(.semibold).monospacedDigit())
                }

                if let rate = trend.weeklyRateKg {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("每周变化速度")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%+.2f kg/周", rate))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(FoodLogTheme.weightPurple)
                    }
                }
            }

            if trend.dailyPoints.count >= 2 {
                Chart(trend.dailyPoints) { pt in
                    LineMark(
                        x: .value("日期", pt.date),
                        y: .value("体重", pt.weightKg)
                    )
                    .foregroundStyle(FoodLogTheme.weightPurple)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("日期", pt.date),
                        y: .value("体重", pt.weightKg)
                    )
                    .foregroundStyle(FoodLogTheme.weightPurple)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 110)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var floatingCameraButton: some View {
        Button {
            appState.openPhotoRecognitionSheet()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "camera.viewfinder")
                    .font(.title3.weight(.bold))
                Text("拍照记录")
                    .font(.headline.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [FoodLogTheme.calorieGreen, Color(red: 0.08, green: 0.58, blue: 0.36)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: FoodLogTheme.calorieGreen.opacity(0.38), radius: 10, x: 0, y: 5)
            )
        }
        .accessibilityIdentifier("floating-camera-record-button")
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
        appState.showTemporaryBanner("已快速记录「\(fav.name)」+\(Int(snapshot.calories.rounded())) kcal")
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
