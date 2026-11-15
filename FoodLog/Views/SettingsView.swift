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
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingProvider) { provider in
                AIProviderEditorSheet(provider: provider, isNew: false)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $isAddingNewProvider) {
                AIProviderEditorSheet(
                    provider: AIProviderConfig(
                        name: "自定义服务",
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
        Section("AI 供应商与密钥") {
            ForEach(appState.providers) { provider in
                Button {
                    editingProvider = provider
                } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(provider.supportsVision ? FoodLogTheme.calorieGreen.gradient : FoodLogTheme.proteinBlue.gradient)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: provider.supportsVision ? "eye.fill" : "text.bubble.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(provider.modelName)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if appState.hasAPIKey(for: provider) {
                            Text(provider.kind.requiresAPIKey ? "已配置" : "内置")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(FoodLogTheme.calorieGreen.opacity(0.14))
                                .foregroundStyle(FoodLogTheme.calorieGreen)
                                .clipShape(Capsule())
                        } else {
                            Text("未填 Key")
                                .font(.caption2.weight(.semibold))
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
                Label("新增 AI 供应商", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var defaultModelsSection: some View {
        Section("默认调用模型") {
            Picker(selection: $appState.defaultVisionProviderID) {
                ForEach(appState.providers) { provider in
                    Text("\(provider.name) (\(provider.modelName))").tag(provider.id)
                }
            } label: {
                SettingsIconLabel("拍照识别", systemImage: "camera.fill", color: FoodLogTheme.calorieGreen)
            }

            Picker(selection: $appState.defaultAnalysisProviderID) {
                ForEach(appState.providers) { provider in
                    Text("\(provider.name) (\(provider.modelName))").tag(provider.id)
                }
            } label: {
                SettingsIconLabel("综合分析", systemImage: "wand.and.stars", color: FoodLogTheme.weightPurple)
            }
        }
    }

    private var profileAndGoalsSection: some View {
        Section("身体参数与每日目标") {
            Picker("阶段目标", selection: $appState.profile.goalMode) {
                ForEach(GoalMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Picker("活动水平", selection: $appState.profile.activityLevel) {
                ForEach(ActivityLevel.allCases) { level in
                    Text(level.title).tag(level)
                }
            }

            HStack {
                Text("身高 (cm)")
                Spacer()
                TextField("身高", value: $appState.profile.heightCm, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }

            HStack {
                Text("当前 / 目标体重 (kg)")
                Spacer()
                TextField("当前", value: $appState.profile.currentWeightKg, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 55)
                Text("→")
                    .foregroundStyle(.secondary)
                TextField("目标", value: $appState.profile.targetWeightKg, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 55)
            }

            HStack {
                Text("目标热量 (kcal)")
                Spacer()
                TextField("热量", value: $appState.profile.targetCalories, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .frame(width: 85)
            }

            HStack {
                Text("蛋白 / 脂肪 / 碳水 (g)")
                    .font(.subheadline)
                Spacer()
                TextField("P", value: $appState.profile.targetProteinGrams, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 46)
                Text("/")
                    .foregroundStyle(.secondary)
                TextField("F", value: $appState.profile.targetFatGrams, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 46)
                Text("/")
                    .foregroundStyle(.secondary)
                TextField("C", value: $appState.profile.targetCarbGrams, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 50)
            }

            let recommended = appState.profile.computeRecommendedTargets()
            Button {
                appState.profile.applyRecommendedTargets()
                appState.showTemporaryBanner("已套用推荐目标 \(Int(recommended.targetCalories)) kcal")
            } label: {
                HStack {
                    Text("套用科学推荐目标")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(Int(recommended.targetCalories)) kcal · P \(Int(recommended.targetProteinGrams))g")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var exportAndBackupSection: some View {
        Section("导出与备份") {
            if let foodURL = exportedFoodCSVURL {
                ShareLink(item: foodURL) {
                    SettingsIconLabel("导出饮食 CSV (\(allFoodRecords.count) 条)", systemImage: "tablecells.fill", color: FoodLogTheme.calorieGreen)
                }
            }

            if let weightURL = exportedWeightCSVURL {
                ShareLink(item: weightURL) {
                    SettingsIconLabel("导出体重 CSV (\(allWeightRecords.count) 条)", systemImage: "scalemass.fill", color: FoodLogTheme.weightPurple)
                }
            }

            if let pdfURL = exportedLatestPDFURL {
                ShareLink(item: pdfURL) {
                    SettingsIconLabel("导出分析报告 PDF", systemImage: "doc.richtext.fill", color: FoodLogTheme.carbCoral)
                }
            }

            Toggle("JSON 备份包含餐食原图", isOn: $includePhotosInBackup)
                .onChange(of: includePhotosInBackup) { _, _ in
                    refreshExportFiles()
                }

            if let jsonURL = exportedBackupJSONURL {
                ShareLink(item: jsonURL) {
                    SettingsIconLabel(
                        includePhotosInBackup ? "导出完整备份 JSON (含照片)" : "导出结构化备份 JSON",
                        systemImage: "externaldrive.fill.badge.checkmark",
                        color: FoodLogTheme.proteinBlue
                    )
                }
            }

            Button {
                isImportingBackup = true
            } label: {
                SettingsIconLabel("从 JSON 备份恢复数据", systemImage: "arrow.down.doc.fill", color: FoodLogTheme.fatAmber)
            }

            if let backupStatusMessage {
                Text(backupStatusMessage)
                    .font(.caption)
                    .foregroundStyle(FoodLogTheme.calorieGreen)
            }
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("版本")
                Spacer()
                Text("1.0.0 · Local-first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("local-storage-footer")
            }
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
            estimationAndFluctuationDisclaimer: "短期体重波动主要受水分和糖原影响。",
            calorieAndWeightAnalysis: "请前往「AI 分析」标签页生成最新报告。",
            surplusEvaluation: "按当前目标持续追踪。",
            underEatingDaysReview: "保持规律记录。",
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
                backupStatusMessage = "已恢复：饮食 \(summary.importedFoodsCount) 条、收藏 \(summary.importedFavoritesCount) 条、体重 \(summary.importedWeightsCount) 条。"
                refreshExportFiles()
            } catch {
                backupStatusMessage = "恢复失败：\(error.localizedDescription)"
            }
        case .failure(let error):
            backupStatusMessage = "读取失败：\(error.localizedDescription)"
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
                Section("供应商与接口") {
                    TextField("名称", text: $draft.name)

                    Picker("类型", selection: $draft.kind) {
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
                    Section("API Key（存 Keychain）") {
                        SecureField("sk-... / AIza...", text: $apiKeyInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }

                Section("模型选择") {
                    Picker("预设模型", selection: $draft.modelName) {
                        ForEach(draft.allSelectableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }

                    HStack {
                        TextField("手动输入模型名", text: $customModelInput)
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

                    Picker("视觉能力", selection: $draft.supportsVisionOverride) {
                        Text("自动识别（\(AIVisionCapabilityChecker.supportsVision(kind: draft.kind, modelName: draft.modelName) ? "支持图片" : "仅文本")）")
                            .tag(Optional<Bool>.none)
                        Text("支持图片").tag(Optional<Bool>.some(true))
                        Text("仅文本").tag(Optional<Bool>.some(false))
                    }
                }

                Section {
                    Button {
                        runConnectionTest()
                    } label: {
                        HStack {
                            if isTestingConnection {
                                ProgressView().padding(.trailing, 6)
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
            .navigationTitle(isNew ? "添加供应商" : "编辑供应商")
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
