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
    @State private var showingDailyGoalEditor: Bool = false

    public init() {}

    private var dailyMetrics: DailyNutritionMetrics {
        let snapshots = allFoodRecords.map(\.snapshot)
        return NutritionAndWeightEngine.calculateDailyMetrics(
            for: appState.selectedDayKey,
            entries: snapshots,
            profile: appState.profile
        )
    }

    private var todayRepresentativeWeight: Double? {
        let dayKey = appState.selectedDayKey
        let daySnapshots = allWeightRecords.filter { $0.dayKey == dayKey }.map(\.snapshot)
        return NutritionAndWeightEngine.selectDailyRepresentativeWeight(
            from: daySnapshots,
            rule: appState.profile.representativeWeightRule
        )
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    topDateHeaderBar
                    heroMagazineNutritionCard(metrics: dailyMetrics)
                    if !favoriteTemplates.isEmpty {
                        quickFavoritesStrip
                    }
                    foodJournalSection(metrics: dailyMetrics)
                    zenWeightCard
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }
            .background(FoodLogTheme.warmBackground.ignoresSafeArea())
            .navigationTitle("食刻")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !Calendar.current.isDateInToday(appState.selectedDate) {
                        Button("回今天") {
                            appState.jumpToToday()
                        }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(FoodLogTheme.charcoalText)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCalendarPopover.toggle()
                    } label: {
                        Image(systemName: "calendar")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(FoodLogTheme.charcoalText)
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
                            .tint(FoodLogTheme.deepCharcoalButton)
                            .padding(.bottom, 12)
                        }
                        .presentationDetents([.medium])
                    }
                }
            }
            .sheet(isPresented: $showingDailyGoalEditor) {
                DailyGoalAndProfileEditorSheet()
                    .environmentObject(appState)
            }
        }
    }

    // MARK: - 1. Clickable Top Date & Calorie Goal Bar (R2)

    private var topDateHeaderBar: some View {
        HStack {
            Button {
                showingDailyGoalEditor = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(DateKeyHelper.readableChineseDate(appState.selectedDate))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(FoodLogTheme.charcoalText)
                        Image(systemName: "slider.horizontal.3")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(FoodLogTheme.morandiCarbTerracotta)
                    }

                    Text("\(appState.profile.goalMode.title) · 目标 \(Int(appState.profile.targetCalories)) kcal · 点击调整")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dashboard-date-goal-header-button")

            Spacer()

            HStack(spacing: 6) {
                Button {
                    appState.moveSelectedDay(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(FoodLogTheme.charcoalText)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.85)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("前一天")

                Button {
                    appState.moveSelectedDay(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(FoodLogTheme.charcoalText)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.85)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("后一天")
            }
        }
    }

    // MARK: - 2. 2026 Magazine Hero Card & Horizon Energy Arc (R2)

    private func heroMagazineNutritionCard(metrics: DailyNutritionMetrics) -> some View {
        VStack(spacing: 16) {
            // Magazine Typography & Horizon Arc
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(metrics.totalCalories.rounded()))")
                        .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(FoodLogTheme.charcoalText)
                        .accessibilityIdentifier("today-calories-value")

                    Text("kcal")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Spacer()

                    let diff = metrics.remainingCalories
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(diff >= 0 ? "还需摄入" : "已超出")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("\(Int(abs(diff).rounded())) kcal")
                            .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(diff >= 0 ? FoodLogTheme.morandiProteinSage : FoodLogTheme.morandiCarbTerracotta)
                    }
                }

                // Horizon Energy Arc
                ZStack {
                    // Background track
                    HorizonEnergyArc()
                        .stroke(
                            FoodLogTheme.arcTrackColor,
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )

                    // Active progress arc with gradient
                    HorizonEnergyArc()
                        .trim(from: 0, to: min(1.0, max(0.01, metrics.calorieProgress)))
                        .stroke(
                            LinearGradient(
                                colors: [FoodLogTheme.arcGradientStart, FoodLogTheme.arcGradientEnd],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: metrics.totalCalories)

                    // Progress percentage badge
                    VStack(spacing: 2) {
                        Text("今日目标 \(Int(metrics.targetCalories.rounded())) kcal")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("\(Int((metrics.calorieProgress * 100).rounded()))%")
                            .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(FoodLogTheme.charcoalText)
                    }
                    .offset(y: 4)
                }
                .frame(height: 64)
                .padding(.top, 4)
            }

            // Three Centered Morandi Micro Capsules (Protein, Carbs, Fat)
            HStack(spacing: 8) {
                MorandiMacroCapsule(
                    title: "蛋白质",
                    currentGrams: metrics.totalProteinGrams,
                    targetGrams: metrics.targetProteinGrams,
                    tintColor: FoodLogTheme.morandiProteinSage
                )
                MorandiMacroCapsule(
                    title: "碳水",
                    currentGrams: metrics.totalCarbGrams,
                    targetGrams: metrics.targetCarbGrams,
                    tintColor: FoodLogTheme.morandiCarbTerracotta
                )
                MorandiMacroCapsule(
                    title: "脂肪",
                    currentGrams: metrics.totalFatGrams,
                    targetGrams: metrics.targetFatGrams,
                    tintColor: FoodLogTheme.morandiFatAlmond
                )
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)

            // Primary Floating Action Lens Pill Button + Manual Add Companion
            HStack(spacing: 10) {
                Button {
                    appState.openPhotoRecognitionSheet()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 15, weight: .bold))
                        Text("⊙ AI 拍摄餐食")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text("DeepSeek")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Capsule())
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(FoodLogTheme.deepCharcoalButton)
                            .shadow(color: FoodLogTheme.deepCharcoalButton.opacity(0.25), radius: 6, x: 0, y: 3)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("floating-camera-record-button")

                Button {
                    appState.openNewFoodSheet()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                        Text("手动添加")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(FoodLogTheme.charcoalText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .stroke(Color.black.opacity(0.1), lineWidth: 0.8)
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dashboard-manual-add-button")
            }
            .padding(.top, 6)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 3)
        )
    }

    // MARK: - 3. Quick Favorites Strip

    private var quickFavoritesStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("常吃快速记录")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(favoriteTemplates.prefix(6)) { fav in
                        Button {
                            quickLogFavorite(fav)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(FoodLogTheme.morandiProteinSage)
                                Text(fav.name)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(FoodLogTheme.charcoalText)
                                Text("\(Int(fav.caloriesPer100g * (fav.defaultGrams / 100.0))) kcal")
                                    .font(.system(size: 11, weight: .regular, design: .rounded).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(Color.white)
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - 4. Food Journal Section (R2)

    private func foodJournalSection(metrics: DailyNutritionMetrics) -> some View {
        let loggedMeals = MealType.allCases.filter { !(metrics.entriesByMeal[$0] ?? []).isEmpty }
        let unloggedMeals = MealType.allCases.filter { (metrics.entriesByMeal[$0] ?? []).isEmpty }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("今日餐次流 · Food Journal")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(FoodLogTheme.charcoalText)
                Spacer()
                Text("\(metrics.totalCount) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            ForEach(loggedMeals) { meal in
                let mealItems = metrics.entriesByMeal[meal] ?? []
                let mealCalories = metrics.calories(for: meal)
                loggedMealCard(meal: meal, items: mealItems, totalCalories: mealCalories)
            }

            if !unloggedMeals.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(loggedMeals.isEmpty ? "点击餐次开始记录今日饮食" : "待记录餐次")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
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
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(FoodLogTheme.mealColor(for: meal).opacity(0.14))
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Image(systemName: meal.systemImage)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(FoodLogTheme.mealColor(for: meal))
                                        )
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(meal.title)
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .foregroundStyle(FoodLogTheme.charcoalText)
                                        Text("点击记录")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(FoodLogTheme.charcoalText.opacity(0.5))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.white)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
                                        )
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

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(mealTint.opacity(0.16))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: meal.systemImage)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(mealTint)
                    )

                Text(meal.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(FoodLogTheme.charcoalText)

                Spacer()

                Text("\(Int(totalCalories.rounded())) kcal")
                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(mealTint)

                Menu {
                    Button {
                        appState.openPhotoRecognitionSheet(for: meal)
                    } label: {
                        Label("AI 拍照加餐", systemImage: "camera.fill")
                    }
                    Button {
                        appState.openNewFoodSheet(for: meal)
                    } label: {
                        Label("手动添加", systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(mealTint.opacity(0.85))
                }
            }

            VStack(spacing: 6) {
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        FoodThumbnailBadge(photoFilename: item.photoFilenames.first, mealType: item.mealType, size: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(FoodLogTheme.charcoalText)
                                .lineLimit(1)
                            Text("\(Int(item.grams))g" + (item.userNote.isEmpty ? "" : " · \(item.userNote)"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(item.calories.rounded())) kcal")
                                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(FoodLogTheme.charcoalText)

                            HStack(spacing: 3) {
                                Text("蛋\(Int(item.proteinGrams))")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundStyle(FoodLogTheme.morandiProteinSage)
                                Text("碳\(Int(item.carbGrams))")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundStyle(FoodLogTheme.morandiCarbTerracotta)
                                Text("脂\(Int(item.fatGrams))")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundStyle(FoodLogTheme.morandiFatAlmond)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.openEditFoodSheet(item)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
        )
    }

    // MARK: - 5. Zen Optional Weight Card (R2)

    private var zenWeightCard: some View {
        HStack(alignment: .center, spacing: 14) {
            Circle()
                .fill(FoodLogTheme.morandiProteinSage.opacity(0.16))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "scalemass.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(FoodLogTheme.morandiProteinSage)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("今日体重 · 顺其自然 (可选)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                if let weight = todayRepresentativeWeight {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.2f", weight))
                            .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(FoodLogTheme.charcoalText)
                        Text("kg · 已记录")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(FoodLogTheme.morandiProteinSage)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("未称重")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(FoodLogTheme.charcoalText.opacity(0.75))
                        Text("顺其自然，健康由每一餐开始")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Button {
                appState.openNewWeightSheet()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(FoodLogTheme.charcoalText)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(FoodLogTheme.warmSurface)
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dashboard-zen-weight-add-button")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
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
}
