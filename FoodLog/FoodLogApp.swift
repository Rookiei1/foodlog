import SwiftUI
import SwiftData

@main
public struct FoodLogApp: App {
    @StateObject private var appState: AppStateViewModel
    private let modelContainer: ModelContainer

    public init() {
        let args = CommandLine.arguments
        let isInMemory = args.contains("-FoodLogInMemoryStore")
        do {
            self.modelContainer = try PersistenceController.makeContainer(inMemory: isInMemory)
        } catch {
            fatalError("Failed to initialize SwiftData ModelContainer: \(error)")
        }

        if args.contains("-FoodLogSeedSample") {
            let context = self.modelContainer.mainContext
            PersistenceController.seedSampleDataIfEmpty(in: context)
        }

        let initialState = AppStateViewModel()
        if let tabIdx = args.firstIndex(of: "-FoodLogInitialTab"),
           tabIdx + 1 < args.count,
           let tab = MainTab(rawValue: args[tabIdx + 1]) {
            initialState.activeTab = tab
        }
        if args.contains("-FoodLogOpenPhotoSheet") {
            initialState.profile.hasAcceptedPhotoPrivacyNotice = true
            initialState.isPresentingPhotoRecognitionSheet = true
        }
        if args.contains("-FoodLogOpenGoalEditor") {
            initialState.isPresentingDailyGoalEditor = true
        }
        if let segIdx = args.firstIndex(of: "-FoodLogHistorySegment"),
           segIdx + 1 < args.count {
            initialState.historySegment = args[segIdx + 1]
        }
        _appState = StateObject(wrappedValue: initialState)
    }

    public var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appState)
        }
        .modelContainer(modelContainer)
    }
}
