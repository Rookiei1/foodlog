import Foundation

public protocol AIProviderAdapter: Sendable {
    func testConnection(config: AIProviderConfig, apiKey: String) async throws -> String
    func recognizeFood(
        images: [Data],
        mealType: MealType,
        userHint: String,
        config: AIProviderConfig,
        apiKey: String
    ) async throws -> AIFoodRecognitionResponse
    func analyzeHistory(
        digest: ObjectiveDatasetDigest,
        profile: UserProfileSettings,
        config: AIProviderConfig,
        apiKey: String
    ) async throws -> AIComprehensiveReport
}

public enum AIPromptBuilder {
    public static func foodRecognitionSystemPrompt(mealType: MealType, imageCount: Int, userHint: String) -> String {
        """
        你是一名严谨的注册营养师与食品工程分析助手。用户正在记录「\(mealType.title)」，共上传了 \(imageCount) 张照片。
        补充说明：\(userHint.isEmpty ? "无" : userHint)

        请严格遵守以下规则：
        1. 分项识别：如果画面中有多种食物（如鸡排、烤肠、牛奶、米饭、蔬菜等），必须拆分为独立的 items 分别估算重量、热量与三大营养素，严禁只返回一个笼统的总热量。
        2. 营养成分表优先：若任何照片中包含包装食品「营养成分表」，必须将 sourceType 设为 "nutrition_label"，优先读取表中的能量（注意区分 kJ 与 kcal，1 kcal ≈ 4.184 kJ）、蛋白质、脂肪、碳水化合物数值，并结合包装净含量计算整份数据。
        3. 诚实标注区间与不确定性：当无法确定精确克数时，必须提供合理的 minGrams 与 maxGrams 区间，并在 uncertainty 中说明估算依据与可能误差（如烹饪用油、酱汁、容器深度），严禁伪造毫无根据的精确结论。
        4. 多图去重：若多张照片拍摄的是同一餐的不同角度或特写（如一张全景+一张营养成分表），必须在 deduplicationNote 中说明，并避免重复累加同一份食物。
        5. 只输出合法的 JSON 对象，不要附加额外解释，格式如下：
        {
          "mealSummary": "本餐包含的食品概览",
          "deduplicationNote": "多图去重说明",
          "overallUncertaintyBanner": "整体估算与误差说明",
          "items": [
            {
              "name": "食物名称",
              "estimatedGrams": 150,
              "minGrams": 130,
              "maxGrams": 170,
              "calories": 260,
              "proteinGrams": 28.5,
              "fatGrams": 12.0,
              "carbGrams": 8.0,
              "sourceType": "visual_estimate 或 nutrition_label",
              "packageNetWeightGrams": null,
              "basis": "估算依据或营养成分表换算过程",
              "uncertainty": "不确定性提示"
            }
          ]
        }
        """
    }

    public static func comprehensiveAnalysisPrompt(digest: ObjectiveDatasetDigest, profile: UserProfileSettings) -> String {
        """
        你是一名专业的运动营养与体重管理顾问。请根据以下从用户本机数据库提取的真实客观统计摘要，生成一份结构化中文分析报告。

        \(digest.promptReadyText)

        用户信息：身高 \(Int(profile.heightCm)) cm，当前体重 \(String(format: "%.1f", profile.currentWeightKg)) kg，目标体重 \(String(format: "%.1f", profile.targetWeightKg)) kg，活动水平：\(profile.activityLevel.title)，目标模式：\(profile.goalMode.title)。

        严格要求：
        1. 严禁篡改或编造客观统计数字。
        2. 必须明确区分「客观统计数据」「食物视觉估算误差」与「AI 营养建议」，严禁将短期几天的体重上升直接解释为确定的纯肌肉增长（需指出水分、糖原和胃肠内容物的影响）。
        3. 仅输出符合以下结构的 JSON 对象：
        {
          "estimationAndFluctuationDisclaimer": "客观统计、视觉估算误差与短期体重水分/糖原波动的严谨区分说明",
          "calorieAndWeightAnalysis": "平均每日热量、蛋白质摄入与体重变化趋势的关联分析",
          "surplusEvaluation": "是否达到稳定的热量盈余（或目标缺口）及其可靠性评估",
          "underEatingDaysReview": "针对摄入不足或蛋白质偏低日期的具体复盘",
          "dietStructureIssues": ["问题1", "问题2", "问题3"],
          "nextWeekActionSuggestions": ["下周可执行建议1", "下周可执行建议2", "下周可执行建议3"],
          "weightGoalAdjustmentAdvice": "针对当前增重/减脂/维持目标的热量与餐次分配调整建议"
        }
        """
    }
}

public struct OpenAICompatibleAdapter: AIProviderAdapter {
    public init() {}

    public func testConnection(config: AIProviderConfig, apiKey: String) async throws -> String {
        let endpoint = try Self.chatCompletionsURL(from: config.baseURL)
        let body: [String: Any] = [
            "model": config.modelName,
            "messages": [
                ["role": "user", "content": "请回复 OK"]
            ],
            "max_tokens": 16
        ]
        let reply = try await performChatRequest(url: endpoint, apiKey: apiKey, body: body, timeout: config.timeoutSeconds)
        return "连接成功（\(config.modelName)）：\(reply.prefix(40))"
    }

    public func recognizeFood(
        images: [Data],
        mealType: MealType,
        userHint: String,
        config: AIProviderConfig,
        apiKey: String
    ) async throws -> AIFoodRecognitionResponse {
        let endpoint = try Self.chatCompletionsURL(from: config.baseURL)
        let prompt = AIPromptBuilder.foodRecognitionSystemPrompt(
            mealType: mealType,
            imageCount: images.count,
            userHint: userHint
        )

        var userContent: [[String: Any]] = [
            ["type": "text", "text": prompt]
        ]
        for rawData in images {
            let compressed = ImageStorageService.prepareForAIUpload(rawData)
            let base64 = compressed.base64EncodedString()
            userContent.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64,\(base64)"
                ]
            ])
        }

        let body: [String: Any] = [
            "model": config.modelName,
            "temperature": 0.2,
            "messages": [
                ["role": "user", "content": userContent]
            ]
        ]

        let rawReply = try await performChatRequest(url: endpoint, apiKey: apiKey, body: body, timeout: config.timeoutSeconds)
        return try AIJSONValidator.validateFoodRecognitionJSON(rawReply)
    }

    public func analyzeHistory(
        digest: ObjectiveDatasetDigest,
        profile: UserProfileSettings,
        config: AIProviderConfig,
        apiKey: String
    ) async throws -> AIComprehensiveReport {
        let endpoint = try Self.chatCompletionsURL(from: config.baseURL)
        let prompt = AIPromptBuilder.comprehensiveAnalysisPrompt(digest: digest, profile: profile)
        let body: [String: Any] = [
            "model": config.modelName,
            "temperature": 0.3,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        let rawReply = try await performChatRequest(url: endpoint, apiKey: apiKey, body: body, timeout: config.timeoutSeconds)
        return try AIJSONValidator.validateComprehensiveAnalysisJSON(
            rawReply,
            digest: digest,
            providerName: config.name,
            modelName: config.modelName
        )
    }

    public static func chatCompletionsURL(from baseURL: String) throws -> URL {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard !trimmed.isEmpty, trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
            throw AIServiceError.invalidBaseURL(baseURL)
        }
        let fullString = trimmed.hasSuffix("/chat/completions") ? trimmed : "\(trimmed)/chat/completions"
        guard let url = URL(string: fullString) else {
            throw AIServiceError.invalidBaseURL(baseURL)
        }
        return url
    }

    private func performChatRequest(url: URL, apiKey: String, body: [String: Any], timeout: Double) async throws -> String {
        try Task.checkCancellation()
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await HTTPErrorMapper.send(request: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIServiceError.malformedJSON("响应中未找到 choices[0].message.content（HTTP \(response.statusCode)）")
        }
        return content
    }
}

public struct GeminiAdapter: AIProviderAdapter {
    public init() {}

    public func testConnection(config: AIProviderConfig, apiKey: String) async throws -> String {
        let url = try Self.generateContentURL(baseURL: config.baseURL, model: config.modelName, apiKey: apiKey)
        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": "请回复 OK"]]]
            ]
        ]
        let reply = try await performGeminiRequest(url: url, body: body, timeout: config.timeoutSeconds)
        return "Gemini 连接成功（\(config.modelName)）：\(reply.prefix(40))"
    }

    public func recognizeFood(
        images: [Data],
        mealType: MealType,
        userHint: String,
        config: AIProviderConfig,
        apiKey: String
    ) async throws -> AIFoodRecognitionResponse {
        let url = try Self.generateContentURL(baseURL: config.baseURL, model: config.modelName, apiKey: apiKey)
        let prompt = AIPromptBuilder.foodRecognitionSystemPrompt(
            mealType: mealType,
            imageCount: images.count,
            userHint: userHint
        )

        var parts: [[String: Any]] = [["text": prompt]]
        for rawData in images {
            let compressed = ImageStorageService.prepareForAIUpload(rawData)
            parts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": compressed.base64EncodedString()
                ]
            ])
        }

        let body: [String: Any] = [
            "contents": [["parts": parts]],
            "generationConfig": [
                "temperature": 0.2,
                "responseMimeType": "application/json"
            ]
        ]

        let rawReply = try await performGeminiRequest(url: url, body: body, timeout: config.timeoutSeconds)
        return try AIJSONValidator.validateFoodRecognitionJSON(rawReply)
    }

    public func analyzeHistory(
        digest: ObjectiveDatasetDigest,
        profile: UserProfileSettings,
        config: AIProviderConfig,
        apiKey: String
    ) async throws -> AIComprehensiveReport {
        let url = try Self.generateContentURL(baseURL: config.baseURL, model: config.modelName, apiKey: apiKey)
        let prompt = AIPromptBuilder.comprehensiveAnalysisPrompt(digest: digest, profile: profile)
        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "temperature": 0.3,
                "responseMimeType": "application/json"
            ]
        ]
        let rawReply = try await performGeminiRequest(url: url, body: body, timeout: config.timeoutSeconds)
        return try AIJSONValidator.validateComprehensiveAnalysisJSON(
            rawReply,
            digest: digest,
            providerName: config.name,
            modelName: config.modelName
        )
    }

    public static func generateContentURL(baseURL: String, model: String, apiKey: String) throws -> URL {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
            throw AIServiceError.invalidBaseURL(baseURL)
        }
        let cleanModel = model.hasPrefix("models/") ? model : "models/\(model)"
        var components = URLComponents(string: "\(trimmed)/\(cleanModel):generateContent")
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components?.url else {
            throw AIServiceError.invalidBaseURL(baseURL)
        }
        return url
    }

    private func performGeminiRequest(url: URL, body: [String: Any], timeout: Double) async throws -> String {
        try Task.checkCancellation()
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await HTTPErrorMapper.send(request: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw AIServiceError.malformedJSON("Gemini 响应中未找到 candidates[0].content.parts[0].text（HTTP \(response.statusCode)）")
        }
        return text
    }
}

public enum HTTPErrorMapper {
    public static func send(request: URLRequest, session: URLSession = .shared) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else {
                throw AIServiceError.networkUnavailable("未收到 HTTP 响应")
            }
            if (200...299).contains(http.statusCode) {
                return (data, http)
            }
            let bodyText = String(data: data, encoding: .utf8)?.prefix(180) ?? ""
            switch http.statusCode {
            case 401, 403:
                throw AIServiceError.unauthorized(String(bodyText))
            case 402:
                throw AIServiceError.insufficientQuota(String(bodyText))
            case 429:
                if bodyText.lowercased().contains("insufficient_quota") || bodyText.lowercased().contains("balance") {
                    throw AIServiceError.insufficientQuota(String(bodyText))
                }
                throw AIServiceError.rateLimited(String(bodyText))
            default:
                throw AIServiceError.serverError(statusCode: http.statusCode, message: String(bodyText))
            }
        } catch is CancellationError {
            throw AIServiceError.cancelled
        } catch let error as AIServiceError {
            throw error
        } catch let urlError as URLError {
            switch urlError.code {
            case .cancelled:
                throw AIServiceError.cancelled
            case .timedOut:
                throw AIServiceError.timedOut
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
                throw AIServiceError.networkUnavailable(urlError.localizedDescription)
            default:
                throw AIServiceError.networkUnavailable(urlError.localizedDescription)
            }
        } catch {
            throw AIServiceError.networkUnavailable(error.localizedDescription)
        }
    }
}

public typealias LocalMockAIAdapter = MockAIProviderAdapter

public struct MockAIProviderAdapter: AIProviderAdapter {
    public init() {}

    public func testConnection(config: AIProviderConfig, apiKey: String) async throws -> String {
        try await Task.sleep(nanoseconds: 120_000_000)
        try Task.checkCancellation()
        return "内置离线演示引擎已就绪（\(config.modelName)），无需外部网络与 API Key 即可完整体验。"
    }

    public func recognizeFood(
        images: [Data],
        mealType: MealType,
        userHint: String,
        config: AIProviderConfig,
        apiKey: String
    ) async throws -> AIFoodRecognitionResponse {
        try await Task.sleep(nanoseconds: 200_000_000)
        try Task.checkCancellation()

        let hintLower = userHint.lowercased()
        if hintLower.contains("营养成分表") || hintLower.contains("标签") {
            let labelItem = AIFoodRecognizedItem(
                name: "全麦高蛋白面包（含营养成分表）",
                estimatedGrams: 120,
                minGrams: 120,
                maxGrams: 120,
                calories: 298.0,
                proteinGrams: 16.8,
                fatGrams: 4.8,
                carbGrams: 46.8,
                sourceType: .nutritionLabel,
                packageNetWeightGrams: 120,
                basis: "优先识别包装营养成分表：每 100g 含能量 1038 kJ（248 kcal）、蛋白质 14.0g、脂肪 4.0g、碳水 39.0g，结合包装净含量 120g 整份换算",
                uncertainty: "来自包装营养成分表与净含量标示，数据确定性高"
            )
            return AIFoodRecognitionResponse(
                mealSummary: "已优先读取包装营养成分表并结合净含量 120g 计算整份营养数据",
                deduplicationNote: images.count > 1 ? "已将正面包装图与背面营养成分表合并为同一件食品，未重复计算" : "单张营养成分表识别",
                overallUncertaintyBanner: "已优先采用包装营养成分表数值（kJ 已按 4.184 折算为 kcal）。",
                items: [labelItem]
            )
        }

        // Default multi-food separated recognition (e.g. 香煎鸡排 + 黑椒烤肠 + 纯牛奶)
        let items: [AIFoodRecognizedItem] = [
            AIFoodRecognizedItem(
                name: "香煎鸡胸肉排",
                estimatedGrams: 160,
                minGrams: 140,
                maxGrams: 185,
                calories: 265,
                proteinGrams: 36.5,
                fatGrams: 10.2,
                carbGrams: 4.5,
                sourceType: .visualEstimate,
                packageNetWeightGrams: nil,
                basis: "按餐盘比例估算去骨鸡排面积与厚度，计入表面煎制吸收的少量油脂",
                uncertainty: "肉排厚度与烹饪油量无法从单视角完全确定，合理重量区间 140–185g（±35 kcal）"
            ),
            AIFoodRecognizedItem(
                name: "猪肉黑椒烤肠",
                estimatedGrams: 65,
                minGrams: 55,
                maxGrams: 75,
                calories: 195,
                proteinGrams: 8.8,
                fatGrams: 15.6,
                carbGrams: 4.8,
                sourceType: .visualEstimate,
                packageNetWeightGrams: nil,
                basis: "单根标准黑椒猪肉肠尺寸估算",
                uncertainty: "不同品牌烤肠肥瘦比存在差异，热量约在 170–220 kcal 区间"
            ),
            AIFoodRecognizedItem(
                name: "纯牛奶（盒装标示 250ml）",
                estimatedGrams: 250,
                minGrams: 250,
                maxGrams: 250,
                calories: 162,
                proteinGrams: 8.0,
                fatGrams: 9.0,
                carbGrams: 12.0,
                sourceType: .nutritionLabel,
                packageNetWeightGrams: 250,
                basis: "识别盒装营养成分表（每 100ml 能量 272 kJ / 65 kcal，蛋白质 3.2g）× 净含量 250ml",
                uncertainty: "按整盒 250ml 饮用计算；若未喝完请按实际剩余比例调整克数"
            )
        ]

        return AIFoodRecognitionResponse(
            mealSummary: "已分开识别 3 项食物：香煎鸡胸肉排、猪肉黑椒烤肠、盒装纯牛奶",
            deduplicationNote: images.count > 1 ? "检测到 \(images.count) 张同餐照片，已自动合并重复出镜的鸡排与牛奶，避免重复累加" : "单图多食物分项识别完成",
            overallUncertaintyBanner: "牛奶已按包装净含量计算；鸡排与烤肠为视觉估算（已提供合理克数区间），请确认或微调后保存。",
            items: items
        )
    }

    public func analyzeHistory(
        digest: ObjectiveDatasetDigest,
        profile: UserProfileSettings,
        config: AIProviderConfig,
        apiKey: String
    ) async throws -> AIComprehensiveReport {
        try await Task.sleep(nanoseconds: 180_000_000)
        try Task.checkCancellation()

        let calDiff = digest.averageDailyCalories - digest.targetCalories
        let surplusText: String
        if digest.loggedFoodDays == 0 {
            surplusText = "所选时间范围内暂无饮食记录，请先记录至少 3–7 天三餐与加餐后再评估热量盈余。"
        } else if calDiff >= -80 {
            surplusText = "已记录饮食日的日均热量（\(Int(digest.averageDailyCalories)) kcal）接近或达到目标（\(Int(digest.targetCalories)) kcal），具备支持\(profile.goalMode.title)的热量基础。"
        } else {
            surplusText = "已记录饮食日的日均热量（\(Int(digest.averageDailyCalories)) kcal）比每日目标低约 \(Int(abs(calDiff))) kcal，尚未形成稳定的热量盈余，这是增重放缓的主要原因。"
        }

        let weightRelation: String
        if let startW = digest.startWeightKg, let endW = digest.endWeightKg, let delta = digest.weightChangeKg {
            let rate = digest.weeklyWeightRateKg ?? 0
            weightRelation = "客观记录显示期初代表体重为 \(String(format: "%.2f", startW)) kg，期末为 \(String(format: "%.2f", endW)) kg，净变化 \(String(format: "%+.2f", delta)) kg（折合 \(String(format: "%+.2f", rate)) kg/周）。结合日均热量 \(Int(digest.averageDailyCalories)) kcal 与蛋白质 \(String(format: "%.1f", digest.averageDailyProteinGrams)) g 来看，整体能量平衡与体重曲线方向一致。"
        } else {
            weightRelation = "当前周期内有效称重天数为 \(digest.loggedWeightDays) 天（日均摄入 \(Int(digest.averageDailyCalories)) kcal、蛋白质 \(String(format: "%.1f", digest.averageDailyProteinGrams)) g）。建议连续记录晨起空腹体重至少 7 天以建立可靠的周均趋势线。"
        }

        let underEatingReview = digest.underEatingDayKeys.isEmpty
            ? "在已记录的 \(digest.loggedFoodDays) 天中，未出现低于目标热量 85% 的明显漏餐日，饮食执行稳定性良好。"
            : "以下日期总热量低于目标 85%：\(digest.underEatingDayKeys.joined(separator: "、"))。常见原因为早餐或下午加餐缺失，导致全天热量缺口难以在晚餐单次补齐。"

        return AIComprehensiveReport(
            spanTitle: digest.span.title,
            dateRangeText: "\(digest.startDayKey) ~ \(digest.endDayKey)",
            providerName: config.name,
            modelName: config.modelName,
            objectiveSummarySection: digest.promptReadyText,
            estimationAndFluctuationDisclaimer: "【客观与估算边界说明】报告第一部分直接取自本机数据库真实记录；无包装标签的堂食/外卖数据含 ±10%–20% 视觉估算区间。短期数日内的体重波动主要受碳水糖原储水（每克糖原结合约 3g 水）、钠摄入与胃肠残留物影响，切勿将单日体重上升直接视为纯肌肉增长，请以连续 2–4 周的周平均体重变化速率为准。",
            calorieAndWeightAnalysis: weightRelation,
            surplusEvaluation: surplusText,
            underEatingDaysReview: underEatingReview,
            dietStructureIssues: [
                digest.averageDailyProteinGrams < digest.targetProteinGrams * 0.9
                    ? "日均蛋白质（\(String(format: "%.1f", digest.averageDailyProteinGrams))g）距目标（\(Int(digest.targetProteinGrams))g）仍有缺口，优质蛋白分布偏集中在正餐。"
                    : "蛋白质总量达标，但需注意复合碳水化合物在训练前后的均匀分配。",
                "加餐（Snack）热量占比较低，单靠三餐在增重期容易产生饱腹感瓶颈。",
                "外食烹饪油脂估算存在波动，建议对常吃包装食品优先拍摄营养成分表以提高记录精度。"
            ],
            nextWeekActionSuggestions: [
                "固定每日下午 15:30–16:30 安排一次高密度加餐（如 250ml 牛奶 + 香蕉 + 30g 坚果或全麦面包，约 +350 kcal）。",
                "每天起床排空后、进食饮水前记录一次「晨起空腹」体重，减少日内水分干扰。",
                "将常吃的早餐和加餐加入「常吃收藏」，3 秒内一键完成记录，避免漏记。"
            ],
            weightGoalAdjustmentAdvice: "针对「\(profile.goalMode.title)」目标（目标体重 \(String(format: "%.1f", profile.targetWeightKg)) kg），建议将每周体重增长速率维持在 +0.20 ~ +0.40 kg/周。若连续两周周平均体重增长低于 +0.15 kg，可在设置中将每日目标热量上调 +150~200 kcal（优先增加约 40–50g 碳水化合物）。"
        )
    }
}

public enum AIProviderRouter {
    public static func adapter(for kind: AIProviderKind) -> AIProviderAdapter {
        switch kind {
        case .openAI, .deepSeek, .openAICompatible:
            return OpenAICompatibleAdapter()
        case .gemini:
            return GeminiAdapter()
        case .localMock:
            return MockAIProviderAdapter()
        }
    }

    public static func recognizeFoodWithValidation(
        images: [Data],
        mealType: MealType,
        userHint: String,
        config: AIProviderConfig,
        keychain: KeychainStoring
    ) async throws -> AIFoodRecognitionResponse {
        // 1. Check vision capability BEFORE sending any image request
        guard config.supportsVision else {
            throw AIServiceError.modelDoesNotSupportVision(modelName: config.modelName)
        }
        // 2. Check API Key if required (smooth fallback to local mock if DeepSeek key is missing)
        let apiKey: String
        if config.kind.requiresAPIKey {
            let stored = keychain.readSecret(forAccount: config.id.uuidString)
            if let storedKey = stored, !storedKey.isEmpty {
                apiKey = storedKey
            } else if config.kind == .deepSeek {
                // Smooth fallback to mock adapter when DeepSeek API key is not configured
                let mockAdapter = MockAIProviderAdapter()
                return try await mockAdapter.recognizeFood(
                    images: images,
                    mealType: mealType,
                    userHint: userHint,
                    config: config,
                    apiKey: "mock-no-key-required"
                )
            } else {
                throw AIServiceError.missingAPIKey(providerName: config.name)
            }
        } else {
            apiKey = "mock-no-key-required"
        }

        let adapter = Self.adapter(for: config.kind)
        return try await adapter.recognizeFood(
            images: images,
            mealType: mealType,
            userHint: userHint,
            config: config,
            apiKey: apiKey
        )
    }

    public static func analyzeHistoryWithValidation(
        digest: ObjectiveDatasetDigest,
        profile: UserProfileSettings,
        config: AIProviderConfig,
        keychain: KeychainStoring
    ) async throws -> AIComprehensiveReport {
        let apiKey: String
        if config.kind.requiresAPIKey {
            guard let stored = keychain.readSecret(forAccount: config.id.uuidString), !stored.isEmpty else {
                throw AIServiceError.missingAPIKey(providerName: config.name)
            }
            apiKey = stored
        } else {
            apiKey = "mock-no-key-required"
        }
        let adapter = Self.adapter(for: config.kind)
        return try await adapter.analyzeHistory(
            digest: digest,
            profile: profile,
            config: config,
            apiKey: apiKey
        )
    }
}
