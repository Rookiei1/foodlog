import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation
import UIKit

public struct AIPhotoRecognitionSheet: View {
    @EnvironmentObject private var appState: AppStateViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    public let initialMealType: MealType
    public let targetDate: Date

    @State private var selectedMealType: MealType = .lunch
    @State private var eatenAt: Date = Date()
    @State private var selectedProviderID: UUID = UUID()
    @State private var userHint: String = ""

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var capturedImagesData: [Data] = []
    @State private var isShowingCamera: Bool = false
    @State private var cameraPermissionError: String? = nil

    @State private var isAnalyzing: Bool = false
    @State private var recognitionTask: Task<Void, Never>? = nil
    @State private var errorMessage: String? = nil
    @State private var recognitionResult: AIFoodRecognitionResponse? = nil

    public init(initialMealType: MealType, targetDate: Date) {
        self.initialMealType = initialMealType
        self.targetDate = targetDate
    }

    private var currentProvider: AIProviderConfig {
        appState.providers.first(where: { $0.id == selectedProviderID })
            ?? appState.defaultVisionProvider
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    photoHeroSection
                    mealAndModelCard
                    if !appState.profile.hasAcceptedPhotoPrivacyNotice {
                        privacyConsentCard
                    }
                    recognizeActionBar

                    if let errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                            Spacer()
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.red.opacity(0.1))
                        )
                    }

                    if let response = recognitionResult {
                        recognizedItemsCards(response: response)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("AI 拍照记餐")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        recognitionTask?.cancel()
                        dismiss()
                    }
                }
                if let response = recognitionResult, response.items.contains(where: \.isSelected) {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存入库") {
                            saveSelectedItems(from: response)
                        }
                        .fontWeight(.bold)
                        .accessibilityIdentifier("save-recognized-foods-button")
                    }
                }
            }
            .onAppear {
                selectedMealType = initialMealType
                eatenAt = DateKeyHelper.combining(day: targetDate, withTimeFrom: Date())
                selectedProviderID = appState.defaultVisionProvider.id
                if CommandLine.arguments.contains("-FoodLogOpenPhotoSheet") && recognitionResult == nil {
                    capturedImagesData = [Self.makeSamplePlaceholderImageData()]
                    startRecognition()
                }
            }
            .onDisappear {
                recognitionTask?.cancel()
            }
            .sheet(isPresented: $isShowingCamera) {
                CameraImagePicker { imageData in
                    if let imageData {
                        capturedImagesData.append(imageData)
                    }
                }
            }
        }
    }

    // MARK: - 1. Photo Hero Area

    private var photoHeroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if capturedImagesData.isEmpty {
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        Button {
                            requestCameraAndOpen()
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "camera.fill")
                                    .font(.title2)
                                Text("拍照识餐")
                                    .font(.subheadline.weight(.bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(FoodLogTheme.calorieGreen.gradient)
                            )
                        }
                        .buttonStyle(.plain)

                        PhotosPicker(
                            selection: $photoItems,
                            maxSelectionCount: 4,
                            matching: .images
                        ) {
                            VStack(spacing: 8) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.title2)
                                    .foregroundStyle(FoodLogTheme.calorieGreen)
                                Text("相册多选")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(.tertiarySystemGroupedBackground))
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    HStack {
                        Label("支持餐盘多菜品拆分、包装营养成分表自动换算", systemImage: "viewfinder")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if currentProvider.kind == .localMock {
                            Button {
                                capturedImagesData.append(Self.makeSamplePlaceholderImageData())
                            } label: {
                                Text("试一下示例图")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(FoodLogTheme.calorieGreen)
                            }
                            .accessibilityIdentifier("use-sample-food-photo-button")
                        }
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(capturedImagesData.enumerated()), id: \.offset) { index, data in
                            ZStack(alignment: .topTrailing) {
                                if let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 92, height: 92)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                Button {
                                    capturedImagesData.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.white, .black.opacity(0.65))
                                }
                                .offset(x: 4, y: -4)
                            }
                        }

                        PhotosPicker(
                            selection: $photoItems,
                            maxSelectionCount: 4,
                            matching: .images
                        ) {
                            VStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.title3.weight(.bold))
                                Text("加图")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                            .frame(width: 92, height: 92)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(.tertiarySystemGroupedBackground))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }

            if let cameraPermissionError {
                Text(cameraPermissionError)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .onChange(of: photoItems) { _, newItems in
            Task {
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        capturedImagesData.append(data)
                    }
                }
                photoItems = []
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - 2. Compact Meal & Model Selector Card

    private var mealAndModelCard: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("餐次", selection: $selectedMealType) {
                    ForEach(MealType.allCases) { meal in
                        Label(meal.title, systemImage: meal.systemImage).tag(meal)
                    }
                }
                .labelsHidden()

                Spacer()

                DatePicker("", selection: $eatenAt, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "zh_CN"))
            }

            Divider()

            HStack {
                Image(systemName: "cpu")
                    .font(.subheadline)
                    .foregroundStyle(FoodLogTheme.calorieGreen)
                Picker("识别模型", selection: $selectedProviderID) {
                    ForEach(appState.providers) { provider in
                        Text("\(provider.name) · \(provider.modelName)")
                            .tag(provider.id)
                    }
                }
                .labelsHidden()

                Spacer()

                if currentProvider.supportsVision {
                    Text("支持视觉")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(FoodLogTheme.calorieGreen.opacity(0.14))
                        .foregroundStyle(FoodLogTheme.calorieGreen)
                        .clipShape(Capsule())
                } else {
                    Text("仅文本")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.14))
                        .foregroundStyle(.red)
                        .clipShape(Capsule())
                }
            }

            if !currentProvider.supportsVision {
                Text("当前模型不支持图片输入，请切换为视觉模型（如 gpt-4o、gemini-2.5-flash 或内置演示）。")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            TextField("补充说明（选填，如：半碗米饭、包装净含量 250ml）", text: $userHint)
                .font(.caption)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.tertiarySystemGroupedBackground))
                )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - 3. Privacy Consent Banner

    private var privacyConsentCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("向所选 AI 发送压缩餐食图")
                    .font(.caption.weight(.semibold))
                Text("照片仅用于本次识别，饮食数据保存在本机")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $appState.profile.hasAcceptedPhotoPrivacyNotice)
                .labelsHidden()
                .accessibilityIdentifier("photo-privacy-consent-toggle")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - 4. Primary Action Button

    private var recognizeActionBar: some View {
        Group {
            if isAnalyzing {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("正在分项识别食物并计算营养…")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button("取消", role: .cancel) {
                        recognitionTask?.cancel()
                        isAnalyzing = false
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            } else {
                Button {
                    startRecognition()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text(recognitionResult == nil ? "开始 AI 识别" : "重新识别")
                            .fontWeight(.bold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(FoodLogTheme.calorieGreen.gradient)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!appState.profile.hasAcceptedPhotoPrivacyNotice || !currentProvider.supportsVision || (capturedImagesData.isEmpty && currentProvider.kind != .localMock))
                .opacity((!appState.profile.hasAcceptedPhotoPrivacyNotice || !currentProvider.supportsVision || (capturedImagesData.isEmpty && currentProvider.kind != .localMock)) ? 0.5 : 1.0)
                .accessibilityIdentifier("start-ai-recognition-button")
            }
        }
    }

    // MARK: - 5. Recognized Items Cards

    @ViewBuilder
    private func recognizedItemsCards(response: AIFoodRecognitionResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("分项识别结果", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(FoodLogTheme.calorieGreen)
                Spacer()
                let totalKcal = response.items.filter(\.isSelected).reduce(0) { $0 + $1.calories }
                Text("已选合计 \(Int(totalKcal.rounded())) kcal")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            if let itemsBinding = Binding($recognitionResult)?.items {
                ForEach(itemsBinding) { $item in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Button {
                                item.isSelected.toggle()
                            } label: {
                                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(item.isSelected ? FoodLogTheme.calorieGreen : .secondary)
                            }
                            .buttonStyle(.plain)

                            TextField("食物名称", text: $item.name)
                                .font(.subheadline.weight(.bold))

                            Text(item.sourceType.badgeTitle)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(item.sourceType == .nutritionLabel ? Color.blue.opacity(0.14) : Color.orange.opacity(0.14))
                                .foregroundStyle(item.sourceType == .nutritionLabel ? .blue : .orange)
                                .clipShape(Capsule())

                            Spacer()

                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                TextField("热量", value: $item.calories, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                                    .frame(width: 58)
                                Text("kcal")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Text("重量")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                TextField("克数", value: $item.estimatedGrams, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.center)
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .frame(width: 48)
                                    .padding(.vertical, 3)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(.tertiarySystemGroupedBackground)))
                                Text("g")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            MacroTagPill(prefix: "P", grams: item.proteinGrams, color: FoodLogTheme.proteinBlue)
                            MacroTagPill(prefix: "F", grams: item.fatGrams, color: FoodLogTheme.fatAmber)
                            MacroTagPill(prefix: "C", grams: item.carbGrams, color: FoodLogTheme.carbCoral)
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(item.uncertainty.isEmpty ? item.basis : "\(item.basis) · \(item.uncertainty)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                }
            }

            Button {
                saveSelectedItems(from: response)
            } label: {
                Text("确认并保存到「\(selectedMealType.title)」")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(FoodLogTheme.calorieGreen)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func requestCameraAndOpen() {
        cameraPermissionError = nil
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraPermissionError = "当前设备无摄像头，已为您载入示例餐盘图。"
            if capturedImagesData.isEmpty {
                capturedImagesData.append(Self.makeSamplePlaceholderImageData())
            }
            return
        }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            isShowingCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        isShowingCamera = true
                    } else {
                        cameraPermissionError = "请在系统设置中开启相机权限，或使用相册选图。"
                    }
                }
            }
        default:
            cameraPermissionError = "相机权限未开启，请前往系统设置允许访问。"
        }
    }

    private func startRecognition() {
        errorMessage = nil
        if capturedImagesData.isEmpty && currentProvider.kind == .localMock {
            capturedImagesData.append(Self.makeSamplePlaceholderImageData())
        }
        isAnalyzing = true
        let provider = currentProvider
        let images = capturedImagesData
        let meal = selectedMealType
        let hint = userHint
        let keychain = appState.keychain

        recognitionTask = Task {
            do {
                let result = try await AIProviderRouter.recognizeFoodWithValidation(
                    images: images,
                    mealType: meal,
                    userHint: hint,
                    config: provider,
                    keychain: keychain
                )
                if !Task.isCancelled {
                    recognitionResult = result
                    isAnalyzing = false
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                    isAnalyzing = false
                }
            }
        }
    }

    private func saveSelectedItems(from response: AIFoodRecognitionResponse) {
        var savedFilenames: [String] = []
        for data in capturedImagesData {
            if let fname = try? ImageStorageService.shared.saveOptimizedPhoto(data: data) {
                savedFilenames.append(fname)
            }
        }

        let selectedItems = response.items.filter(\.isSelected)
        var totalAddedCalories = 0.0
        for item in selectedItems {
            let snapshot = item.toFoodEntrySnapshot(
                mealType: selectedMealType,
                eatenAt: eatenAt,
                photoFilenames: savedFilenames,
                providerName: currentProvider.name,
                modelName: currentProvider.modelName
            )
            totalAddedCalories += snapshot.calories
            modelContext.insert(FoodEntryRecord(snapshot: snapshot))
        }
        try? modelContext.save()
        appState.showTemporaryBanner("已保存 \(selectedItems.count) 项食物（+\(Int(totalAddedCalories.rounded())) kcal）")
        dismiss()
    }

    public static func makeSamplePlaceholderImageData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 360, height: 260))
        let image = renderer.image { ctx in
            let rect = CGRect(x: 0, y: 0, width: 360, height: 260)
            UIColor(red: 0.14, green: 0.56, blue: 0.36, alpha: 1.0).setFill()
            ctx.fill(rect)
            let circleRect = CGRect(x: 110, y: 60, width: 140, height: 140)
            UIColor(white: 1.0, alpha: 0.18).setFill()
            ctx.cgContext.fillEllipse(in: circleRect)
        }
        return image.jpegData(compressionQuality: 0.8) ?? Data()
    }
}

public struct CameraImagePicker: UIViewControllerRepresentable {
    public var onCapture: (Data?) -> Void
    @Environment(\.dismiss) private var dismiss

    public func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    public func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraImagePicker

        init(parent: CameraImagePicker) {
            self.parent = parent
        }

        public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image.jpegData(compressionQuality: 0.85))
            } else {
                parent.onCapture(nil)
            }
            parent.dismiss()
        }

        public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCapture(nil)
            parent.dismiss()
        }
    }
}
