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
            Form {
                privacyNoticeSection
                photoSelectionSection
                modelAndMealSection
                actionButtonSection

                if let errorMessage {
                    Section("识别提示") {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if let response = recognitionResult {
                    recognizedResultsSection(response: response)
                }
            }
            .navigationTitle("AI 拍照识别记录")
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
                        Button("保存到饮食库") {
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

    private var privacyNoticeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(.orange)
                    Text("第三方 AI 图片传输说明")
                        .font(.subheadline.weight(.semibold))
                }
                Text("发起识别前请注意：您所拍摄或选择的餐食照片将经过压缩脱敏后传输至您当前所选的 AI 供应商（\(currentProvider.name)）进行营养成分分析。应用默认将所有饮食数据保存在本机。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("我已知悉并同意向所选 AI 服务发送本次图片", isOn: $appState.profile.hasAcceptedPhotoPrivacyNotice)
                    .font(.caption.weight(.medium))
                    .accessibilityIdentifier("photo-privacy-consent-toggle")
            }
            .padding(.vertical, 2)
        }
    }

    private var photoSelectionSection: some View {
        Section("1. 拍摄或选择餐食 / 营养成分表照片（支持同一餐多图去重）") {
            HStack(spacing: 12) {
                Button {
                    requestCameraAndOpen()
                } label: {
                    Label("打开相机拍照", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                PhotosPicker(
                    selection: $photoItems,
                    maxSelectionCount: 4,
                    matching: .images
                ) {
                    Label("相册多选", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
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
            }

            if currentProvider.kind == .localMock && capturedImagesData.isEmpty {
                Button {
                    capturedImagesData.append(Self.makeSamplePlaceholderImageData())
                } label: {
                    Label("使用示例餐盘图片体验（鸡排 + 烤肠 + 牛奶）", systemImage: "sparkles.rectangle.stack")
                        .font(.caption.weight(.semibold))
                }
                .accessibilityIdentifier("use-sample-food-photo-button")
            }

            if let cameraPermissionError {
                Text(cameraPermissionError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if !capturedImagesData.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(capturedImagesData.enumerated()), id: \.offset) { index, data in
                            ZStack(alignment: .topTrailing) {
                                if let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 82, height: 82)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                Button {
                                    capturedImagesData.remove(at: index)
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
    }

    private var modelAndMealSection: some View {
        Section("2. 选择餐次与 AI 视觉模型") {
            Picker("餐次", selection: $selectedMealType) {
                ForEach(MealType.allCases) { meal in
                    Label(meal.title, systemImage: meal.systemImage).tag(meal)
                }
            }

            DatePicker("食用时间", selection: $eatenAt, displayedComponents: [.date, .hourAndMinute])
                .environment(\.locale, Locale(identifier: "zh_CN"))

            Picker("AI 供应商与模型", selection: $selectedProviderID) {
                ForEach(appState.providers) { provider in
                    Text("\(provider.name) · \(provider.modelName)")
                        .tag(provider.id)
                }
            }

            HStack {
                Text("模型视觉能力检查")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if currentProvider.supportsVision {
                    Label("支持图像输入", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FoodLogTheme.calorieGreen)
                } else {
                    Label("纯文本模型（不支持图片）", systemImage: "xmark.octagon.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }

            if !currentProvider.supportsVision {
                Text("当前选择的模型「\(currentProvider.modelName)」不支持视觉图片输入。请切换为支持视觉的模型（如 gpt-4o、gemini-2.5-flash、deepseek-vl2 或内置演示模型），避免发送错误的图像请求。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            TextField("补充说明（选填，如：包含包装营养成分表、半份米饭）", text: $userHint)
                .font(.subheadline)
        }
    }

    private var actionButtonSection: some View {
        Section {
            if isAnalyzing {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("AI 正在分项识别食物并估算营养成分…")
                        .font(.subheadline)
                    Spacer()
                    Button("取消", role: .cancel) {
                        recognitionTask?.cancel()
                        isAnalyzing = false
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button {
                    startRecognition()
                } label: {
                    HStack {
                        Spacer()
                        Label("开始 AI 识别与营养估算", systemImage: "sparkles")
                            .font(.headline)
                        Spacer()
                    }
                }
                .disabled(!appState.profile.hasAcceptedPhotoPrivacyNotice || !currentProvider.supportsVision || (capturedImagesData.isEmpty && currentProvider.kind != .localMock))
                .accessibilityIdentifier("start-ai-recognition-button")
            }
        }
    }

    @ViewBuilder
    private func recognizedResultsSection(response: AIFoodRecognitionResponse) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label(response.mealSummary, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FoodLogTheme.calorieGreen)
                Text(response.deduplicationNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(response.overallUncertaintyBanner)
                    .font(.caption)
                    .padding(8)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        } header: {
            Text("3. AI 分项分析结果（可逐项修改后保存）")
        }

        if let itemsBinding = Binding($recognitionResult)?.items {
            ForEach(itemsBinding) { $item in
                Section {
                    Toggle(isOn: $item.isSelected) {
                        HStack {
                            TextField("食物名称", text: $item.name)
                                .font(.headline)
                            Text(item.sourceType.badgeTitle)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(item.sourceType == .nutritionLabel ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15))
                                .foregroundStyle(item.sourceType == .nutritionLabel ? .blue : .orange)
                                .clipShape(Capsule())
                        }
                    }

                    HStack {
                        Text("估算重量 (g)")
                        if let rangeText = item.weightRangeDescription {
                            Text("合理区间 \(rangeText)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        TextField("克数", value: $item.estimatedGrams, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }

                    HStack {
                        Text("热量 (kcal)")
                        Spacer()
                        TextField("热量", value: $item.calories, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }

                    HStack {
                        Text("蛋白质 / 脂肪 / 碳水 (g)")
                            .font(.caption)
                        Spacer()
                        TextField("蛋白", value: $item.proteinGrams, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 52)
                        Text("/")
                        TextField("脂肪", value: $item.fatGrams, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 52)
                        Text("/")
                        TextField("碳水", value: $item.carbGrams, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 52)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("估算依据：\(item.basis)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("不确定性提示：\(item.uncertainty)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private func requestCameraAndOpen() {
        cameraPermissionError = nil
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraPermissionError = "当前设备或模拟器无物理摄像头，请使用「相册多选」或点击下方示例图片按钮体验。"
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
                        cameraPermissionError = "未授予相机权限，请在系统设置中开启相机权限或改用相册选图。"
                    }
                }
            }
        default:
            cameraPermissionError = "相机权限已被拒绝或受限，请在系统「设置 → 隐私与安全性 → 相机」中允许「食刻」访问。"
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
        appState.showTemporaryBanner("已保存 \(selectedItems.count) 项食物（共 \(Int(totalAddedCalories.rounded())) kcal）")
        dismiss()
    }

    public static func makeSamplePlaceholderImageData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 240))
        let image = renderer.image { ctx in
            UIColor(red: 0.14, green: 0.52, blue: 0.34, alpha: 1.0).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
        }
        return image.jpegData(compressionQuality: 0.7) ?? Data()
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
