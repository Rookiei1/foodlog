import SwiftUI
import SwiftData

@main
public struct FoodLogApp: App {
    @StateObject private var appState = AppStateViewModel()
    private let modelContainer: ModelContainer

    public init() {
        let isInMemory = CommandLine.arguments.contains("-FoodLogInMemoryStore")
        do {
            self.modelContainer = try PersistenceController.makeContainer(inMemory: isInMemory)
        } catch {
            fatalError("Failed to initialize SwiftData ModelContainer: \(error)")
        }

        if CommandLine.arguments.contains("-FoodLogSeedSample") {
            let context = self.modelContainer.mainContext
            PersistenceController.seedSampleDataIfEmpty(in: context)
        }
    }

    public var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appState)
        }
        .modelContainer(modelContainer)
    }
}
