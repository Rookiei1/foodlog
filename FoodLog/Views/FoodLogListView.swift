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
                                "",
                                selection: $appState.selectedDate,
                                displayedComponents: [.date]
                            )
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "zh_CN"))

                            let totalKcal = filteredEntries.reduce(0.0) { $0 + $1.calories }
                            Text("共 \(filteredEntries.count) 项 · \(Int(totalKcal.rounded())) kcal")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.secondary)

                            Spacer()

                            if !Calendar.current.isDateInToday(appState.selectedDate) {
                                Button("回今天") {
                                    appState.jumpToToday()
                                }
                                .font(.caption.weight(.semibold))
                            }
                        }
                    }

                    if filterScope != .favorites {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                mealChip(title: "全部", isSelected: selectedMealFilter == nil) {
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
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索食物名称")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        appState.openPhotoRecognitionSheet()
                    } label: {
                        Image(systemName: "camera.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        appState.openNewFoodSheet()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }

    private func mealChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 13)
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
                    VStack(spacing: 12) {
                        Image(systemName: "fork.knife.circle.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(FoodLogTheme.calorieGreen.opacity(0.6))
                        Text("暂无饮食记录")
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 12) {
                            Button {
                                appState.openPhotoRecognitionSheet()
                            } label: {
                                Label("AI 拍照记餐", systemImage: "camera.fill")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                appState.openNewFoodSheet()
                            } label: {
                                Label("手动添加", systemImage: "plus")
                            }
                            .buttonStyle(.bordered)
                        }
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
                        HStack(spacing: 12) {
                            FoodThumbnailBadge(
                                photoFilename: snapshot.photoFilenames.first,
                                mealType: snapshot.mealType,
                                size: 46
                            )

                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text(snapshot.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    if snapshot.isFromNutritionLabel {
                                        Text("营养表")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.14))
                                            .foregroundStyle(.blue)
                                            .clipShape(Capsule())
                                    }
                                }

                                HStack(spacing: 6) {
                                    Text(filterScope == .allHistory ? "\(DateKeyHelper.shortDateString(for: snapshot.eatenAt)) \(snapshot.mealType.title)" : "\(DateKeyHelper.timeString(for: snapshot.eatenAt)) \(snapshot.mealType.title)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("· \(Int(snapshot.grams))g")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }

                                HStack(spacing: 5) {
                                    MacroTagPill(prefix: "P", grams: snapshot.proteinGrams, color: FoodLogTheme.proteinBlue)
                                    MacroTagPill(prefix: "F", grams: snapshot.fatGrams, color: FoodLogTheme.fatAmber)
                                    MacroTagPill(prefix: "C", grams: snapshot.carbGrams, color: FoodLogTheme.carbCoral)
                                }
                            }

                            Spacer(minLength: 4)

                            VStack(alignment: .trailing, spacing: 1) {
                                Text("\(Int(snapshot.calories.rounded()))")
                                    .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(.primary)
                                Text("kcal")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
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
                            appState.showTemporaryBanner("已复制「\(snapshot.name)」")
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
                            appState.showTemporaryBanner("已收藏「\(snapshot.name)」")
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
            Section {
                if favoriteTemplates.isEmpty {
                    Text("左滑或右滑饮食记录即可加入常吃收藏。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(favoriteTemplates) { fav in
                        let kcal = Int((fav.caloriesPer100g * fav.defaultGrams / 100.0).rounded())
                        let protein = fav.proteinPer100g * fav.defaultGrams / 100.0
                        let fat = fav.fatPer100g * fav.defaultGrams / 100.0
                        let carb = fav.carbPer100g * fav.defaultGrams / 100.0

                        HStack(spacing: 12) {
                            FoodThumbnailBadge(photoFilename: nil, mealType: fav.defaultMealType, size: 42)

                            VStack(alignment: .leading, spacing: 5) {
                                Text(fav.name)
                                    .font(.subheadline.weight(.semibold))
                                HStack(spacing: 5) {
                                    Text("\(Int(fav.defaultGrams))g · \(kcal) kcal")
                                        .font(.caption2.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    MacroTagPill(prefix: "P", grams: protein, color: FoodLogTheme.proteinBlue)
                                    MacroTagPill(prefix: "F", grams: fat, color: FoodLogTheme.fatAmber)
                                    MacroTagPill(prefix: "C", grams: carb, color: FoodLogTheme.carbCoral)
                                }
                            }
                            Spacer()
                            Button {
                                let targetDate = DateKeyHelper.combining(day: appState.selectedDate, withTimeFrom: Date())
                                let entry = fav.snapshot.makeEntrySnapshot(date: targetDate)
                                modelContext.insert(FoodEntryRecord(snapshot: entry))
                                fav.useCount += 1
                                fav.lastUsedAt = Date()
                                try? modelContext.save()
                                appState.showTemporaryBanner("已快记「\(fav.name)」")
                            } label: {
                                Label("快记", systemImage: "plus")
                                    .font(.caption.weight(.bold))
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 2)
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
                Section("餐食信息") {
                    TextField("食物名称（如：香煎鸡排、纯牛奶）", text: $name)
                        .accessibilityIdentifier("food-editor-name-field")

                    Picker("餐次", selection: $mealType) {
                        ForEach(MealType.allCases) { meal in
                            Label(meal.title, systemImage: meal.systemImage).tag(meal)
                        }
                    }

                    DatePicker(
                        "食用时间",
                        selection: $eatenAt,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                }

                Section {
                    DisclosureGroup("包装营养成分表换算（kJ 转 kcal）", isExpanded: $showLabelCalculator) {
                        Picker("能量单位", selection: $labelEnergyUnit) {
                            ForEach(EnergyUnit.allCases) { unit in
                                Text(unit.title).tag(unit)
                            }
                        }

                        numberRow(title: "每 100g 能量 (\(labelEnergyUnit.rawValue))", value: $labelEnergyPer100g)
                        numberRow(title: "每 100g 蛋白质 (g)", value: $labelProteinPer100g)
                        numberRow(title: "每 100g 脂肪 (g)", value: $labelFatPer100g)
                        numberRow(title: "每 100g 碳水 (g)", value: $labelCarbPer100g)
                        numberRow(title: "包装净含量 (g/ml)", value: $labelNetWeightGrams)

                        VStack(alignment: .leading) {
                            Text("食用比例：\(Int((labelConsumedRatio * 100).rounded()))%")
                                .font(.caption)
                            Slider(value: $labelConsumedRatio, in: 0.1...2.0, step: 0.05)
                        }

                        Button {
                            applyNutritionLabelCalculation()
                        } label: {
                            Label("按成分表自动填入", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Section("分量与营养素") {
                    numberRow(title: "重量 (g)", value: $grams)
                    numberRow(title: "热量 (kcal)", value: $calories)
                    numberRow(title: "蛋白质 (g)", value: $proteinGrams)
                    numberRow(title: "脂肪 (g)", value: $fatGrams)
                    numberRow(title: "碳水化合物 (g)", value: $carbGrams)
                }

                Section("照片与备注") {
                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: 5,
                        matching: .images
                    ) {
                        Label("添加餐食照片", systemImage: "photo.on.rectangle.angled")
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
                                                .frame(width: 72, height: 72)
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
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

                    TextField("备注（选填）", text: $userNote)
                    if !aiAnalysisBasis.isEmpty {
                        Text("估算依据：\(aiAnalysisBasis)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if existingSnapshot == nil {
                        Toggle("加入常吃收藏", isOn: $saveToFavorites)
                    }
                }
            }
            .navigationTitle(existingSnapshot == nil ? "新增记录" : "编辑记录")
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
        uncertaintyNote = "依据包装营养成分表换算"
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
