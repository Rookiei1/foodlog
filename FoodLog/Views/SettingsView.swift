import SwiftUI
import SwiftData
import UniformTypeIdentifiers

public struct SettingsView: View {
    @EnvironmentObject private var appState: AppStateViewModel
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \FoodEntryRecord.eatenAt, order: .forward)
    private var allFoodRecords: [FoodEntryRecord]

    @Query(sort: \FavoriteFoodTemplate.useCount, order: .reverse)
    private var favoriteTemplates: [FavoriteFoodTemplate]

    @Query(sort: \WeightRecord.measuredAt, order: .forward)
    private var allWeightRecords: [WeightRecord]

    @Query(sort: \SavedAnalysisReportRecord.createdAt, order: .reverse)
    private var savedReportRecords: [SavedAnalysisReportRecord]

    @State private var editingProvider: AIProviderConfig? = nil
    @State private var isAddingNewProvider: Bool = false

    @State private var includePhotosInBackup: Bool = false
    @State private var exportedFoodCSVURL: URL? = nil
    @State private var exportedWeightCSVURL: URL? = nil
    @State private var exportedBackupJSONURL: URL? = nil
    @State private var exportedLatestPDFURL: URL? = nil
    @State private var isImportingBackup: Bool = false
    @State private var backupStatusMessage: String? = nil

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                aiProvidersSection
                defaultModelsSection
                profileAndGoalsSection
                exportAndBackupSection
                aboutSection
            }
            .navigationTitle("设置与数据管理")
            .sheet(item: $editingProvider) { provider in
                AIProviderEditorSheet(provider: provider, isNew: false)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $isAddingNewProvider) {
                AIProviderEditorSheet(
                    provider: AIProviderConfig(
                        name: "自定义 OpenAI 兼容服务",
                        kind: .openAICompatible,
                        baseURL: "https://api.openai.com/v1",
                        modelName: "gpt-4o-mini"
                    ),
                    isNew: true
                )
                .environmentObject(appState)
            }
            .fileImporter(
                isPresented: $isImportingBackup,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleBackupFileImport(result)
            }
            .onAppear {
                refreshExportFiles()
            }
        }
    }

    private var aiProvidersSection: some View {
        Section {
            ForEach(appState.providers) { provider in
                Button {
                    editingProvider = provider
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(provider.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(provider.kind.displayName)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15))
                                    .foregroundStyle(.secondary)
                                    .clipShape(Capsule())
                            }
                            Text("模型：\(provider.modelName)  |  \(provider.supportsVision ? "支持视觉" : "仅文本")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if appState.hasAPIKey(for: provider) {
                            Label(provider.kind.requiresAPIKey ? "Keychain 已存" : "免密钥", systemImage: "key.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(FoodLogTheme.calorieGreen)
                        } else {
                            Text("未填 Key")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    if appState.providers.count > 1 {
                        Button(role: .destructive) {
                            appState.deleteProvider(provider)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }

            Button {
                isAddingNewProvider = true
            } label: {
                Label("添加 AI 供应商（OpenAI / DeepSeek / Gemini / 自定义）", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("多供应商 AI API 管理（API Key 仅保存在 iOS Keychain）")
        }
    }

    private var defaultModelsSection: some View {
        Section("默认调用模型分配") {
            Picker("默认拍照识别模型", selection: $appState.defaultVisionProviderID) {
                ForEach(appState.providers) { provider in
                    Text("\(provider.name) (\(provider.modelName))").tag(provider.id)
                }
            }

            Picker("默认综合分析模型", selection: $appState.defaultAnalysisProviderID) {
                ForEach(appState.providers) { provider in
                    Text("\(provider.name) (\(provider.modelName))").tag(provider.id)
                }
            }
        }
    }

    private var profileAndGoalsSection: some View {
        Section("个人身体参数与每日营养目标") {
            Picker("性别", selection: $appState.profile.sex) {
                ForEach(BiologicalSex.allCases) { sex in
                    Text(sex.title).tag(sex)
                }
            }

            HStack {
                Text("年龄")
                Spacer()
                TextField("年龄", value: $appState.profile.age, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }

            HStack {
                Text("身高 (cm)")
                Spacer()
                TextField("身高", value: $appState.profile.heightCm, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
            }

            HStack {
                Text("当前体重 (kg)")
                Spacer()
                TextField("当前体重", value: $appState.profile.currentWeightKg, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
            }

            HStack {
                Text("目标体重 (kg)")
                Spacer()
                TextField("目标体重", value: $appState.profile.targetWeightKg, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
            }

            Picker("日常活动水平", selection: $appState.profile.activityLevel) {
                ForEach(ActivityLevel.allCases) { level in
                    Text(level.title).tag(level)
                }
            }

            Picker("阶段目标", selection: $appState.profile.goalMode) {
                ForEach(GoalMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            let recommended = appState.profile.computeRecommendedTargets()
            VStack(alignment: .leading, spacing: 6) {
                Text("系统科学建议值：TDEE 约 \(Int(recommended.tdee)) kcal → 建议目标 \(Int(recommended.targetCalories)) kcal/天，蛋白质 \(Int(recommended.targetProteinGrams))g，脂肪 \(Int(recommended.targetFatGrams))g，碳水 \(Int(recommended.targetCarbGrams))g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("一键应用系统建议目标") {
                    appState.profile.applyRecommendedTargets()
                    appState.showTemporaryBanner("已应用推荐热量与蛋白质目标")
                }
                .font(.caption.weight(.semibold))
            }

            HStack {
                Text("每日目标热量 (kcal)")
                Spacer()
                TextField("目标热量", value: $appState.profile.targetCalories, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 95)
            }

            HStack {
                Text("每日目标蛋白质 (g)")
                Spacer()
                TextField("目标蛋白质", value: $appState.profile.targetProteinGrams, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 95)
            }

            HStack {
                Text("每日目标脂肪 (g)")
                Spacer()
                TextField("目标脂肪", value: $appState.profile.targetFatGrams, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 95)
            }

            HStack {
                Text("每日目标碳水化合物 (g)")
                Spacer()
                TextField("目标碳水", value: $appState.profile.targetCarbGrams, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 95)
            }
        }
    }

    private var exportAndBackupSection: some View {
        Section("数据导出与 JSON 备份恢复（绝不导出 API Key）") {
            Button {
                refreshExportFiles()
                appState.showTemporaryBanner("已刷新最新导出文件")
            } label: {
                Label("重新生成最新导出数据包", systemImage: "arrow.clockwise.circle")
            }

            if let foodURL = exportedFoodCSVURL {
                ShareLink(item: foodURL) {
                    Label("导出 CSV 饮食记录（\(allFoodRecords.count) 条）", systemImage: "tablecells")
                }
            }

            if let weightURL = exportedWeightCSVURL {
                ShareLink(item: weightURL) {
                    Label("导出 CSV 体重记录（\(allWeightRecords.count) 条）", systemImage: "scalemass")
                }
            }

            Toggle("JSON 完整备份中附带餐食照片数据包（独立完整备份选项）", isOn: $includePhotosInBackup)
                .font(.caption)
                .onChange(of: includePhotosInBackup) { _, _ in
                    refreshExportFiles()
                }

            if let jsonURL = exportedBackupJSONURL {
                ShareLink(item: jsonURL) {
                    Label(
                        includePhotosInBackup ? "导出 JSON 完整备份（含照片包）" : "导出 JSON 完整结构化数据（轻量默认）",
                        systemImage: "externaldrive.badge.checkmark"
                    )
                }
            }

            if let pdfURL = exportedLatestPDFURL {
                ShareLink(item: pdfURL) {
                    Label("导出最新 AI 分析报告 PDF", systemImage: "doc.richtext")
                }
            }

            Button {
                isImportingBackup = true
            } label: {
                Label("从 JSON 备份文件恢复数据", systemImage: "arrow.down.doc.fill")
            }

            if let backupStatusMessage {
                Text(backupStatusMessage)
                    .font(.caption)
                    .foregroundStyle(FoodLogTheme.calorieGreen)
            }
        }
    }

    private var aboutSection: some View {
        Section("关于食刻 FoodLog") {
            HStack {
                Text("版本")
                Spacer()
                Text("1.0.0 (Local-first Architecture)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("所有饮食、体重、常吃收藏及个人设置默认保存在本机 SwiftData 数据库；API 密钥仅加密保存在 iOS Keychain。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("local-storage-footer")
        }
    }

    private func refreshExportFiles() {
        let foods = allFoodRecords.map(\.snapshot)
        let weights = allWeightRecords.map(\.snapshot)
        let favs = favoriteTemplates.map(\.snapshot)
        let reports = savedReportRecords.compactMap(\.decodedReport)

        let foodCSV = DataExportService.exportFoodEntriesCSV(entries: foods)
        exportedFoodCSVURL = try? DataExportService.writeTemporaryExportFile(
            data: foodCSV,
            filename: "FoodLog-Diet-\(appState.selectedDayKey).csv"
        )

        let weightCSV = DataExportService.exportWeightRecordsCSV(records: weights)
        exportedWeightCSVURL = try? DataExportService.writeTemporaryExportFile(
            data: weightCSV,
            filename: "FoodLog-Weight-\(appState.selectedDayKey).csv"
        )

        if let jsonData = try? DataExportService.exportFullBackupJSON(
            profile: appState.profile,
            foodEntries: foods,
            favoriteFoods: favs,
            weightRecords: weights,
            savedReports: reports,
            includePhotos: includePhotosInBackup
        ) {
            exportedBackupJSONURL = try? DataExportService.writeTemporaryExportFile(
                data: jsonData,
                filename: "FoodLog-Backup-\(appState.selectedDayKey).json"
            )
        }

        let sampleOrLatestReport = reports.first ?? AIComprehensiveReport(
            spanTitle: "最近 7 天",
            dateRangeText: appState.selectedDayKey,
            providerName: appState.defaultAnalysisProvider.name,
            modelName: appState.defaultAnalysisProvider.modelName,
            objectiveSummarySection: NutritionAndWeightEngine.buildObjectiveDigest(
                span: .days7,
                foodEntries: foods,
                weightRecords: weights,
                profile: appState.profile
            ).promptReadyText,
            estimationAndFluctuationDisclaimer: "本报告区分数据库客观统计与视觉估算；短期体重波动主要受水分和糖原影响。",
            calorieAndWeightAnalysis: "请前往「AI 分析」标签页生成最新周期完整报告。",
            surplusEvaluation: "按当前目标持续追踪。",
            underEatingDaysReview: "保持规律记录三餐与加餐。",
            dietStructureIssues: ["坚持记录可获得更精准的趋势洞察"],
            nextWeekActionSuggestions: ["每日晨起空腹称重，使用拍照或常吃收藏快速记录饮食"],
            weightGoalAdjustmentAdvice: "每 2 周根据周平均体重斜率微调每日热量目标。"
        )
        let pdfData = DataExportService.renderAnalysisReportPDF(report: sampleOrLatestReport)
        exportedLatestPDFURL = try? DataExportService.writeTemporaryExportFile(
            data: pdfData,
            filename: "FoodLog-Analysis-Report.pdf"
        )
    }

    private func handleBackupFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try Data(contentsOf: url)
                let (summary, restoredProfile) = try DataExportService.restoreBackup(from: data, into: modelContext)
                appState.profile = restoredProfile
                backupStatusMessage = "恢复成功：新增饮食 \(summary.importedFoodsCount) 条、收藏 \(summary.importedFavoritesCount) 条、体重 \(summary.importedWeightsCount) 条、报告 \(summary.importedReportsCount) 份。"
                refreshExportFiles()
            } catch {
                backupStatusMessage = "恢复失败：\(error.localizedDescription)"
            }
        case .failure(let error):
            backupStatusMessage = "读取文件失败：\(error.localizedDescription)"
        }
    }
}

public struct AIProviderEditorSheet: View {
    @EnvironmentObject private var appState: AppStateViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft: AIProviderConfig
    @State private var apiKeyInput: String = ""
    @State private var customModelInput: String = ""
    @State private var isTestingConnection: Bool = false
    @State private var testStatusMessage: String? = nil
    @State private var testSucceeded: Bool = false
    public let isNew: Bool

    public init(provider: AIProviderConfig, isNew: Bool) {
        _draft = State(initialValue: provider)
        self.isNew = isNew
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("供应商类型与地址") {
                    TextField("供应商名称", text: $draft.name)

                    Picker("接口类型", selection: $draft.kind) {
                        ForEach(AIProviderKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .onChange(of: draft.kind) { _, newKind in
                        draft.baseURL = newKind.defaultBaseURL
                        if let firstModel = newKind.presetModels.first {
                            draft.modelName = firstModel
                        }
                    }

                    TextField("Base URL", text: $draft.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                if draft.kind.requiresAPIKey {
                    Section("API Key（安全存储于 iOS Keychain，绝不上传 GitHub 或写入日志）") {
                        SecureField("输入或更新 API Key（sk-... / AIza...）", text: $apiKeyInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }

                Section("模型选择与手动输入") {
                    Picker("预设模型快速选择", selection: $draft.modelName) {
                        ForEach(draft.allSelectableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }

                    HStack {
                        TextField("或手动输入模型名（如 deepseek-vl2 / gpt-4.1）", text: $customModelInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("使用") {
                            let trimmed = customModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            if !draft.customModels.contains(trimmed) {
                                draft.customModels.append(trimmed)
                            }
                            draft.modelName = trimmed
                            customModelInput = ""
                        }
                        .disabled(customModelInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    HStack {
                        Text("当前选定模型")
                        Spacer()
                        Text(draft.modelName)
                            .font(.subheadline.weight(.semibold).monospaced())
                    }

                    Picker("视觉能力（图片输入）", selection: $draft.supportsVisionOverride) {
                        Text("自动根据模型名识别（当前：\(AIVisionCapabilityChecker.supportsVision(kind: draft.kind, modelName: draft.modelName) ? "支持" : "不支持")）")
                            .tag(Optional<Bool>.none)
                        Text("强制标记为支持视觉").tag(Optional<Bool>.some(true))
                        Text("强制标记为仅文本").tag(Optional<Bool>.some(false))
                    }
                }

                Section("连接测试") {
                    Button {
                        runConnectionTest()
                    } label: {
                        HStack {
                            if isTestingConnection {
                                ProgressView()
                                    .padding(.trailing, 6)
                            }
                            Label("测试连接", systemImage: "bolt.horizontal.circle.fill")
                        }
                    }
                    .disabled(isTestingConnection)

                    if let testStatusMessage {
                        Text(testStatusMessage)
                            .font(.caption)
                            .foregroundStyle(testSucceeded ? FoodLogTheme.calorieGreen : .red)
                    }
                }
            }
            .navigationTitle(isNew ? "添加 AI 供应商" : "编辑 AI 供应商")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        try? appState.upsertProvider(draft, apiKey: draft.kind.requiresAPIKey ? apiKeyInput : nil)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                apiKeyInput = appState.apiKey(for: draft)
            }
        }
    }

    private func runConnectionTest() {
        isTestingConnection = true
        testStatusMessage = nil
        let config = draft
        let keyToTest = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                if config.kind.requiresAPIKey && keyToTest.isEmpty {
                    throw AIServiceError.missingAPIKey(providerName: config.name)
                }
                let adapter = AIProviderRouter.adapter(for: config.kind)
                let message = try await adapter.testConnection(config: config, apiKey: keyToTest)
                testSucceeded = true
                testStatusMessage = message
            } catch {
                testSucceeded = false
                testStatusMessage = error.localizedDescription
            }
            isTestingConnection = false
        }
    }
}
