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

                FoodLogListView()
                    .tabItem {
                        Label(MainTab.food.title, systemImage: MainTab.food.systemImage)
                    }
                    .tag(MainTab.food)
                    .accessibilityIdentifier("tab-food")

                WeightTrackingView()
                    .tabItem {
                        Label(MainTab.weight.title, systemImage: MainTab.weight.systemImage)
                    }
                    .tag(MainTab.weight)
                    .accessibilityIdentifier("tab-weight")

                AIAnalysisView()
                    .tabItem {
                        Label(MainTab.analysis.title, systemImage: MainTab.analysis.systemImage)
                    }
                    .tag(MainTab.analysis)
                    .accessibilityIdentifier("tab-analysis")

                SettingsView()
                    .tabItem {
                        Label(MainTab.settings.title, systemImage: MainTab.settings.systemImage)
                    }
                    .tag(MainTab.settings)
                    .accessibilityIdentifier("tab-settings")
            }
            .tint(FoodLogTheme.calorieGreen)

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
    }
}
