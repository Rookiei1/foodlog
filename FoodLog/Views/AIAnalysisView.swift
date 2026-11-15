import SwiftUI
import SwiftData

public struct AIAnalysisView: View {
    @EnvironmentObject private var appState: AppStateViewModel
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \FoodEntryRecord.eatenAt, order: .forward)
    private var allFoodRecords: [FoodEntryRecord]

    @Query(sort: \WeightRecord.measuredAt, order: .forward)
    private var allWeightRecords: [WeightRecord]

    @Query(sort: \SavedAnalysisReportRecord.createdAt, order: .reverse)
    private var savedReportRecords: [SavedAnalysisReportRecord]

    @State private var selectedSpan: AnalysisTimeSpan = .days7
    @State private var selectedProviderID: UUID = UUID()
    @State private var hasConfirmedDigestSend: Bool = true

    @State private var isGenerating: Bool = false
    @State private var analysisTask: Task<Void, Never>? = nil
    @State private var errorMessage: String? = nil
    @State private var currentReport: AIComprehensiveReport? = nil
    @State private var exportedPDFURL: URL? = nil

    public init() {}

    private var currentProvider: AIProviderConfig {
        appState.providers.first(where: { $0.id == selectedProviderID })
            ?? appState.defaultAnalysisProvider
    }

    private var objectiveDigest: ObjectiveDatasetDigest {
        NutritionAndWeightEngine.buildObjectiveDigest(
            span: selectedSpan,
            foodEntries: allFoodRecords.map(\.snapshot),
            weightRecords: allWeightRecords.map(\.snapshot),
            profile: appState.profile
        )
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    controlAndDigestCard

                    if let report = currentReport {
                        visualReportCards(report: report)
                    }

                    if !savedReportRecords.isEmpty {
                        savedReportsSection
                    }
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("AI 综合分析")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                selectedProviderID = appState.defaultAnalysisProvider.id
                if currentReport == nil, let latest = savedReportRecords.first?.decodedReport {
                    currentReport = latest
                    preparePDFExport(for: latest)
                }
            }
            .onDisappear {
                analysisTask?.cancel()
            }
        }
    }

    // MARK: - 1. Control & Visual Digest Card

    private var controlAndDigestCard: some View {
        let digest = objectiveDigest

        return VStack(alignment: .leading, spacing: 14) {
            Picker("统计范围", selection: $selectedSpan) {
                ForEach(AnalysisTimeSpan.allCases) { span in
                    Text(span.title).tag(span)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Image(systemName: "cpu")
                    .font(.subheadline)
                    .foregroundStyle(FoodLogTheme.calorieGreen)
                Text("分析模型")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("AI 分析模型", selection: $selectedProviderID) {
                    ForEach(appState.providers) { provider in
                        Text("\(provider.name) · \(provider.modelName)").tag(provider.id)
                    }
                }
                .labelsHidden()
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                digestMetricTile(
                    icon: "flame.fill",
                    tint: FoodLogTheme.calorieGreen,
                    title: "日均摄入热量",
                    value: "\(Int(digest.averageDailyCalories.rounded())) kcal",
                    sub: "目标 \(Int(digest.targetCalories.rounded())) kcal"
                )
                digestMetricTile(
                    icon: "bolt.heart.fill",
                    tint: FoodLogTheme.proteinBlue,
                    title: "日均蛋白质",
                    value: "\(Int(digest.averageDailyProteinGrams.rounded())) g",
                    sub: "目标 \(Int(digest.targetProteinGrams.rounded())) g"
                )
                digestMetricTile(
                    icon: "scalemass.fill",
                    tint: FoodLogTheme.weightPurple,
                    title: "周期体重变化",
                    value: digest.weightChangeKg.map { String(format: "%+.2f kg", $0) } ?? "--",
                    sub: digest.weeklyWeightRateKg.map { String(format: "%+.2f kg/周", $0) } ?? "称重 \(digest.loggedWeightDays) 天"
                )
                digestMetricTile(
                    icon: "calendar.badge.checkmark",
                    tint: FoodLogTheme.fatAmber,
                    title: "饮食记录天数",
                    value: "\(digest.loggedFoodDays) / \(digest.totalCalendarDays) 天",
                    sub: digest.underEatingDayKeys.isEmpty ? "无摄入不足日" : "摄入不足 \(digest.underEatingDayKeys.count) 天"
                )
            }

            Toggle("确认发送以上真实统计摘要至所选 AI", isOn: $hasConfirmedDigestSend)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("confirm-send-digest-toggle")

            if isGenerating {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在生成诊断报告…")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button("取消", role: .cancel) {
                        analysisTask?.cancel()
                        isGenerating = false
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
            } else {
                Button {
                    runComprehensiveAnalysis()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                        Text("分析我的饮食与体重")
                            .fontWeight(.bold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(FoodLogTheme.calorieGreen.gradient)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!hasConfirmedDigestSend)
                .opacity(hasConfirmedDigestSend ? 1.0 : 0.5)
                .accessibilityIdentifier("run-comprehensive-analysis-button")
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func digestMetricTile(icon: String, tint: Color, title: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
            Text(sub)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }

    // MARK: - 2. Visual Report Cards

    @ViewBuilder
    private func visualReportCards(report: AIComprehensiveReport) -> some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(report.spanTitle)诊断报告")
                        .font(.headline)
                    Text("\(report.dateRangeText) · \(report.modelName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    saveReportToDatabase(report)
                } label: {
                    Label("保存", systemImage: "tray.and.arrow.down.fill")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.bordered)

                if let pdfURL = exportedPDFURL {
                    ShareLink(item: pdfURL) {
                        Label("PDF", systemImage: "square.and.arrow.up")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 4)

            // Card A: Surplus & Weight Relationship
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                        .font(.title3)
                        .foregroundStyle(FoodLogTheme.calorieGreen)
                    Text("热量盈余与体重关联")
                        .font(.subheadline.weight(.bold))
                }
                Text(report.surplusEvaluation)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FoodLogTheme.calorieGreen)
                Text(report.calorieAndWeightAnalysis)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )

            // Card B: Next Week Action Plan
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3)
                        .foregroundStyle(FoodLogTheme.proteinBlue)
                    Text("下周行动清单")
                        .font(.subheadline.weight(.bold))
                }

                ForEach(Array(report.nextWeekActionSuggestions.enumerated()), id: \.offset) { idx, suggestion in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(idx + 1)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(FoodLogTheme.proteinBlue))
                        Text(suggestion)
                            .font(.footnote.weight(.medium))
                    }
                }

                Divider()

                HStack(spacing: 6) {
                    Image(systemName: "target")
                        .font(.caption)
                        .foregroundStyle(FoodLogTheme.calorieGreen)
                    Text(report.weightGoalAdjustmentAdvice)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FoodLogTheme.calorieGreen)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )

            // Card C: Diet Structure & Under-eating Days
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(FoodLogTheme.fatAmber)
                    Text("结构短板与摄入不足日")
                        .font(.subheadline.weight(.bold))
                }

                Text(report.underEatingDaysReview)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(Array(report.dietStructureIssues.enumerated()), id: \.offset) { _, issue in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(FoodLogTheme.fatAmber)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        Text(issue)
                            .font(.footnote)
                    }
                }

                Divider()

                Text(report.estimationAndFluctuationDisclaimer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    // MARK: - 3. Saved Reports

    private var savedReportsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("已保存报告")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            ForEach(savedReportRecords.prefix(5)) { record in
                if let decoded = record.decodedReport {
                    Button {
                        currentReport = decoded
                        preparePDFExport(for: decoded)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(decoded.spanTitle) · \(decoded.dateRangeText)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(decoded.modelName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
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

    private func runComprehensiveAnalysis() {
        errorMessage = nil
        isGenerating = true
        let digest = objectiveDigest
        let profile = appState.profile
        let provider = currentProvider
        let keychain = appState.keychain

        analysisTask = Task {
            do {
                let report = try await AIProviderRouter.analyzeHistoryWithValidation(
                    digest: digest,
                    profile: profile,
                    config: provider,
                    keychain: keychain
                )
                if !Task.isCancelled {
                    currentReport = report
                    preparePDFExport(for: report)
                    isGenerating = false
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }

    private func saveReportToDatabase(_ report: AIComprehensiveReport) {
        if !savedReportRecords.contains(where: { $0.id == report.id }) {
            modelContext.insert(SavedAnalysisReportRecord(report: report))
            try? modelContext.save()
        }
        appState.showTemporaryBanner("报告已保存")
    }

    private func preparePDFExport(for report: AIComprehensiveReport) {
        let pdfData = DataExportService.renderAnalysisReportPDF(report: report)
        let fname = "FoodLog-Report-\(DateKeyHelper.dayKey(for: report.createdAt)).pdf"
        exportedPDFURL = try? DataExportService.writeTemporaryExportFile(data: pdfData, filename: fname)
    }
}
