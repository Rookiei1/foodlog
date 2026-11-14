import SwiftUI
import SwiftData
import PhotosUI

public struct FoodLogListView: View {
    @EnvironmentObject private var appState: AppStateViewModel
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \FoodEntryRecord.eatenAt, order: .reverse)
    private var allFoodRecords: [FoodEntryRecord]

    @Query(sort: \FavoriteFoodTemplate.useCount, order: .reverse)
    private var favoriteTemplates: [FavoriteFoodTemplate]

    @State private var filterScope: FilterScope = .selectedDay
    @State private var selectedMealFilter: MealType? = nil
    @State private var searchText: String = ""

    public enum FilterScope: String, CaseIterable, Identifiable {
        case selectedDay = "所选日期"
        case allHistory = "全部历史"
        case favorites = "常吃收藏"
        public var id: String { rawValue }
    }

    public init() {}

    private var filteredEntries: [FoodEntryRecord] {
        allFoodRecords.filter { record in
            if filterScope == .selectedDay && record.dayKey != appState.selectedDayKey {
                return false
            }
            if let meal = selectedMealFilter, record.mealType != meal {
                return false
            }
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let q = searchText.lowercased()
                let matchName = record.name.lowercased().contains(q)
                let matchNote = record.userNote.lowercased().contains(q)
                if !matchName && !matchNote { return false }
            }
            return true
        }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Picker("筛选范围", selection: $filterScope) {
                        ForEach(FilterScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)

                    if filterScope == .selectedDay {
                        HStack {
                            DatePicker(
                                "查看或补录日期",
                                selection: $appState.selectedDate,
                                displayedComponents: [.date]
                            )
                            .environment(\.locale, Locale(identifier: "zh_CN"))
                            .font(.subheadline)
                            Spacer()
                            Button("今天") {
                                appState.jumpToToday()
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                        }
                    }

                    if filterScope != .favorites {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                mealChip(title: "全部餐次", isSelected: selectedMealFilter == nil) {
                                    selectedMealFilter = nil
                                }
                                ForEach(MealType.allCases) { meal in
                                    mealChip(title: meal.title, isSelected: selectedMealFilter == meal) {
                                        selectedMealFilter = meal
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground))

                if filterScope == .favorites {
                    favoritesManagementList
                } else {
                    foodHistoryList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("饮食记录")
            .searchable(text: $searchText, prompt: "搜索食物名称或备注")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        appState.openPhotoRecognitionSheet()
                    } label: {
                        Label("拍照识别", systemImage: "camera.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        appState.openNewFoodSheet()
                    } label: {
                        Label("新增记录", systemImage: "plus")
                    }
                }
            }
        }
    }

    private func mealChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? FoodLogTheme.calorieGreen : Color(.tertiarySystemGroupedBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var foodHistoryList: some View {
        List {
            if filteredEntries.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "fork.knife.circle")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("当前筛选条件下暂无饮食记录")
                            .font(.subheadline.weight(.medium))
                        Text("支持随时补录或修改任意历史日期的餐食")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button {
                                appState.openPhotoRecognitionSheet()
                            } label: {
                                Label("AI 拍照识别", systemImage: "camera.fill")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                appState.openNewFoodSheet()
                            } label: {
                                Label("手动新增", systemImage: "square.and.pencil")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                }
            } else {
                ForEach(filteredEntries) { record in
                    let snapshot = record.snapshot
                    Button {
                        appState.openEditFoodSheet(snapshot)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(snapshot.mealType.title, systemImage: snapshot.mealType.systemImage)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(FoodLogTheme.calorieGreen)
                                Text("\(snapshot.dayKey) \(DateKeyHelper.timeString(for: snapshot.eatenAt))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(snapshot.calories.rounded())) kcal")
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.primary)
                            }

                            HStack(spacing: 6) {
                                Text(snapshot.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if snapshot.isFromNutritionLabel {
                                    Text("营养成分表")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.15))
                                        .foregroundStyle(.blue)
                                        .clipShape(Capsule())
                                }
                                if !snapshot.photoFilenames.isEmpty {
                                    Label("\(snapshot.photoFilenames.count)", systemImage: "photo")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Text("重量 \(Int(snapshot.grams))g  |  蛋白质 \(String(format: "%.1f", snapshot.proteinGrams))g · 脂肪 \(String(format: "%.1f", snapshot.fatGrams))g · 碳水 \(String(format: "%.1f", snapshot.carbGrams))g")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if !snapshot.aiAnalysisBasis.isEmpty {
                                Text(snapshot.aiAnalysisBasis)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            ImageStorageService.shared.deletePhotos(filenames: record.photoFilenames)
                            modelContext.delete(record)
                            try? modelContext.save()
                        } label: {
                            Label("删除", systemImage: "trash")
                        }

                        Button {
                            let dup = snapshot.duplicated(for: appState.selectedDate)
                            modelContext.insert(FoodEntryRecord(snapshot: dup))
                            try? modelContext.save()
                            appState.showTemporaryBanner("已复制「\(snapshot.name)」到 \(appState.selectedDayKey)")
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        .tint(.indigo)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            let fav = FavoriteFoodSnapshot.fromEntry(snapshot)
                            modelContext.insert(FavoriteFoodTemplate(snapshot: fav))
                            record.isFavorite = true
                            try? modelContext.save()
                            appState.showTemporaryBanner("已加入常吃收藏「\(snapshot.name)」")
                        } label: {
                            Label("收藏", systemImage: "star.fill")
                        }
                        .tint(.orange)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var favoritesManagementList: some View {
        List {
            Section("点击右侧「快记」可按默认克数一键记入当前所选日期（\(appState.selectedDayKey)）") {
                if favoriteTemplates.isEmpty {
                    Text("暂无收藏食物，可在饮食列表中右滑任意记录点击「收藏」添加。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(favoriteTemplates) { fav in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(fav.name)
                                    .font(.subheadline.weight(.semibold))
                                Text("默认 \(Int(fav.defaultGrams))g · 每100g: \(Int(fav.caloriesPer100g)) kcal | 蛋白 \(String(format: "%.1f", fav.proteinPer100g))g")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                let targetDate = DateKeyHelper.combining(day: appState.selectedDate, withTimeFrom: Date())
                                let entry = fav.snapshot.makeEntrySnapshot(date: targetDate)
                                modelContext.insert(FoodEntryRecord(snapshot: entry))
                                fav.useCount += 1
                                fav.lastUsedAt = Date()
                                try? modelContext.save()
                                appState.showTemporaryBanner("已记录「\(fav.name)」")
                            } label: {
                                Text("快记")
                                    .font(.caption.weight(.bold))
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            modelContext.delete(favoriteTemplates[index])
                        }
                        try? modelContext.save()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

public struct FoodEntryEditorSheet: View {
    @EnvironmentObject private var appState: AppStateViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allFoodRecords: [FoodEntryRecord]

    public let existingSnapshot: FoodEntrySnapshot?
    public let defaultMealType: MealType
    public let defaultDate: Date

    @State private var name: String = ""
    @State private var mealType: MealType = .lunch
    @State private var eatenAt: Date = Date()
    @State private var grams: Double = 150
    @State private var calories: Double = 250
    @State private var proteinGrams: Double = 18
    @State private var fatGrams: Double = 8
    @State private var carbGrams: Double = 26
    @State private var photoFilenames: [String] = []
    @State private var isFromNutritionLabel: Bool = false
    @State private var aiAnalysisBasis: String = ""
    @State private var uncertaintyNote: String = ""
    @State private var userNote: String = ""
    @State private var saveToFavorites: Bool = false

    // Nutrition label helper states
    @State private var showLabelCalculator: Bool = false
    @State private var labelEnergyUnit: EnergyUnit = .kilojoule
    @State private var labelEnergyPer100g: Double = 1050
    @State private var labelProteinPer100g: Double = 12.0
    @State private var labelFatPer100g: Double = 6.0
    @State private var labelCarbPer100g: Double = 38.0
    @State private var labelNetWeightGrams: Double = 100.0
    @State private var labelConsumedRatio: Double = 1.0

    @State private var selectedPhotoItems: [PhotosPickerItem] = []

    public init(
        existingSnapshot: FoodEntrySnapshot?,
        defaultMealType: MealType,
        defaultDate: Date
    ) {
        self.existingSnapshot = existingSnapshot
        self.defaultMealType = defaultMealType
        self.defaultDate = defaultDate
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("基础信息（支持修改任意历史日期）") {
                    TextField("食物名称（如：香煎鸡排、盒装纯牛奶）", text: $name)
                        .accessibilityIdentifier("food-editor-name-field")

                    Picker("所属餐次", selection: $mealType) {
                        ForEach(MealType.allCases) { meal in
                            Label(meal.title, systemImage: meal.systemImage).tag(meal)
                        }
                    }

                    DatePicker(
                        "食用日期与时间",
                        selection: $eatenAt,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                }

                Section {
                    DisclosureGroup("包装「营养成分表」换算器（支持 kJ 自动转 kcal）", isExpanded: $showLabelCalculator) {
                        Picker("能量单位", selection: $labelEnergyUnit) {
                            ForEach(EnergyUnit.allCases) { unit in
                                Text(unit.title).tag(unit)
                            }
                        }

                        HStack {
                            Text("每 100g 能量 (\(labelEnergyUnit.rawValue))")
                            Spacer()
                            TextField("能量", value: $labelEnergyPer100g, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }

                        HStack {
                            Text("每 100g 蛋白质 (g)")
                            Spacer()
                            TextField("蛋白质", value: $labelProteinPer100g, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }

                        HStack {
                            Text("每 100g 脂肪 (g)")
                            Spacer()
                            TextField("脂肪", value: $labelFatPer100g, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }

                        HStack {
                            Text("每 100g 碳水 (g)")
                            Spacer()
                            TextField("碳水", value: $labelCarbPer100g, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }

                        HStack {
                            Text("包装净含量 (g/ml)")
                            Spacer()
                            TextField("净含量", value: $labelNetWeightGrams, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }

                        VStack(alignment: .leading) {
                            Text("本次食用比例：\(Int((labelConsumedRatio * 100).rounded()))%")
                                .font(.caption)
                            Slider(value: $labelConsumedRatio, in: 0.1...2.0, step: 0.05)
                        }

                        Button {
                            applyNutritionLabelCalculation()
                        } label: {
                            Label("按营养成分表自动填入数值", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Section("分量与三大营养素") {
                    numberRow(title: "食物重量 (克 g)", value: $grams)
                    numberRow(title: "热量 (kcal)", value: $calories)
                    numberRow(title: "蛋白质 (g)", value: $proteinGrams)
                    numberRow(title: "脂肪 (g)", value: $fatGrams)
                    numberRow(title: "碳水化合物 (g)", value: $carbGrams)
                }

                Section("餐食照片（支持多张，已自动压缩优化）") {
                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: 5,
                        matching: .images
                    ) {
                        Label("从相册选择照片（可多选）", systemImage: "photo.on.rectangle.angled")
                    }
                    .onChange(of: selectedPhotoItems) { _, newItems in
                        Task {
                            for item in newItems {
                                if let data = try? await item.loadTransferable(type: Data.self),
                                   let filename = try? ImageStorageService.shared.saveOptimizedPhoto(data: data) {
                                    photoFilenames.append(filename)
                                }
                            }
                            selectedPhotoItems = []
                        }
                    }

                    if !photoFilenames.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(photoFilenames, id: \.self) { filename in
                                    ZStack(alignment: .topTrailing) {
                                        if let uiImage = ImageStorageService.shared.loadImage(filename: filename) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 76, height: 76)
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                        } else {
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(Color.secondary.opacity(0.2))
                                                .frame(width: 76, height: 76)
                                                .overlay(Image(systemName: "photo"))
                                        }
                                        Button {
                                            ImageStorageService.shared.deletePhotos(filenames: [filename])
                                            photoFilenames.removeAll { $0 == filename }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.white, .black.opacity(0.7))
                                        }
                                        .offset(x: 4, y: -4)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("分析依据与备注") {
                    TextField("AI 估算依据 / 来源说明（选填）", text: $aiAnalysisBasis, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("不确定性提示（选填）", text: $uncertaintyNote, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("用户备注（如：去皮、少油、训练后加餐）", text: $userNote, axis: .vertical)
                        .lineLimit(2...4)

                    if existingSnapshot == nil {
                        Toggle("同时加入「常吃食物收藏」", isOn: $saveToFavorites)
                    }
                }
            }
            .navigationTitle(existingSnapshot == nil ? "新增饮食记录" : "编辑饮食记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveRecord()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("food-editor-save-button")
                }
            }
            .onAppear {
                if let snap = existingSnapshot {
                    name = snap.name
                    mealType = snap.mealType
                    eatenAt = snap.eatenAt
                    grams = snap.grams
                    calories = snap.calories
                    proteinGrams = snap.proteinGrams
                    fatGrams = snap.fatGrams
                    carbGrams = snap.carbGrams
                    photoFilenames = snap.photoFilenames
                    isFromNutritionLabel = snap.isFromNutritionLabel
                    aiAnalysisBasis = snap.aiAnalysisBasis
                    uncertaintyNote = snap.uncertaintyNote
                    userNote = snap.userNote
                } else {
                    mealType = defaultMealType
                    eatenAt = DateKeyHelper.combining(day: defaultDate, withTimeFrom: Date())
                }
            }
        }
    }

    private func numberRow(title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 110)
        }
    }

    private func applyNutritionLabelCalculation() {
        let input = NutritionLabelInput(
            energyPerBasis: labelEnergyPer100g,
            energyUnit: labelEnergyUnit,
            basisGrams: 100.0,
            proteinPerBasis: labelProteinPer100g,
            fatPerBasis: labelFatPer100g,
            carbPerBasis: labelCarbPer100g,
            packageNetWeightGrams: labelNetWeightGrams,
            consumedServingsRatio: labelConsumedRatio
        )
        let result = NutritionAndWeightEngine.calculateFromNutritionLabel(input)
        grams = result.consumedGrams
        calories = result.calories
        proteinGrams = result.proteinGrams
        fatGrams = result.fatGrams
        carbGrams = result.carbGrams
        isFromNutritionLabel = true
        aiAnalysisBasis = result.explanation
        uncertaintyNote = "依据包装营养成分表与净含量换算"
    }

    private func saveRecord() {
        let snapshot = FoodEntrySnapshot(
            id: existingSnapshot?.id ?? UUID(),
            name: name,
            mealType: mealType,
            eatenAt: eatenAt,
            dayKey: DateKeyHelper.dayKey(for: eatenAt),
            grams: grams,
            estimatedMinGrams: existingSnapshot?.estimatedMinGrams,
            estimatedMaxGrams: existingSnapshot?.estimatedMaxGrams,
            calories: calories,
            proteinGrams: proteinGrams,
            fatGrams: fatGrams,
            carbGrams: carbGrams,
            photoFilenames: photoFilenames,
            isFromNutritionLabel: isFromNutritionLabel,
            aiAnalysisBasis: aiAnalysisBasis,
            uncertaintyNote: uncertaintyNote,
            aiProviderName: existingSnapshot?.aiProviderName,
            aiModelName: existingSnapshot?.aiModelName,
            userNote: userNote,
            isFavorite: saveToFavorites || (existingSnapshot?.isFavorite ?? false)
        )

        if let existingID = existingSnapshot?.id,
           let target = allFoodRecords.first(where: { $0.id == existingID }) {
            target.update(from: snapshot)
        } else {
            modelContext.insert(FoodEntryRecord(snapshot: snapshot))
            if saveToFavorites {
                let fav = FavoriteFoodSnapshot.fromEntry(snapshot)
                modelContext.insert(FavoriteFoodTemplate(snapshot: fav))
            }
        }
        try? modelContext.save()
        dismiss()
    }
}
