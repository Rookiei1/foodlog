import Foundation

public enum AIProviderKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case openAI = "openAI"
    case deepSeek = "deepSeek"
    case gemini = "gemini"
    case openAICompatible = "openAICompatible"
    case localMock = "localMock"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openAI: return "OpenAI GPT 系列"
        case .deepSeek: return "DeepSeek 系列"
        case .gemini: return "Google Gemini 系列"
        case .openAICompatible: return "OpenAI 兼容接口 (自定义)"
        case .localMock: return "内置离线演示 (Mock 无需密钥)"
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1"
        case .deepSeek: return "https://api.deepseek.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .openAICompatible: return "https://api.example.com/v1"
        case .localMock: return "local://mock-ai-provider"
        }
    }

    public var presetModels: [String] {
        switch self {
        case .openAI:
            return ["gpt-4o", "gpt-4o-mini", "gpt-4.1", "gpt-4.1-mini", "o3-mini"]
        case .deepSeek:
            return ["deepseek-flash", "deepseek-v4-pro", "deepseek-chat", "deepseek-reasoner"]
        case .gemini:
            return ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash"]
        case .openAICompatible:
            return ["qwen-vl-max", "qwen-plus", "claude-3-7-sonnet", "glm-4v-plus"]
        case .localMock:
            return ["foodlog-vision-mock-v1", "foodlog-text-only-mock"]
        }
    }

    public var requiresAPIKey: Bool {
        self != .localMock
    }
}

public struct AIProviderConfig: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: AIProviderKind
    public var baseURL: String
    public var modelName: String
    public var customModels: [String]
    public var supportsVisionOverride: Bool?
    public var timeoutSeconds: Double

    public init(
        id: UUID = UUID(),
        name: String,
        kind: AIProviderKind,
        baseURL: String? = nil,
        modelName: String? = nil,
        customModels: [String] = [],
        supportsVisionOverride: Bool? = nil,
        timeoutSeconds: Double = 45.0
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL ?? kind.defaultBaseURL
        self.modelName = modelName ?? (kind.presetModels.first ?? "gpt-4o-mini")
        self.customModels = customModels
        self.supportsVisionOverride = supportsVisionOverride
        self.timeoutSeconds = max(5.0, min(180.0, timeoutSeconds))
    }

    public var allSelectableModels: [String] {
        var combined = kind.presetModels
        for model in customModels where !combined.contains(model) {
            combined.append(model)
        }
        if !modelName.isEmpty && !combined.contains(modelName) {
            combined.insert(modelName, at: 0)
        }
        return combined
    }

    public var supportsVision: Bool {
        AIVisionCapabilityChecker.supportsVision(
            kind: kind,
            modelName: modelName,
            explicitOverride: supportsVisionOverride
        )
    }

    public static func defaultProviders() -> [AIProviderConfig] {
        [
            AIProviderConfig(
                id: UUID(uuidString: "11111111-2222-3333-4444-555555555503") ?? UUID(),
                name: "DeepSeek API",
                kind: .deepSeek,
                baseURL: "https://api.deepseek.com/v1",
                modelName: "deepseek-flash"
            ),
            AIProviderConfig(
                id: UUID(uuidString: "11111111-2222-3333-4444-555555555501") ?? UUID(),
                name: "内置离线演示 (Mock)",
                kind: .localMock,
                modelName: "foodlog-vision-mock-v1"
            )
        ]
    }
}

public enum AIVisionCapabilityChecker {
    /// Checks whether the selected model supports image recognition before sending any image payload.
    public static func supportsVision(
        kind: AIProviderKind,
        modelName: String,
        explicitOverride: Bool? = nil
    ) -> Bool {
        if let explicitOverride {
            return explicitOverride
        }
        let lower = modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }

        // flash is the primary vision model requested for DeepSeek
        if lower.contains("flash") {
            return true
        }

        // Known text-only models that must never receive image requests
        let textOnlyKeywords = [
            "deepseek-reasoner",
            "deepseek-coder",
            "gpt-3.5",
            "o1-mini",
            "o3-mini",
            "text-only",
            "qwen-turbo"
        ]
        if textOnlyKeywords.contains(where: { lower == $0 || lower.contains($0) }) && !lower.contains("vl") && !lower.contains("flash") {
            return false
        }

        switch kind {
        case .localMock:
            return !lower.contains("text-only")
        case .gemini:
            return lower.contains("gemini-1.5") || lower.contains("gemini-2") || lower.contains("vision") || lower.contains("pro") || lower.contains("flash")
        case .openAI:
            return lower.contains("gpt-4o") || lower.contains("gpt-4.1") || lower.contains("gpt-4-turbo") || lower.contains("vision") || lower.contains("gpt-4.5")
        case .deepSeek:
            return lower.contains("flash") || lower.contains("vl") || lower.contains("vision") || lower.contains("v4-pro") || lower.contains("v4")
        case .openAICompatible:
            let visionMarkers = ["flash", "vl", "vision", "4o", "4.1", "gemini", "claude-3", "pixtral", "llava", "qvq", "4v"]
            return visionMarkers.contains { lower.contains($0) }
        }
    }
}

public enum AIServiceError: LocalizedError, Equatable, Sendable {
    case missingAPIKey(providerName: String)
    case invalidBaseURL(String)
    case modelDoesNotSupportVision(modelName: String)
    case unauthorized(String)
    case insufficientQuota(String)
    case rateLimited(String)
    case timedOut
    case cancelled
    case networkUnavailable(String)
    case malformedJSON(String)
    case serverError(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "尚未配置「\(provider)」的 API Key，请前往「设置 → AI 供应商管理」填写并保存到 Keychain，或切换至「内置离线演示 (Mock)」。"
        case .invalidBaseURL(let url):
            return "API 地址格式无效：\(url)"
        case .modelDoesNotSupportVision(let model):
            return "当前模型「\(model)」不支持图片视觉输入（例如纯文本模型 deepseek-chat）。请切换为支持视觉的模型（如 deepseek-flash、deepseek-v4-pro、gemini-2.5-flash），或在供应商设置中开启视觉能力覆盖。"
        case .unauthorized(let detail):
            return "API 鉴权失败（401/403）：请检查 Keychain 中的 API Key 是否有效。\(detail)"
        case .insufficientQuota(let detail):
            return "API 账户余额不足或配额已用尽（402）：请充值或切换其他供应商。\(detail)"
        case .rateLimited(let detail):
            return "API 请求触发限流（429）：请稍后重试或切换其他模型。\(detail)"
        case .timedOut:
            return "AI 请求超时：请检查网络连接，或在设置中适当调高超时时间。"
        case .cancelled:
            return "已取消当前 AI 请求。"
        case .networkUnavailable(let detail):
            return "网络连接不可用：\(detail)。您依然可以正常使用手动记录与营养成分表换算功能。"
        case .malformedJSON(let reason):
            return "AI 返回的数据不是有效的结构化 JSON：\(reason)"
        case .serverError(let code, let message):
            return "AI 服务端异常（HTTP \(code)）：\(message)"
        }
    }
}

public enum AIJSONValidator {
    private struct RawRecognitionPayload: Decodable {
        var mealSummary: String?
        var deduplicationNote: String?
        var overallUncertaintyBanner: String?
        var items: [RawRecognitionItem]?
    }

    private struct RawRecognitionItem: Decodable {
        var name: String?
        var estimatedGrams: Double?
        var minGrams: Double?
        var maxGrams: Double?
        var calories: Double?
        var proteinGrams: Double?
        var fatGrams: Double?
        var carbGrams: Double?
        var sourceType: String?
        var packageNetWeightGrams: Double?
        var basis: String?
        var uncertainty: String?
    }

    private struct RawAnalysisPayload: Decodable {
        var estimationAndFluctuationDisclaimer: String?
        var calorieAndWeightAnalysis: String?
        var surplusEvaluation: String?
        var underEatingDaysReview: String?
        var dietStructureIssues: [String]?
        var nextWeekActionSuggestions: [String]?
        var weightGoalAdjustmentAdvice: String?
    }

    public static func extractJSONSubstring(from rawText: String) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fenceStart = trimmed.range(of: "```json"),
           let fenceEnd = trimmed.range(of: "```", range: fenceStart.upperBound..<trimmed.endIndex) {
            return String(trimmed[fenceStart.upperBound..<fenceEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let firstBrace = trimmed.firstIndex(of: "{"),
           let lastBrace = trimmed.lastIndex(of: "}"),
           firstBrace <= lastBrace {
            return String(trimmed[firstBrace...lastBrace])
        }
        return trimmed
    }

    public static func validateFoodRecognitionJSON(_ rawText: String) throws -> AIFoodRecognitionResponse {
        let cleaned = extractJSONSubstring(from: rawText)
        guard let data = cleaned.data(using: .utf8) else {
            throw AIServiceError.malformedJSON("无法编码为 UTF-8 数据")
        }

        let decoded: RawRecognitionPayload
        do {
            decoded = try JSONDecoder().decode(RawRecognitionPayload.self, from: data)
        } catch {
            throw AIServiceError.malformedJSON("JSON 解析失败：\(error.localizedDescription)")
        }

        guard let rawItems = decoded.items, !rawItems.isEmpty else {
            throw AIServiceError.malformedJSON("缺少有效 items 食物列表或列表为空")
        }

        var validatedItems: [AIFoodRecognizedItem] = []
        for raw in rawItems {
            let name = (raw.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw AIServiceError.malformedJSON("存在缺少名称的食物条目")
            }
            let grams = max(1.0, min(5000.0, raw.estimatedGrams ?? 100.0))
            let minG = raw.minGrams.map { max(1.0, min(grams, $0)) }
            let maxG = raw.maxGrams.map { max(grams, min(5000.0, $0)) }
            let kcal = max(0.0, min(10000.0, raw.calories ?? 0.0))
            let protein = max(0.0, min(1000.0, raw.proteinGrams ?? 0.0))
            let fat = max(0.0, min(1000.0, raw.fatGrams ?? 0.0))
            let carb = max(0.0, min(2000.0, raw.carbGrams ?? 0.0))
            let source: AIFoodSourceType = (raw.sourceType == "nutrition_label") ? .nutritionLabel : .visualEstimate
            let basis = (raw.basis ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let uncertainty = (raw.uncertainty ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            validatedItems.append(
                AIFoodRecognizedItem(
                    name: name,
                    estimatedGrams: (grams * 10).rounded() / 10,
                    minGrams: minG,
                    maxGrams: maxG,
                    calories: (kcal * 10).rounded() / 10,
                    proteinGrams: (protein * 10).rounded() / 10,
                    fatGrams: (fat * 10).rounded() / 10,
                    carbGrams: (carb * 10).rounded() / 10,
                    sourceType: source,
                    packageNetWeightGrams: raw.packageNetWeightGrams,
                    basis: basis.isEmpty ? "根据画面食物体积与常见烹饪方式估算" : basis,
                    uncertainty: uncertainty.isEmpty ? "视觉估算存在约 ±15% 分量与油脂波动，请核对后保存" : uncertainty
                )
            )
        }

        return AIFoodRecognitionResponse(
            mealSummary: decoded.mealSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? decoded.mealSummary!
                : "已分项识别 \(validatedItems.count) 种食物",
            deduplicationNote: decoded.deduplicationNote ?? "已对同一餐次的重复视角进行去重合并",
            overallUncertaintyBanner: decoded.overallUncertaintyBanner ?? "以下数据（除包装营养成分表外）属于 AI 视觉估算，已附带克数合理区间，请在确认或微调后保存。",
            items: validatedItems
        )
    }

    public static func validateComprehensiveAnalysisJSON(
        _ rawText: String,
        digest: ObjectiveDatasetDigest,
        providerName: String,
        modelName: String
    ) throws -> AIComprehensiveReport {
        let cleaned = extractJSONSubstring(from: rawText)
        guard let data = cleaned.data(using: .utf8) else {
            throw AIServiceError.malformedJSON("无法编码为 UTF-8 数据")
        }

        let decoded: RawAnalysisPayload
        do {
            decoded = try JSONDecoder().decode(RawAnalysisPayload.self, from: data)
        } catch {
            throw AIServiceError.malformedJSON("分析报告 JSON 解析失败：\(error.localizedDescription)")
        }

        guard let calorieAndWeight = decoded.calorieAndWeightAnalysis, !calorieAndWeight.isEmpty else {
            throw AIServiceError.malformedJSON("缺少热量与体重趋势关系分析字段")
        }

        let disclaimer = decoded.estimationAndFluctuationDisclaimer
            ?? "【客观与估算边界说明】本报告第一部分为数据库客观汇总；外卖及无标签食物的热量含 ±10%–20% 估算区间。短期 1–3 天内的体重上下波动主要反映体液水分、肌糖原储备及胃肠道内容物变化，不等同于确定的骨骼肌增长或纯脂肪堆积，请以 2–4 周的周均体重斜率为准。"

        return AIComprehensiveReport(
            spanTitle: digest.span.title,
            dateRangeText: "\(digest.startDayKey) ~ \(digest.endDayKey)",
            providerName: providerName,
            modelName: modelName,
            objectiveSummarySection: digest.promptReadyText,
            estimationAndFluctuationDisclaimer: disclaimer,
            calorieAndWeightAnalysis: calorieAndWeight,
            surplusEvaluation: decoded.surplusEvaluation ?? "请结合每日热量目标与周均体重变化率持续观察。",
            underEatingDaysReview: decoded.underEatingDaysReview ?? (digest.underEatingDayKeys.isEmpty ? "所选周期内已记录饮食日均达到目标热量的 85% 以上。" : "摄入偏低日期：\(digest.underEatingDayKeys.joined(separator: "、"))"),
            dietStructureIssues: (decoded.dietStructureIssues?.isEmpty == false) ? decoded.dietStructureIssues! : ["部分餐次蛋白质与复合碳水分布不够均衡"],
            nextWeekActionSuggestions: (decoded.nextWeekActionSuggestions?.isEmpty == false) ? decoded.nextWeekActionSuggestions! : ["保持每日晨起空腹称重，优先保证三餐规律摄入并利用加餐补齐热量差额"],
            weightGoalAdjustmentAdvice: decoded.weightGoalAdjustmentAdvice ?? "建议每周增重速度控制在 +0.20 至 +0.45 kg/周，若连续两周周均体重无变化可上调每日目标 +150~200 kcal。"
        )
    }
}
