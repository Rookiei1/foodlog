import SwiftUI
import SwiftData
import Charts

public struct HistoryView: View {
    @EnvironmentObject private var appState: AppStateViewModel
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \FoodEntryRecord.eatenAt, order: .reverse)
    private var allFoodRecords: [FoodEntryRecord]

    @Query(sort: \WeightRecord.measuredAt, order: .reverse)
    private var allWeightRecords: [WeightRecord]

    public enum HistorySegment: String, CaseIterable, Identifiable {
        case food = "饮食明细"
        case weight = "体重记录"
        public var id: String { rawValue }
    }

    @State private var selectedSegment: HistorySegment = .food
    @State private var searchText: String = ""
    @State private var selectedMealFilter: MealType? = nil
    @State private var weightRangeFilter: WeightRangeFilter = .days30
    @State private var exportedFoodURL: URL? = nil
    @State private var exportedWeightURL: URL? = nil

    public init() {}

    // MARK: - Filtered Food Entries

    private var filteredFoodEntries: [FoodEntryRecord] {
        allFoodRecords.filter { record in
            if let meal = selectedMealFilter, record.mealType != meal {
                return false
            }
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let q = searchText.lowercased()
                let matchName = record.name.lowercased().contains(q)
                let matchNote = record.userNote.lowercased().contains(q)
                if !matchName && !matchNote { return false }
            }
            return true
        }
    }

    // MARK: - Weight Trend Calculation

    private var activeWeightDateBounds: (Date?, Date?) {
        let now = Date()
        switch weightRangeFilter {
        case .days7:
            return (DateKeyHelper.shiftingDays(now, by: -6), now)
        case .days30:
            return (DateKeyHelper.shiftingDays(now, by: -29), now)
        case .days90:
            return (DateKeyHelper.shiftingDays(now, by: -89), now)
        case .custom:
            return (DateKeyHelper.shiftingDays(now, by: -29), now)
        }
    }

    private var weightTrendSummary: WeightTrendSummary {
        let (start, end) = activeWeightDateBounds
        return NutritionAndWeightEngine.buildWeightTrend(
            records: allWeightRecords.map(\.snapshot),
            rule: appState.profile.representativeWeightRule,
            startDate: start,
            endDate: end
        )
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented control switcher
                Picker("历史记录类型", selection: $selectedSegment) {
                    ForEach(HistorySegment.allCases) { seg in
                        Text(seg.rawValue).tag(seg)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(FoodLogTheme.warmBackground)

                // Main Content View
                Group {
                    if selectedSegment == .food {
                        foodEntriesSegmentView
                    } else {
                        weightRecordsSegmentView
                    }
                }
            }
            .background(FoodLogTheme.warmBackground.ignoresSafeArea())
            .navigationTitle("历史记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let foodURL = exportedFoodURL {
                            ShareLink(item: foodURL) {
                                Label("导出饮食记录 CSV", systemImage: "tablecells.fill")
                            }
                        }
                        if let weightURL = exportedWeightURL {
                            ShareLink(item: weightURL) {
                                Label("导出体重记录 CSV", systemImage: "scalemass.fill")
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 11, weight: .semibold))
                            Text("导出 CSV")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(FoodLogTheme.charcoalText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.85))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.black.opacity(0.12), lineWidth: 0.8)
                        )
                    }
                    .accessibilityIdentifier("history-export-csv-button")
                }
            }
            .onAppear {
                if appState.historySegment == "weight" {
                    selectedSegment = .weight
                }
                refreshExportFiles()
            }
            .onChange(of: allFoodRecords.count) { _, _ in
                refreshExportFiles()
            }
            .onChange(of: allWeightRecords.count) { _, _ in
                refreshExportFiles()
            }
        }
    }

    // MARK: - Food Entries Segment

    private var foodEntriesSegmentView: some View {
        VStack(spacing: 0) {
            // Search and Meal Filters
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索餐食名称或备注...", text: $searchText)
                        .font(.subheadline)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white)
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        filterMealPill(title: "全部餐次", isSelected: selectedMealFilter == nil) {
                            selectedMealFilter = nil
                        }
                        ForEach(MealType.allCases) { meal in
                            filterMealPill(title: meal.title, isSelected: selectedMealFilter == meal) {
                                selectedMealFilter = meal
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(FoodLogTheme.warmBackground)

            // Meal List
            if filteredFoodEntries.isEmpty {
                VStack(spacing: 12) {
                    Spacer(minLength: 40)
                    Image(systemName: "fork.knife.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("暂无符合条件的饮食记录")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(FoodLogTheme.charcoalText.opacity(0.7))
                    Text("在首页使用【⊙ AI 拍摄餐食】或手动添加即可记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(filteredFoodEntries) { entry in
                        foodEntryRow(entry: entry)
                            .listRowBackground(Color.white.opacity(0.85))
                            .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                appState.openEditFoodSheet(entry.snapshot)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    modelContext.delete(entry)
                                    try? modelContext.save()
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    duplicateFoodEntry(entry)
                                } label: {
                                    Label("再记一次", systemImage: "doc.on.doc")
                                }
                                .tint(FoodLogTheme.morandiProteinSage)
                            }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func filterMealPill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                .foregroundStyle(isSelected ? .white : FoodLogTheme.charcoalText)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isSelected ? FoodLogTheme.deepCharcoalButton : Color.white)
                )
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(isSelected ? 0 : 0.1), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
    }

    private func foodEntryRow(entry: FoodEntryRecord) -> some View {
        HStack(spacing: 12) {
            FoodThumbnailBadge(photoFilename: entry.photoFilenames.first, mealType: entry.mealType, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.mealType.title)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(FoodLogTheme.mealColor(for: entry.mealType))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(FoodLogTheme.mealColor(for: entry.mealType).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                    Text(entry.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(FoodLogTheme.charcoalText)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text(DateKeyHelper.timeString(for: entry.eatenAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text("\(Int(entry.grams))g")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if !entry.userNote.isEmpty {
                        Text(entry.userNote)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int(entry.calories.rounded()))")
                    .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(FoodLogTheme.charcoalText)
                + Text(" kcal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Text("蛋 \(Int(entry.proteinGrams.rounded()))")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(FoodLogTheme.morandiProteinSage)
                    Text("碳 \(Int(entry.carbGrams.rounded()))")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(FoodLogTheme.morandiCarbTerracotta)
                    Text("脂 \(Int(entry.fatGrams.rounded()))")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(FoodLogTheme.morandiFatAlmond)
                }
            }
        }
    }

    private func duplicateFoodEntry(_ entry: FoodEntryRecord) {
        let copy = FoodEntryRecord(
            name: entry.name,
            mealType: entry.mealType,
            eatenAt: Date(),
            grams: entry.grams,
            calories: entry.calories,
            proteinGrams: entry.proteinGrams,
            fatGrams: entry.fatGrams,
            carbGrams: entry.carbGrams,
            photoFilenames: entry.photoFilenames,
            isFromNutritionLabel: entry.isFromNutritionLabel,
            aiAnalysisBasis: entry.aiAnalysisBasis,
            uncertaintyNote: entry.uncertaintyNote,
            userNote: entry.userNote
        )
        modelContext.insert(copy)
        try? modelContext.save()
        appState.showTemporaryBanner("已再次记录：\(copy.name)")
    }

    // MARK: - Weight Records Segment

    private var weightRecordsSegmentView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Weight Trend Chart Card
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("最新代表体重")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(weightTrendSummary.latestWeightKg.map { String(format: "%.2f", $0) } ?? "--")
                                    .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(FoodLogTheme.charcoalText)
                                Text("kg")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)

                                if let rate = weightTrendSummary.weeklyRateKg {
                                    Text(String(format: "%+.2f kg/周", rate))
                                        .font(.caption.weight(.bold).monospacedDigit())
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2.5)
                                        .background(FoodLogTheme.morandiProteinSage.opacity(0.18))
                                        .foregroundStyle(FoodLogTheme.morandiProteinSage)
                                        .clipShape(Capsule())
                                }
                            }
                        }

                        Spacer()

                        Button {
                            appState.openNewWeightSheet()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text("记体重")
                            }
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(FoodLogTheme.deepCharcoalButton)
                            )
                        }
                    }

                    // Range Switcher
                    Picker("统计周期", selection: $weightRangeFilter) {
                        Text("近7天").tag(WeightRangeFilter.days7)
                        Text("近30天").tag(WeightRangeFilter.days30)
                        Text("近90天").tag(WeightRangeFilter.days90)
                    }
                    .pickerStyle(.segmented)

                    // Swift Charts Line Plot
                    if weightTrendSummary.dailyPoints.isEmpty {
                        VStack(spacing: 8) {
                            Text("该时间区间内暂无体重数据")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 160)
                    } else {
                        Chart {
                            ForEach(weightTrendSummary.dailyPoints) { pt in
                                LineMark(
                                    x: .value("日期", pt.date),
                                    y: .value("体重", pt.weightKg)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(FoodLogTheme.morandiProteinSage)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))

                                PointMark(
                                    x: .value("日期", pt.date),
                                    y: .value("体重", pt.weightKg)
                                )
                                .foregroundStyle(FoodLogTheme.charcoalText)
                                .symbolSize(22)
                            }

                            RuleMark(y: .value("目标", appState.profile.targetWeightKg))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .foregroundStyle(FoodLogTheme.morandiCarbTerracotta.opacity(0.8))
                                .annotation(position: .top, alignment: .leading) {
                                    Text("目标 \(String(format: "%.1f", appState.profile.targetWeightKg))kg")
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .foregroundStyle(FoodLogTheme.morandiCarbTerracotta)
                                }
                        }
                        .chartYScale(domain: weightYScaleDomain)
                        .frame(height: 190)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
                )

                // Weight History Entries List
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("体重明细列表 (\(allWeightRecords.count) 条)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(FoodLogTheme.charcoalText)
                        Spacer()
                    }

                    if allWeightRecords.isEmpty {
                        Text("暂无称重记录")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 20)
                            .frame(maxWidth: .infinity)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(allWeightRecords) { record in
                                weightRecordRow(record: record)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.white)
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        appState.openEditWeightSheet(record.snapshot)
                                    }
                            }
                        }
                    }
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }

    private var weightYScaleDomain: ClosedRange<Double> {
        let values = weightTrendSummary.dailyPoints.map(\.weightKg) + [appState.profile.targetWeightKg]
        let minV = (values.min() ?? 60.0) - 1.5
        let maxV = (values.max() ?? 70.0) + 1.5
        return minV...maxV
    }

    private func weightRecordRow(record: WeightRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.slot.title)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(FoodLogTheme.morandiProteinSage)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(FoodLogTheme.morandiProteinSage.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                    Text(DateKeyHelper.readableChineseDate(record.measuredAt))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(FoodLogTheme.charcoalText)
                }

                HStack(spacing: 6) {
                    Text(DateKeyHelper.timeString(for: record.measuredAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if !record.note.isEmpty {
                        Text(record.note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Text(String(format: "%.2f", record.weightKg))
                .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(FoodLogTheme.charcoalText)
            + Text(" kg")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func refreshExportFiles() {
        let foodCSV = DataExportService.exportFoodEntriesCSV(entries: allFoodRecords.map(\.snapshot))
        exportedFoodURL = try? DataExportService.writeTemporaryExportFile(
            data: foodCSV,
            filename: "FoodLog-FoodEntries-\(DateKeyHelper.dayKey(for: Date())).csv"
        )
        let weightCSV = DataExportService.exportWeightRecordsCSV(records: allWeightRecords.map(\.snapshot))
        exportedWeightURL = try? DataExportService.writeTemporaryExportFile(
            data: weightCSV,
            filename: "FoodLog-WeightRecords-\(DateKeyHelper.dayKey(for: Date())).csv"
        )
    }
}
