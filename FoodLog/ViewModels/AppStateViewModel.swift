import Foundation
import SwiftUI

public enum MainTab: String, CaseIterable, Identifiable, Sendable {
    case dashboard = "dashboard"
    case history = "history"
    case settings = "settings"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: return "首页"
        case .history: return "历史"
        case .settings: return "设置"
        }
    }

    public var systemImage: String {
        switch self {
        case .dashboard: return "flame.fill"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape.fill"
        }
    }
}

@MainActor
public final class AppStateViewModel: ObservableObject {
    @Published public var activeTab: MainTab = .dashboard
    @Published public var selectedDate: Date = Date()
    @Published public var profile: UserProfileSettings {
        didSet { saveProfile() }
    }
    @Published public var providers: [AIProviderConfig] {
        didSet { saveProviders() }
    }
    @Published public var defaultVisionProviderID: UUID {
        didSet { userDefaults.set(defaultVisionProviderID.uuidString, forKey: Keys.defaultVisionProviderID) }
    }
    @Published public var defaultAnalysisProviderID: UUID {
        didSet { userDefaults.set(defaultAnalysisProviderID.uuidString, forKey: Keys.defaultAnalysisProviderID) }
    }

    // Sheet presentation states
    @Published public var isPresentingPhotoRecognitionSheet: Bool = false
    @Published public var isPresentingDailyGoalEditor: Bool = false
    @Published public var historySegment: String = "food"
    @Published public var isPresentingFoodEditorSheet: Bool = false
    @Published public var presetMealForEditor: MealType = .lunch
    @Published public var editingFoodSnapshot: FoodEntrySnapshot? = nil

    @Published public var isPresentingWeightEditorSheet: Bool = false
    @Published public var editingWeightSnapshot: WeightRecordSnapshot? = nil

    @Published public var statusBannerMessage: String? = nil

    public let keychain: KeychainStoring
    private let userDefaults: UserDefaults

    private enum Keys {
        static let profile = "foodlog.user.profile.v1"
        static let providers = "foodlog.ai.providers.v1"
        static let defaultVisionProviderID = "foodlog.ai.defaultVisionProviderID.v1"
        static let defaultAnalysisProviderID = "foodlog.ai.defaultAnalysisProviderID.v1"
    }

    public init(
        userDefaults: UserDefaults = .standard,
        keychain: KeychainStoring = SystemKeychainService.shared
    ) {
        self.userDefaults = userDefaults
        self.keychain = keychain

        if let data = userDefaults.data(forKey: Keys.profile),
           let decoded = try? JSONDecoder().decode(UserProfileSettings.self, from: data) {
            self.profile = decoded
        } else {
            var initialProfile = UserProfileSettings()
            initialProfile.applyRecommendedTargets()
            self.profile = initialProfile
        }

        var loadedProviders: [AIProviderConfig]
        if let data = userDefaults.data(forKey: Keys.providers),
           let decoded = try? JSONDecoder().decode([AIProviderConfig].self, from: data),
           !decoded.isEmpty {
            loadedProviders = decoded
        } else {
            loadedProviders = AIProviderConfig.defaultProviders()
        }

        // Migrate any legacy "flash" or empty model names for DeepSeek to "deepseek-flash"
        loadedProviders = loadedProviders.map { provider in
            var p = provider
            if p.kind == .deepSeek && (p.modelName.lowercased() == "flash" || p.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                p.modelName = "deepseek-flash"
            }
            return p
        }
        self.providers = loadedProviders

        let fallbackID = loadedProviders.first?.id ?? UUID()
        if let visionStr = userDefaults.string(forKey: Keys.defaultVisionProviderID),
           let uuid = UUID(uuidString: visionStr),
           loadedProviders.contains(where: { $0.id == uuid }) {
            self.defaultVisionProviderID = uuid
        } else {
            self.defaultVisionProviderID = fallbackID
        }

        if let analysisStr = userDefaults.string(forKey: Keys.defaultAnalysisProviderID),
           let uuid = UUID(uuidString: analysisStr),
           loadedProviders.contains(where: { $0.id == uuid }) {
            self.defaultAnalysisProviderID = uuid
        } else {
            self.defaultAnalysisProviderID = fallbackID
        }
    }

    public var selectedDayKey: String {
        DateKeyHelper.dayKey(for: selectedDate)
    }

    public func moveSelectedDay(by days: Int) {
        selectedDate = DateKeyHelper.shiftingDays(selectedDate, by: days)
    }

    public func jumpToToday() {
        selectedDate = Date()
    }

    public var defaultVisionProvider: AIProviderConfig {
        providers.first(where: { $0.id == defaultVisionProviderID })
            ?? providers.first
            ?? AIProviderConfig.defaultProviders()[0]
    }

    public var defaultAnalysisProvider: AIProviderConfig {
        providers.first(where: { $0.id == defaultAnalysisProviderID })
            ?? providers.first
            ?? AIProviderConfig.defaultProviders()[0]
    }

    public func openNewFoodSheet(for meal: MealType? = nil) {
        editingFoodSnapshot = nil
        presetMealForEditor = meal ?? MealType.suggested(for: selectedDate)
        isPresentingFoodEditorSheet = true
    }

    public func openEditFoodSheet(_ snapshot: FoodEntrySnapshot) {
        editingFoodSnapshot = snapshot
        presetMealForEditor = snapshot.mealType
        isPresentingFoodEditorSheet = true
    }

    public func openPhotoRecognitionSheet(for meal: MealType? = nil) {
        presetMealForEditor = meal ?? MealType.suggested(for: selectedDate)
        isPresentingPhotoRecognitionSheet = true
    }

    public func openNewWeightSheet() {
        editingWeightSnapshot = nil
        isPresentingWeightEditorSheet = true
    }

    public func openEditWeightSheet(_ snapshot: WeightRecordSnapshot) {
        editingWeightSnapshot = snapshot
        isPresentingWeightEditorSheet = true
    }

    // MARK: - Keychain Credential Management

    public func apiKey(for provider: AIProviderConfig) -> String {
        keychain.readSecret(forAccount: provider.id.uuidString) ?? ""
    }

    public func hasAPIKey(for provider: AIProviderConfig) -> Bool {
        if !provider.kind.requiresAPIKey { return true }
        return !(keychain.readSecret(forAccount: provider.id.uuidString) ?? "").isEmpty
    }

    public func saveAPIKey(_ key: String, for provider: AIProviderConfig) throws {
        try keychain.saveSecret(key, forAccount: provider.id.uuidString)
        objectWillChange.send()
    }

    public func upsertProvider(_ config: AIProviderConfig, apiKey: String? = nil) throws {
        if let index = providers.firstIndex(where: { $0.id == config.id }) {
            providers[index] = config
        } else {
            providers.append(config)
        }
        if let apiKey {
            try saveAPIKey(apiKey, for: config)
        }
    }

    public func deleteProvider(_ config: AIProviderConfig) {
        guard providers.count > 1 else { return }
        keychain.deleteSecret(forAccount: config.id.uuidString)
        providers.removeAll { $0.id == config.id }
        if !providers.contains(where: { $0.id == defaultVisionProviderID }), let first = providers.first {
            defaultVisionProviderID = first.id
        }
        if !providers.contains(where: { $0.id == defaultAnalysisProviderID }), let first = providers.first {
            defaultAnalysisProviderID = first.id
        }
    }

    public func showTemporaryBanner(_ text: String) {
        statusBannerMessage = text
        Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if self.statusBannerMessage == text {
                self.statusBannerMessage = nil
            }
        }
    }

    private func saveProfile() {
        if let data = try? JSONEncoder().encode(profile) {
            userDefaults.set(data, forKey: Keys.profile)
        }
    }

    private func saveProviders() {
        if let data = try? JSONEncoder().encode(providers) {
            userDefaults.set(data, forKey: Keys.providers)
        }
    }
}
