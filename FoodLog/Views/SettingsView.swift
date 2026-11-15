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

    // DeepSeek API Configuration
    @State private var apiKeyInput: String = ""
    @State private var baseURLInput: String = "https://api.deepseek.com/v1"
    @State private var selectedModel: String = "deepseek-flash"
    @State private var customModelText: String = ""
    @State private var isTestingConnection: Bool = false
    @State private var testStatusMessage: String? = nil
    @State private var testSucceeded: Bool = false

    // Export & Backup
    @State private var includePhotosInBackup: Bool = false
    @State private var exportedFoodCSVURL: URL? = nil
    @State private var exportedWeightCSVURL: URL? = nil
    @State private var exportedBackupJSONURL: URL? = nil
    @State private var isImportingBackup: Bool = false
    @State private var backupStatusMessage: String? = nil

    public init() {}

    private var deepSeekConfig: AIProviderConfig {
        if var ds = appState.providers.first(where: { $0.kind == .deepSeek }) {
            if ds.modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "flash" || ds.modelName.isEmpty {
                ds.modelName = "deepseek-flash"
            }
            return ds
        }
        return AIProviderConfig(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555503") ?? UUID(),
            name: "DeepSeek API",
            kind: .deepSeek,
            baseURL: "https://api.deepseek.com/v1",
            modelName: "deepseek-flash"
        )
    }

    public var body: some View {
        NavigationStack {
            Form {
                deepSeekApiSection
                exportAndBackupSection
                aboutSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("设置与导出")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $isImportingBackup,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleBackupFileImport(result)
            }
            .onAppear {
                loadDeepSeekConfig()
                refreshExportFiles()
            }
        }
    }

    // MARK: - 1. DeepSeek API 配置（主推与默认）

    private var deepSeekApiSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(FoodLogTheme.deepCharcoalButton)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "sparkles")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("DeepSeek API")
                            .font(.headline)
                            .foregroundStyle(FoodLogTheme.charcoalText)
                        Text("用于拍照自动拆解菜品条目与估算热量")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    if !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("已存 Key")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(FoodLogTheme.morandiProteinSage.opacity(0.18))
                            .foregroundStyle(FoodLogTheme.morandiProteinSage)
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 2)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("API Key (sk-...)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack {
                    SecureField("粘贴你的 DeepSeek API Key", text: $apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("settings-api-key-input")
                    if !apiKeyInput.isEmpty {
                        Button("保存") {
                            saveDeepSeekKey()
                        }
                        .font(.caption.weight(.bold))
                        .buttonStyle(.borderedProminent)
                        .tint(FoodLogTheme.deepCharcoalButton)
                    }
                }
            }
            .padding(.vertical, 4)

            Picker("模型选择", selection: $selectedModel) {
                Text("deepseek-flash（推荐 · 极速识别）").tag("deepseek-flash")
                Text("deepseek-v4-pro（高精度）").tag("deepseek-v4-pro")
                Text("deepseek-chat（纯文本）").tag("deepseek-chat")
                if !customModelText.isEmpty && customModelText != "deepseek-flash" && customModelText != "deepseek-v4-pro" && customModelText != "deepseek-chat" {
                    Text(customModelText).tag(customModelText)
                }
            }
            .onChange(of: selectedModel) { _, newModel in
                var effective = newModel.trimmingCharacters(in: .whitespacesAndNewlines)
                if effective.lowercased() == "flash" {
                    effective = "deepseek-flash"
                }
                updateDeepSeekModel(effective)
            }

            HStack {
                TextField("或手动输入模型名（如 deepseek-flash）", text: $customModelText)
                    .font(.caption)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !customModelText.isEmpty {
                    Button("使用") {
                        dismissKeyboard()
                        var trimmed = customModelText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.lowercased() == "flash" {
                            trimmed = "deepseek-flash"
                        }
                        selectedModel = trimmed
                        updateDeepSeekModel(trimmed)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FoodLogTheme.charcoalText)
                }
            }

            DisclosureGroup("高级：接口 Base URL") {
                TextField("https://api.deepseek.com/v1", text: $baseURLInput)
                    .font(.caption.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onChange(of: baseURLInput) { _, newURL in
                        updateDeepSeekBaseURL(newURL)
                    }
            }
            .font(.caption)

            Button {
                testDeepSeekConnection()
            } label: {
                HStack {
                    if isTestingConnection {
                        ProgressView().padding(.trailing, 6)
                    }
                    Label("测试 API 连接", systemImage: "bolt.horizontal.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FoodLogTheme.charcoalText)
                }
            }
            .accessibilityIdentifier("settings-test-connection-button")
            .disabled(isTestingConnection || apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let testStatusMessage {
                Text(testStatusMessage)
                    .font(.caption)
                    .foregroundStyle(testSucceeded ? FoodLogTheme.morandiProteinSage : .red)
            }
        } header: {
            Text("AI 拍照识别配置")
        } footer: {
            Text("API Key 仅加密存储于 iPhone 本地 Keychain，绝不上云或打印日志。未配置 Key 时拍照自动平滑回退至本地离线演示。")
                .font(.caption2)
        }
    }

    // MARK: - 2. 导出与备份

    private var exportAndBackupSection: some View {
        Section("数据导出与备份") {
            if let foodURL = exportedFoodCSVURL {
                ShareLink(item: foodURL) {
                    SettingsIconLabel("导出饮食记录 CSV (\(allFoodRecords.count) 条)", systemImage: "tablecells.fill", color: FoodLogTheme.morandiProteinSage)
                }
            }

            if let weightURL = exportedWeightCSVURL {
                ShareLink(item: weightURL) {
                    SettingsIconLabel("导出体重记录 CSV (\(allWeightRecords.count) 条)", systemImage: "scalemass.fill", color: FoodLogTheme.morandiCarbTerracotta)
                }
            }

            Toggle("备份中包含餐食原图", isOn: $includePhotosInBackup)
                .font(.subheadline)
                .onChange(of: includePhotosInBackup) { _, _ in
                    refreshExportFiles()
                }

            if let jsonURL = exportedBackupJSONURL {
                ShareLink(item: jsonURL) {
                    SettingsIconLabel(
                        includePhotosInBackup ? "导出完整备份 JSON (含照片)" : "导出完整记录 JSON",
                        systemImage: "externaldrive.fill.badge.checkmark",
                        color: FoodLogTheme.charcoalText
                    )
                }
            }

            Button {
                isImportingBackup = true
            } label: {
                SettingsIconLabel("从 JSON 备份恢复数据", systemImage: "arrow.down.doc.fill", color: FoodLogTheme.morandiFatAlmond)
            }

            if let backupStatusMessage {
                Text(backupStatusMessage)
                    .font(.caption)
                    .foregroundStyle(FoodLogTheme.morandiProteinSage)
            }
        }
    }

    // MARK: - 3. 关于

    private var aboutSection: some View {
        Section {
            HStack {
                Text("架构")
                Spacer()
                Text("Local-first · 本地优先存储")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("版本")
                Spacer()
                Text("1.0.0")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helper Methods

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func loadDeepSeekConfig() {
        let config = deepSeekConfig
        apiKeyInput = appState.apiKey(for: config)
        baseURLInput = config.baseURL
        var model = config.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.isEmpty || model.lowercased() == "flash" {
            model = "deepseek-flash"
        }
        selectedModel = model
        if model == "deepseek-flash" || model == "deepseek-v4-pro" || model == "deepseek-chat" {
            customModelText = ""
        } else {
            customModelText = model
        }
    }

    private func saveDeepSeekKey() {
        dismissKeyboard()
        var config = deepSeekConfig
        var model = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.isEmpty || model.lowercased() == "flash" {
            model = "deepseek-flash"
        }
        config.modelName = model
        config.baseURL = baseURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        try? appState.upsertProvider(config, apiKey: apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines))
        appState.defaultVisionProviderID = config.id
        appState.defaultAnalysisProviderID = config.id
        appState.showTemporaryBanner("已保存 DeepSeek API Key")
    }

    private func updateDeepSeekModel(_ newModel: String) {
        var config = deepSeekConfig
        var model = newModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.isEmpty || model.lowercased() == "flash" {
            model = "deepseek-flash"
        }
        config.modelName = model
        try? appState.upsertProvider(config, apiKey: nil)
        appState.defaultVisionProviderID = config.id
        appState.defaultAnalysisProviderID = config.id
    }

    private func updateDeepSeekBaseURL(_ newURL: String) {
        var config = deepSeekConfig
        config.baseURL = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        try? appState.upsertProvider(config, apiKey: nil)
    }

    private func testDeepSeekConnection() {
        dismissKeyboard()
        isTestingConnection = true
        testStatusMessage = nil
        saveDeepSeekKey()
        let config = deepSeekConfig
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                if key.isEmpty {
                    throw AIServiceError.missingAPIKey(providerName: "DeepSeek")
                }
                let adapter = AIProviderRouter.adapter(for: .deepSeek)
                let reply = try await adapter.testConnection(config: config, apiKey: key)
                testSucceeded = true
                testStatusMessage = reply
            } catch {
                testSucceeded = false
                testStatusMessage = error.localizedDescription
            }
            isTestingConnection = false
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
