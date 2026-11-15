import SwiftUI
import SwiftData
import Charts

public struct WeightTrackingView: View {
    @EnvironmentObject private var appState: AppStateViewModel
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \WeightRecord.measuredAt, order: .reverse)
    private var allWeightRecords: [WeightRecord]

    @State private var rangeFilter: WeightRangeFilter = .days30
    @State private var customStartDate: Date = DateKeyHelper.shiftingDays(Date(), by: -29)
    @State private var customEndDate: Date = Date()
    @State private var selectedChartDate: Date? = nil

    public init() {}

    private var activeDateBounds: (Date?, Date?) {
        let now = Date()
        switch rangeFilter {
        case .days7:
            return (DateKeyHelper.shiftingDays(now, by: -6), now)
        case .days30:
            return (DateKeyHelper.shiftingDays(now, by: -29), now)
        case .days90:
            return (DateKeyHelper.shiftingDays(now, by: -89), now)
        case .custom:
            return (min(customStartDate, customEndDate), max(customStartDate, customEndDate))
        }
    }

    private var trendSummary: WeightTrendSummary {
        let (start, end) = activeDateBounds
        return NutritionAndWeightEngine.buildWeightTrend(
            records: allWeightRecords.map(\.snapshot),
            rule: appState.profile.representativeWeightRule,
            startDate: start,
            endDate: end
        )
    }

    private var todayRepresentativeWeight: Double? {
        let todayKey = DateKeyHelper.dayKey(for: Date())
        let todaySnapshots = allWeightRecords.filter { $0.dayKey == todayKey }.map(\.snapshot)
        return NutritionAndWeightEngine.selectDailyRepresentativeWeight(
            from: todaySnapshots,
            rule: appState.profile.representativeWeightRule
        )
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroWeightChartCard
                    if !trendSummary.weeklyAverages.isEmpty {
                        weeklyAveragesCard
                    }
                    weightHistoryCard
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("每日体重")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        appState.openNewWeightSheet()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("add-weight-record-button")
                }
            }
        }
    }

    // MARK: - 1. Hero Weight & Chart Card

    private var heroWeightChartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日代表体重")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(todayRepresentativeWeight.map { String(format: "%.2f", $0) } ?? (trendSummary.latestWeightKg.map { String(format: "%.2f", $0) } ?? "--"))
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        Text("kg")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        if let rate = trendSummary.weeklyRateKg {
                            Text(String(format: "%+.2f kg/周", rate))
                                .font(.caption.weight(.bold).monospacedDigit())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(FoodLogTheme.weightPurple.opacity(0.15))
                                .foregroundStyle(FoodLogTheme.weightPurple)
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer()

                Button {
                    appState.openNewWeightSheet()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                        Text("记体重")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(FoodLogTheme.weightPurple.gradient)
                    )
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                statMiniTile(
                    title: "目标体重",
                    value: String(format: "%.1f kg", appState.profile.targetWeightKg)
                )
                statMiniTile(
                    title: "区间变化",
                    value: trendSummary.totalChangeKg.map { String(format: "%+.2f kg", $0) } ?? "--"
                )
                Menu {
                    Picker("同日多次代表值规则", selection: $appState.profile.representativeWeightRule) {
                        ForEach(DailyRepresentativeRule.allCases) { rule in
                            Text(rule.title).tag(rule)
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 3) {
                            Text("代表值规则")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        Text(shortRuleName(appState.profile.representativeWeightRule))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(FoodLogTheme.weightPurple)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.tertiarySystemGroupedBackground))
                    )
                }
                .buttonStyle(.plain)
            }

            Picker("趋势范围", selection: $rangeFilter) {
                ForEach(WeightRangeFilter.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if rangeFilter == .custom {
                HStack {
                    DatePicker("从", selection: $customStartDate, displayedComponents: [.date])
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                        .font(.caption)
                    Spacer()
                    DatePicker("至", selection: $customEndDate, displayedComponents: [.date])
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                        .font(.caption)
                }
            }

            interactiveChartView
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func statMiniTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }

    private func shortRuleName(_ rule: DailyRepresentativeRule) -> String {
        switch rule {
        case .morningFastingFirst: return "晨起空腹"
        case .lowestOfDay: return "当日最低"
        case .latestOfDay: return "当日最新"
        case .averageOfDay: return "当日均值"
        }
    }

    @ViewBuilder
    private var interactiveChartView: some View {
        if trendSummary.dailyPoints.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("暂无趋势数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let selectedDate = selectedChartDate,
                   let nearest = nearestPoint(to: selectedDate) {
                    HStack(spacing: 8) {
                        Text(nearest.dayKey)
                            .font(.caption.weight(.bold))
                        Text(String(format: "%.2f kg", nearest.weightKg))
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(FoodLogTheme.weightPurple)
                        if let roll = nearest.rolling7DayAverageKg {
                            Text("7日均 \(String(format: "%.2f", roll))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(FoodLogTheme.calorieGreen)
                        }
                        Spacer()
                    }
                } else {
                    HStack(spacing: 14) {
                        HStack(spacing: 4) {
                            Circle().fill(FoodLogTheme.weightPurple).frame(width: 6, height: 6)
                            Text("每日体重").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Circle().fill(FoodLogTheme.calorieGreen).frame(width: 6, height: 6)
                            Text("7日均线").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Circle().fill(.orange).frame(width: 6, height: 6)
                            Text("目标线").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                let minW = min(trendSummary.minWeightKg ?? 55, appState.profile.targetWeightKg) - 0.8
                let maxW = max(trendSummary.maxWeightKg ?? 70, appState.profile.targetWeightKg) + 0.8

                Chart {
                    RuleMark(y: .value("目标", appState.profile.targetWeightKg))
                        .foregroundStyle(.orange.opacity(0.65))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 4]))

                    ForEach(trendSummary.dailyPoints) { pt in
                        AreaMark(
                            x: .value("日期", pt.date),
                            yStart: .value("底", minW),
                            yEnd: .value("体重", pt.weightKg)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [FoodLogTheme.weightPurple.opacity(0.25), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("日期", pt.date),
                            y: .value("体重", pt.weightKg),
                            series: .value("类型", "每日")
                        )
                        .foregroundStyle(FoodLogTheme.weightPurple)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("日期", pt.date),
                            y: .value("体重", pt.weightKg)
                        )
                        .foregroundStyle(FoodLogTheme.weightPurple)

                        if let rolling = pt.rolling7DayAverageKg {
                            LineMark(
                                x: .value("日期", pt.date),
                                y: .value("均线", rolling),
                                series: .value("类型", "均线")
                            )
                            .foregroundStyle(FoodLogTheme.calorieGreen)
                            .lineStyle(StrokeStyle(lineWidth: 1.6, dash: [4, 3]))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                }
                .chartYScale(domain: minW...maxW)
                .chartXSelection(value: $selectedChartDate)
                .frame(height: 195)
            }
        }
    }

    // MARK: - 2. Weekly Averages Card

    private var weeklyAveragesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("周均体重")
                .font(.headline)

            ForEach(Array(trendSummary.weeklyAverages.reversed().prefix(4))) { week in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(week.weekLabel)
                            .font(.subheadline.weight(.semibold))
                        Text("记录 \(week.sampleDays) 天")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let delta = week.deltaFromPreviousWeekKg {
                        Text(String(format: "%+.2f kg", delta))
                            .font(.caption.weight(.bold).monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(FoodLogTheme.weightPurple.opacity(0.14))
                            .foregroundStyle(FoodLogTheme.weightPurple)
                            .clipShape(Capsule())
                    }
                    Text(String(format: "%.2f kg", week.averageKg))
                        .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - 3. Weight History Card

    private var weightHistoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("近期称重明细")
                    .font(.headline)
                Spacer()
                Text("共 \(allWeightRecords.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if allWeightRecords.isEmpty {
                Text("尚无称重记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(allWeightRecords.prefix(14)) { record in
                    let snap = record.snapshot
                    Button {
                        appState.openEditWeightSheet(snap)
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(FoodLogTheme.weightPurple.opacity(0.14))
                                .frame(width: 34, height: 34)
                                .overlay(
                                    Image(systemName: "scalemass")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(FoodLogTheme.weightPurple)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(DateKeyHelper.shortDateString(for: snap.measuredAt))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(snap.slot.title)
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(FoodLogTheme.weightPurple.opacity(0.12))
                                        .foregroundStyle(FoodLogTheme.weightPurple)
                                        .clipShape(Capsule())
                                }
                                Text(snap.note.isEmpty ? DateKeyHelper.timeString(for: snap.measuredAt) : "\(DateKeyHelper.timeString(for: snap.measuredAt)) · \(snap.note)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(String(format: "%.2f kg", snap.weightKg))
                                .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            modelContext.delete(record)
                            try? modelContext.save()
                        } label: {
                            Label("删除", systemImage: "trash")
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

    private func nearestPoint(to date: Date) -> DailyWeightPoint? {
        trendSummary.dailyPoints.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }
}

public struct WeightEntryEditorSheet: View {
    @EnvironmentObject private var appState: AppStateViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allWeightRecords: [WeightRecord]

    public let existingSnapshot: WeightRecordSnapshot?
    public let defaultDate: Date

    @State private var measuredAt: Date = Date()
    @State private var weightKg: Double = 62.0
    @State private var slot: WeightSlot = .morningFasting
    @State private var isRepresentativeOverride: Bool = false
    @State private var note: String = ""

    public init(existingSnapshot: WeightRecordSnapshot?, defaultDate: Date) {
        self.existingSnapshot = existingSnapshot
        self.defaultDate = defaultDate
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("称重数据") {
                    HStack {
                        Text("体重 (kg)")
                        Spacer()
                        TextField("体重", value: $weightKg, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.headline.monospacedDigit())
                            .frame(width: 110)
                            .accessibilityIdentifier("weight-editor-kg-field")
                    }

                    DatePicker("时间", selection: $measuredAt, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.locale, Locale(identifier: "zh_CN"))

                    Picker("时段", selection: $slot) {
                        ForEach(WeightSlot.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }

                    Toggle("设为当日代表值", isOn: $isRepresentativeOverride)
                }

                Section("备注") {
                    TextField("选填（如：晨起空腹）", text: $note)
                }
            }
            .navigationTitle(existingSnapshot == nil ? "记体重" : "修改体重")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveWeight()
                    }
                    .accessibilityIdentifier("weight-editor-save-button")
                }
            }
            .onAppear {
                if let snap = existingSnapshot {
                    measuredAt = snap.measuredAt
                    weightKg = snap.weightKg
                    slot = snap.slot
                    isRepresentativeOverride = snap.isRepresentativeOverride
                    note = snap.note
                } else {
                    measuredAt = DateKeyHelper.combining(day: defaultDate, withTimeFrom: Date())
                    weightKg = appState.profile.currentWeightKg
                }
            }
        }
    }

    private func saveWeight() {
        let snapshot = WeightRecordSnapshot(
            id: existingSnapshot?.id ?? UUID(),
            measuredAt: measuredAt,
            dayKey: DateKeyHelper.dayKey(for: measuredAt),
            weightKg: weightKg,
            slot: slot,
            isRepresentativeOverride: isRepresentativeOverride,
            note: note
        )
        if let existingID = existingSnapshot?.id,
           let target = allWeightRecords.first(where: { $0.id == existingID }) {
            target.update(from: snapshot)
        } else {
            modelContext.insert(WeightRecord(snapshot: snapshot))
        }
        appState.profile.currentWeightKg = snapshot.weightKg
        try? modelContext.save()
        dismiss()
    }
}
