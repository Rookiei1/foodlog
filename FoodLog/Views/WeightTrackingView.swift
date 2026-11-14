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
            List {
                Section {
                    summaryHeaderCard
                }

                Section("趋势范围与代表值规则") {
                    Picker("趋势范围", selection: $rangeFilter) {
                        ForEach(WeightRangeFilter.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    if rangeFilter == .custom {
                        DatePicker("起始日期", selection: $customStartDate, displayedComponents: [.date])
                            .environment(\.locale, Locale(identifier: "zh_CN"))
                        DatePicker("结束日期", selection: $customEndDate, displayedComponents: [.date])
                            .environment(\.locale, Locale(identifier: "zh_CN"))
                    }

                    Picker("同日多次称重代表值规则", selection: $appState.profile.representativeWeightRule) {
                        ForEach(DailyRepresentativeRule.allCases) { rule in
                            Text(rule.title).tag(rule)
                        }
                    }
                    Text(appState.profile.representativeWeightRule.explanation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section("交互式体重变化曲线（Swift Charts）") {
                    interactiveChartView
                }

                if !trendSummary.weeklyAverages.isEmpty {
                    Section("周平均体重与周变化") {
                        ForEach(trendSummary.weeklyAverages.reversed()) { week in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(week.weekLabel)
                                        .font(.subheadline.weight(.semibold))
                                    Text("采样 \(week.sampleDays) 天")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let delta = week.deltaFromPreviousWeekKg {
                                    Text(String(format: "%+.2f kg", delta))
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(FoodLogTheme.weightPurple.opacity(0.14))
                                        .foregroundStyle(FoodLogTheme.weightPurple)
                                        .clipShape(Capsule())
                                }
                                Text(String(format: "%.2f kg", week.averageKg))
                                    .font(.headline.monospacedDigit())
                            }
                        }
                    }
                }

                Section("全部历史称重明细（支持同日多次、点击修改或左滑删除）") {
                    if allWeightRecords.isEmpty {
                        Text("尚无体重记录，点击右上角「＋」开始记录。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(allWeightRecords) { record in
                            let snap = record.snapshot
                            Button {
                                appState.openEditWeightSheet(snap)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text("\(snap.dayKey) \(DateKeyHelper.timeString(for: snap.measuredAt))")
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(.primary)
                                            Text(snap.slot.title)
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(FoodLogTheme.weightPurple.opacity(0.15))
                                                .foregroundStyle(FoodLogTheme.weightPurple)
                                                .clipShape(Capsule())
                                            if snap.isRepresentativeOverride {
                                                Text("指定代表值")
                                                    .font(.caption2)
                                                    .foregroundStyle(.orange)
                                            }
                                        }
                                        if !snap.note.isEmpty {
                                            Text(snap.note)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text(String(format: "%.2f kg", snap.weightKg))
                                        .font(.headline.monospacedDigit())
                                        .foregroundStyle(.primary)
                                }
                            }
                            .swipeActions(edge: .trailing) {
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
            }
            .listStyle(.insetGrouped)
            .navigationTitle("每日体重")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        appState.openNewWeightSheet()
                    } label: {
                        Label("记录体重", systemImage: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("add-weight-record-button")
                }
            }
        }
    }

    private var summaryHeaderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                metricBlock(
                    title: "今日体重",
                    value: todayRepresentativeWeight.map { String(format: "%.2f kg", $0) } ?? "未记录"
                )
                metricBlock(
                    title: "目标体重",
                    value: String(format: "%.1f kg", appState.profile.targetWeightKg)
                )
                metricBlock(
                    title: "区间变化",
                    value: trendSummary.totalChangeKg.map { String(format: "%+.2f kg", $0) } ?? "--"
                )
                metricBlock(
                    title: "每周速率",
                    value: trendSummary.weeklyRateKg.map { String(format: "%+.2f/周", $0) } ?? "--"
                )
            }
        }
        .padding(.vertical, 4)
    }

    private func metricBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .minimumScaleFactor(0.75)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var interactiveChartView: some View {
        if trendSummary.dailyPoints.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("所选日期范围内暂无体重数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if let selectedDate = selectedChartDate,
                   let nearest = nearestPoint(to: selectedDate) {
                    HStack {
                        Text("\(nearest.dayKey) 代表体重：\(String(format: "%.2f kg", nearest.weightKg))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(FoodLogTheme.weightPurple)
                        if let roll = nearest.rolling7DayAverageKg {
                            Text("（7日均线 \(String(format: "%.2f kg", roll))）")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                } else {
                    Text("按住或拖动图表可查看单日代表体重与 7 日移动均线；虚线为目标体重。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                let minW = min(trendSummary.minWeightKg ?? 50, appState.profile.targetWeightKg) - 1.2
                let maxW = max(trendSummary.maxWeightKg ?? 75, appState.profile.targetWeightKg) + 1.2

                Chart {
                    RuleMark(y: .value("目标体重", appState.profile.targetWeightKg))
                        .foregroundStyle(.orange.opacity(0.75))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 4]))

                    ForEach(trendSummary.dailyPoints) { pt in
                        AreaMark(
                            x: .value("日期", pt.date),
                            yStart: .value("基线", minW),
                            yEnd: .value("体重", pt.weightKg)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [FoodLogTheme.weightPurple.opacity(0.28), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("日期", pt.date),
                            y: .value("体重", pt.weightKg),
                            series: .value("曲线", "当日代表值")
                        )
                        .foregroundStyle(FoodLogTheme.weightPurple)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))

                        PointMark(
                            x: .value("日期", pt.date),
                            y: .value("体重", pt.weightKg)
                        )
                        .foregroundStyle(FoodLogTheme.weightPurple)

                        if let rolling = pt.rolling7DayAverageKg {
                            LineMark(
                                x: .value("日期", pt.date),
                                y: .value("7日均线", rolling),
                                series: .value("曲线", "7日均线")
                            )
                            .foregroundStyle(FoodLogTheme.calorieGreen)
                            .lineStyle(StrokeStyle(lineWidth: 1.6, dash: [3, 3]))
                        }
                    }
                }
                .chartYScale(domain: minW...maxW)
                .chartXSelection(value: $selectedChartDate)
                .frame(height: 210)
            }
            .padding(.vertical, 6)
        }
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
                Section("称重数据（单位 kg）") {
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

                    DatePicker("称重日期与时间", selection: $measuredAt, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.locale, Locale(identifier: "zh_CN"))

                    Picker("称重时段", selection: $slot) {
                        ForEach(WeightSlot.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }

                    Toggle("强制设为当日趋势代表值", isOn: $isRepresentativeOverride)
                }

                Section("备注（选填）") {
                    TextField("如：晨起排空后、训练后称重", text: $note)
                }
            }
            .navigationTitle(existingSnapshot == nil ? "记录体重" : "修改体重记录")
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
