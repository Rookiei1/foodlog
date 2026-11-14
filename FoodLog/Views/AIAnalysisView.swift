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
    @State private var hasConfirmedDigestSend: Bool = false

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
            List {
                Section("1. 选择统计范围与分析模型") {
                    Picker("分析范围", selection: $selectedSpan) {
                        ForEach(AnalysisTimeSpan.allCases) { span in
                            Text(span.title).tag(span)
                        }
                    }

                    Picker("AI 分析模型", selection: $selectedProviderID) {
                        ForEach(appState.providers) { provider in
                            Text("\(provider.name) · \(provider.modelName)").tag(provider.id)
                        }
                    }
                }

                Section("2. 真实数据库客观摘要预览（确认后发送给 AI）") {
                    Text(objectiveDigest.promptReadyText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)

                    Toggle("我已核对以上客观统计摘要，确认发送给所选 AI 模型生成综合分析", isOn: $hasConfirmedDigestSend)
                        .font(.caption.weight(.medium))
                        .accessibilityIdentifier("confirm-send-digest-toggle")

                    if isGenerating {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("正在生成中文饮食与体重综合报告…")
                                .font(.subheadline)
                            Spacer()
                            Button("取消", role: .cancel) {
                                analysisTask?.cancel()
                                isGenerating = false
                            }
                            .buttonStyle(.bordered)
                        }
                    } else {
                        Button {
                            runComprehensiveAnalysis()
                        } label: {
                            HStack {
                                Spacer()
                                Label("分析我的饮食与体重", systemImage: "wand.and.stars")
                                    .font(.headline)
                                Spacer()
                            }
                        }
                        .disabled(!hasConfirmedDigestSend)
                        .accessibilityIdentifier("run-comprehensive-analysis-button")
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if let report = currentReport {
                    activeReportSections(report: report)
                }

                if !savedReportRecords.isEmpty {
                    Section("已保存的历史分析报告") {
                        ForEach(savedReportRecords) { record in
                            if let decoded = record.decodedReport {
                                Button {
                                    currentReport = decoded
                                    preparePDFExport(for: decoded)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("\(decoded.spanTitle) · \(decoded.dateRangeText)")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            Text("模型：\(decoded.providerName) (\(decoded.modelName))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "doc.richtext")
                                            .foregroundStyle(FoodLogTheme.calorieGreen)
                                    }
                                }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                modelContext.delete(savedReportRecords[index])
                            }
                            try? modelContext.save()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("AI 综合分析")
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

    @ViewBuilder
    private func activeReportSections(report: AIComprehensiveReport) -> some View {
        Section("分析报告操作") {
            HStack(spacing: 12) {
                Button {
                    saveReportToDatabase(report)
                } label: {
                    Label("保存报告到本机", systemImage: "tray.and.arrow.down.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)

                if let pdfURL = exportedPDFURL {
                    ShareLink(item: pdfURL) {
                        Label("导出 PDF 报告", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
            }
        }

        Section("一、【客观统计】数据库真实汇总") {
            Text(report.objectiveSummarySection)
                .font(.footnote.monospacedDigit())
        }

        Section("二、【估算边界与短期体重波动说明】") {
            Text(report.estimationAndFluctuationDisclaimer)
                .font(.footnote)
                .foregroundStyle(.orange)
        }

        Section("三、【关联分析】热量、蛋白质与体重趋势") {
            Text(report.calorieAndWeightAnalysis)
                .font(.footnote)
            Divider()
            Text(report.surplusEvaluation)
                .font(.footnote.weight(.medium))
        }

        Section("四、【摄入不足日期与饮食结构问题】") {
            Text(report.underEatingDaysReview)
                .font(.footnote)
            ForEach(Array(report.dietStructureIssues.enumerated()), id: \.offset) { idx, issue in
                Label("\(idx + 1). \(issue)", systemImage: "exclamationmark.circle")
                    .font(.footnote)
            }
        }

        Section("五、【AI 建议】下一周饮食与增重调整方案") {
            ForEach(Array(report.nextWeekActionSuggestions.enumerated()), id: \.offset) { idx, suggestion in
                Label("\(idx + 1). \(suggestion)", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.primary)
            }
            Divider()
            Text(report.weightGoalAdjustmentAdvice)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(FoodLogTheme.calorieGreen)
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
        appState.showTemporaryBanner("分析报告已保存到本机")
    }

    private func preparePDFExport(for report: AIComprehensiveReport) {
        let pdfData = DataExportService.renderAnalysisReportPDF(report: report)
        let fname = "FoodLog-Report-\(DateKeyHelper.dayKey(for: report.createdAt)).pdf"
        exportedPDFURL = try? DataExportService.writeTemporaryExportFile(data: pdfData, filename: fname)
    }
}
