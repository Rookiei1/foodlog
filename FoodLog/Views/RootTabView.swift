import SwiftUI
import SwiftData

public struct RootTabView: View {
    @EnvironmentObject private var appState: AppStateViewModel
    @Environment(\.modelContext) private var modelContext

    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $appState.activeTab) {
                DashboardView()
                    .tabItem {
                        Label(MainTab.dashboard.title, systemImage: MainTab.dashboard.systemImage)
                    }
                    .tag(MainTab.dashboard)
                    .accessibilityIdentifier("tab-dashboard")

                HistoryView()
                    .tabItem {
                        Label(MainTab.history.title, systemImage: MainTab.history.systemImage)
                    }
                    .tag(MainTab.history)
                    .accessibilityIdentifier("tab-history")

                SettingsView()
                    .tabItem {
                        Label(MainTab.settings.title, systemImage: MainTab.settings.systemImage)
                    }
                    .tag(MainTab.settings)
                    .accessibilityIdentifier("tab-settings")
            }
            .tint(FoodLogTheme.deepCharcoalButton)

            if let banner = appState.statusBannerMessage {
                Text(banner)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.82))
                    )
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .sheet(isPresented: $appState.isPresentingPhotoRecognitionSheet) {
            AIPhotoRecognitionSheet(
                initialMealType: appState.presetMealForEditor,
                targetDate: appState.selectedDate
            )
            .environmentObject(appState)
        }
        .sheet(isPresented: $appState.isPresentingFoodEditorSheet) {
            FoodEntryEditorSheet(
                existingSnapshot: appState.editingFoodSnapshot,
                defaultMealType: appState.presetMealForEditor,
                defaultDate: appState.selectedDate
            )
            .environmentObject(appState)
        }
        .sheet(isPresented: $appState.isPresentingWeightEditorSheet) {
            WeightEntryEditorSheet(
                existingSnapshot: appState.editingWeightSnapshot,
                defaultDate: appState.selectedDate
            )
            .environmentObject(appState)
        }
        .sheet(isPresented: $appState.isPresentingDailyGoalEditor) {
            DailyGoalAndProfileEditorSheet()
                .environmentObject(appState)
        }
    }
}
