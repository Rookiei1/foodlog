import SwiftUI

public struct DailyGoalAndProfileEditorSheet: View {
    @EnvironmentObject private var appState: AppStateViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var draftProfile: UserProfileSettings = UserProfileSettings()

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("每日能量与营养目标")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(FoodLogTheme.charcoalText)
                        Text("点击目标或身体参数可随时更新，系统根据 Mifflin-St Jeor 科学公式自动测算 TDEE 与推荐摄入量。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("每日摄入目标") {
                    HStack {
                        Label("目标热量", systemImage: "flame.fill")
                            .foregroundStyle(FoodLogTheme.charcoalText)
                        Spacer()
                        TextField("目标热量", value: $draftProfile.targetCalories, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(.body, design: .rounded).bold())
                            .frame(width: 90)
                        Text("kcal")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("目标蛋白质", systemImage: "leaf.fill")
                            .foregroundStyle(FoodLogTheme.morandiProteinSage)
                        Spacer()
                        TextField("蛋白质", value: $draftProfile.targetProteinGrams, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(.body, design: .rounded))
                            .frame(width: 80)
                        Text("g")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("目标碳水", systemImage: "circle.hexagongrid.fill")
                            .foregroundStyle(FoodLogTheme.morandiCarbTerracotta)
                        Spacer()
                        TextField("碳水", value: $draftProfile.targetCarbGrams, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(.body, design: .rounded))
                            .frame(width: 80)
                        Text("g")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("目标脂肪", systemImage: "drop.fill")
                            .foregroundStyle(FoodLogTheme.morandiFatAlmond)
                        Spacer()
                        TextField("脂肪", value: $draftProfile.targetFatGrams, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(.body, design: .rounded))
                            .frame(width: 80)
                        Text("g")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("阶段健康目标") {
                    Picker("目标模式", selection: $draftProfile.goalMode) {
                        ForEach(GoalMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("身体基础参数") {
                    Picker("生理性别", selection: $draftProfile.sex) {
                        ForEach(BiologicalSex.allCases) { sex in
                            Text(sex.title).tag(sex)
                        }
                    }

                    HStack {
                        Text("年龄")
                        Spacer()
                        TextField("年龄", value: $draftProfile.age, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text("岁")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("身高")
                        Spacer()
                        TextField("身高", value: $draftProfile.heightCm, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text("cm")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("当前体重")
                        Spacer()
                        TextField("当前体重", value: $draftProfile.currentWeightKg, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text("kg")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("目标体重")
                        Spacer()
                        TextField("目标体重", value: $draftProfile.targetWeightKg, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text("kg")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Picker("日常活动水平", selection: $draftProfile.activityLevel) {
                        ForEach(ActivityLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                }

                Section("科学建议与自动测算") {
                    let recommended = draftProfile.computeRecommendedTargets()
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("基础代谢 (BMR)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(recommended.bmr)) kcal")
                                .font(.caption.weight(.medium))
                        }
                        HStack {
                            Text("每日总消耗 (TDEE)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(recommended.tdee)) kcal")
                                .font(.caption.weight(.medium))
                        }
                        Divider().padding(.vertical, 2)
                        Text("系统建议目标: \(Int(recommended.targetCalories)) kcal · 蛋 \(Int(recommended.targetProteinGrams))g · 碳 \(Int(recommended.targetCarbGrams))g · 脂 \(Int(recommended.targetFatGrams))g")
                            .font(.caption)
                            .foregroundStyle(FoodLogTheme.charcoalText)

                        Button {
                            draftProfile.applyRecommendedTargets()
                        } label: {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("一键应用科学推荐目标")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(FoodLogTheme.morandiCarbTerracotta)
                        }
                        .accessibilityIdentifier("apply-recommended-goal-button")
                        .padding(.top, 4)
                    }
                }
            }
            .navigationTitle("调整目标与身体参数")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        appState.profile = draftProfile
                        appState.showTemporaryBanner("已更新每日目标与身体参数")
                        dismiss()
                    }
                    .accessibilityIdentifier("daily-goal-save-button")
                    .fontWeight(.semibold)
                    .foregroundStyle(FoodLogTheme.deepCharcoalButton)
                }
            }
            .onAppear {
                draftProfile = appState.profile
            }
        }
        .accessibilityIdentifier("daily-goal-editor-sheet")
    }
}
