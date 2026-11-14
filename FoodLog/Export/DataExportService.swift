import Foundation
import SwiftData
import UIKit

public struct BundledPhotoItem: Codable, Equatable, Sendable {
    public var filename: String
    public var base64JPEG: String
}

public struct FoodLogFullBackupDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = "1.0"

    public var schemaVersion: String
    public var appName: String
    public var appVersion: String
    public var exportedAt: Date
    public var includesPhotos: Bool
    public var profileSettings: UserProfileSettings
    public var foodEntries: [FoodEntrySnapshot]
    public var favoriteFoods: [FavoriteFoodSnapshot]
    public var weightRecords: [WeightRecordSnapshot]
    public var savedAnalysisReports: [AIComprehensiveReport]
    public var bundledPhotos: [BundledPhotoItem]?

    public init(
        schemaVersion: String = Self.currentSchemaVersion,
        appName: String = "食刻 FoodLog",
        appVersion: String = "1.0.0",
        exportedAt: Date = Date(),
        includesPhotos: Bool = false,
        profileSettings: UserProfileSettings,
        foodEntries: [FoodEntrySnapshot],
        favoriteFoods: [FavoriteFoodSnapshot],
        weightRecords: [WeightRecordSnapshot],
        savedAnalysisReports: [AIComprehensiveReport],
        bundledPhotos: [BundledPhotoItem]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.appName = appName
        self.appVersion = appVersion
        self.exportedAt = exportedAt
        self.includesPhotos = includesPhotos
        self.profileSettings = profileSettings
        self.foodEntries = foodEntries
        self.favoriteFoods = favoriteFoods
        self.weightRecords = weightRecords
        self.savedAnalysisReports = savedAnalysisReports
        self.bundledPhotos = bundledPhotos
    }
}

public struct BackupRestoreSummary: Equatable, Sendable {
    public var schemaVersion: String
    public var importedFoodsCount: Int
    public var importedFavoritesCount: Int
    public var importedWeightsCount: Int
    public var importedReportsCount: Int
    public var restoredPhotosCount: Int
}

public enum DataExportError: LocalizedError, Equatable {
    case unsupportedSchemaVersion(String)
    case corruptedBackupFile(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "不支持的备份文件版本：\(version)"
        case .corruptedBackupFile(let reason):
            return "备份文件损坏或格式不合法：\(reason)"
        }
    }
}

public enum DataExportService {
    private static func escapeCSV(_ value: String) -> String {
        let cleaned = value.replacingOccurrences(of: "\"", with: "\"\"")
        if cleaned.contains(",") || cleaned.contains("\n") || cleaned.contains("\"") {
            return "\"\(cleaned)\""
        }
        return cleaned
    }

    /// Exports all food entries as UTF-8 CSV (with UTF-8 BOM for Excel/Numbers compatibility).
    public static func exportFoodEntriesCSV(entries: [FoodEntrySnapshot]) -> Data {
        let sorted = entries.sorted { $0.eatenAt > $1.eatenAt }
        var lines: [String] = [
            "记录ID,日期,时间,餐次,食物名称,重量(g),最小估算(g),最大估算(g),热量(kcal),蛋白质(g),脂肪(g),碳水化合物(g),来源类型,AI分析依据,不确定性提示,用户备注"
        ]
        for item in sorted {
            let minG = item.estimatedMinGrams.map { String(format: "%.0f", $0) } ?? ""
            let maxG = item.estimatedMaxGrams.map { String(format: "%.0f", $0) } ?? ""
            let sourceLabel = item.isFromNutritionLabel ? "营养成分表" : "常规/视觉估算"
            let row = [
                item.id.uuidString,
                item.dayKey,
                DateKeyHelper.timeString(for: item.eatenAt),
                item.mealType.title,
                escapeCSV(item.name),
                String(format: "%.1f", item.grams),
                minG,
                maxG,
                String(format: "%.1f", item.calories),
                String(format: "%.1f", item.proteinGrams),
                String(format: "%.1f", item.fatGrams),
                String(format: "%.1f", item.carbGrams),
                sourceLabel,
                escapeCSV(item.aiAnalysisBasis),
                escapeCSV(item.uncertaintyNote),
                escapeCSV(item.userNote)
            ].joined(separator: ",")
            lines.append(row)
        }
        let body = lines.joined(separator: "\r\n") + "\r\n"
        var data = Data([0xEF, 0xBB, 0xBF]) // UTF-8 BOM
        data.append(Data(body.utf8))
        return data
    }

    /// Exports all weight records as UTF-8 CSV (with UTF-8 BOM).
    public static func exportWeightRecordsCSV(records: [WeightRecordSnapshot]) -> Data {
        let sorted = records.sorted { $0.measuredAt > $1.measuredAt }
        var lines: [String] = [
            "记录ID,日期,时间,称重时段,体重(kg),手动指定代表值,备注"
        ]
        for item in sorted {
            let row = [
                item.id.uuidString,
                item.dayKey,
                DateKeyHelper.timeString(for: item.measuredAt),
                item.slot.title,
                String(format: "%.2f", item.weightKg),
                item.isRepresentativeOverride ? "是" : "否",
                escapeCSV(item.note)
            ].joined(separator: ",")
            lines.append(row)
        }
        let body = lines.joined(separator: "\r\n") + "\r\n"
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(body.utf8))
        return data
    }

    /// Exports full structured JSON backup. By default excludes photos and NEVER includes API Keys.
    public static func exportFullBackupJSON(
        profile: UserProfileSettings,
        foodEntries: [FoodEntrySnapshot],
        favoriteFoods: [FavoriteFoodSnapshot],
        weightRecords: [WeightRecordSnapshot],
        savedReports: [AIComprehensiveReport],
        includePhotos: Bool = false,
        imageStorage: ImageStorageService = .shared
    ) throws -> Data {
        var photoBundle: [BundledPhotoItem]? = nil
        if includePhotos {
            let allFilenames = Set(foodEntries.flatMap(\.photoFilenames))
            var collected: [BundledPhotoItem] = []
            for filename in allFilenames.sorted() {
                if let raw = imageStorage.loadPhotoData(filename: filename) {
                    collected.append(BundledPhotoItem(filename: filename, base64JPEG: raw.base64EncodedString()))
                }
            }
            photoBundle = collected
        }

        let document = FoodLogFullBackupDocument(
            includesPhotos: includePhotos,
            profileSettings: profile,
            foodEntries: foodEntries.sorted { $0.eatenAt < $1.eatenAt },
            favoriteFoods: favoriteFoods.sorted { $0.name < $1.name },
            weightRecords: weightRecords.sorted { $0.measuredAt < $1.measuredAt },
            savedAnalysisReports: savedReports.sorted { $0.createdAt < $1.createdAt },
            bundledPhotos: photoBundle
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    public static func decodeBackupDocument(from data: Data) throws -> FoodLogFullBackupDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let doc: FoodLogFullBackupDocument
        do {
            doc = try decoder.decode(FoodLogFullBackupDocument.self, from: data)
        } catch {
            throw DataExportError.corruptedBackupFile(error.localizedDescription)
        }
        guard doc.schemaVersion == "1.0" else {
            throw DataExportError.unsupportedSchemaVersion(doc.schemaVersion)
        }
        return doc
    }

    @MainActor
    public static func restoreBackup(
        from data: Data,
         into context: ModelContext,
        imageStorage: ImageStorageService = .shared
    ) throws -> (BackupRestoreSummary, UserProfileSettings) {
        let doc = try decodeBackupDocument(from: data)

        let existingFoodIDs = Set(((try? context.fetch(FetchDescriptor<FoodEntryRecord>())) ?? []).map(\.id))
        let existingFavIDs = Set(((try? context.fetch(FetchDescriptor<FavoriteFoodTemplate>())) ?? []).map(\.id))
        let existingWeightIDs = Set(((try? context.fetch(FetchDescriptor<WeightRecord>())) ?? []).map(\.id))
        let existingReportIDs = Set(((try? context.fetch(FetchDescriptor<SavedAnalysisReportRecord>())) ?? []).map(\.id))

        var addedFoods = 0
        for item in doc.foodEntries where !existingFoodIDs.contains(item.id) {
            context.insert(FoodEntryRecord(snapshot: item))
            addedFoods += 1
        }

        var addedFavs = 0
        for fav in doc.favoriteFoods where !existingFavIDs.contains(fav.id) {
            context.insert(FavoriteFoodTemplate(snapshot: fav))
            addedFavs += 1
        }

        var addedWeights = 0
        for weight in doc.weightRecords where !existingWeightIDs.contains(weight.id) {
            context.insert(WeightRecord(snapshot: weight))
            addedWeights += 1
        }

        var addedReports = 0
        for report in doc.savedAnalysisReports where !existingReportIDs.contains(report.id) {
            context.insert(SavedAnalysisReportRecord(report: report))
            addedReports += 1
        }

        var restoredPhotos = 0
        if let photos = doc.bundledPhotos {
            for item in photos {
                if let rawData = Data(base64Encoded: item.base64JPEG),
                   (try? imageStorage.saveRawPhotoData(rawData, preferredFilename: item.filename)) != nil {
                    restoredPhotos += 1
                }
            }
        }

        try context.save()
        let summary = BackupRestoreSummary(
            schemaVersion: doc.schemaVersion,
            importedFoodsCount: addedFoods,
            importedFavoritesCount: addedFavs,
            importedWeightsCount: addedWeights,
            importedReportsCount: addedReports,
            restoredPhotosCount: restoredPhotos
        )
        return (summary, doc.profileSettings)
    }

    /// Generates a formatted A4 Chinese PDF analysis report using UIGraphicsPDFRenderer.
    public static func renderAnalysisReportPDF(report: AIComprehensiveReport) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4 at 72 DPI
        let margin: CGFloat = 42.0
        let contentWidth = pageRect.width - margin * 2

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            var yOffset: CGFloat = margin

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .bold),
                .foregroundColor: UIColor(red: 0.08, green: 0.42, blue: 0.26, alpha: 1.0)
            ]
            let metaAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10.5, weight: .regular),
                .foregroundColor: UIColor.darkGray
            ]
            let sectionAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13.5, weight: .semibold),
                .foregroundColor: UIColor(red: 0.10, green: 0.32, blue: 0.20, alpha: 1.0)
            ]
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4.0
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11.0, weight: .regular),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraphStyle
            ]

            func drawBlock(_ text: String, attributes: [NSAttributedString.Key: Any], spacingAfter: CGFloat) {
                let attrString = NSAttributedString(string: text, attributes: attributes)
                let bounding = attrString.boundingRect(
                    with: CGSize(width: contentWidth, height: 4000),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                let neededHeight = ceil(bounding.height)
                if yOffset + neededHeight > pageRect.height - margin {
                    ctx.beginPage()
                    yOffset = margin
                }
                attrString.draw(in: CGRect(x: margin, y: yOffset, width: contentWidth, height: neededHeight))
                yOffset += neededHeight + spacingAfter
            }

            drawBlock("食刻 FoodLog · AI 饮食与体重分析报告", attributes: titleAttrs, spacingAfter: 6)
            let metaLine = "统计范围：\(report.spanTitle)（\(report.dateRangeText)）  |  分析模型：\(report.providerName) (\(report.modelName))  |  日期：\(DateKeyHelper.dayKey(for: report.createdAt))"
            drawBlock(metaLine, attributes: metaAttrs, spacingAfter: 16)

            let sections: [(String, String)] = [
                ("一、客观统计数据（基于本机数据库真实记录）", report.objectiveSummarySection),
                ("二、估算数据与体重短期波动边界说明", report.estimationAndFluctuationDisclaimer),
                ("三、平均热量、蛋白质与体重变化趋势关系", report.calorieAndWeightAnalysis),
                ("四、热量盈余 / 目标达成度评估", report.surplusEvaluation),
                ("五、摄入不足日期复盘", report.underEatingDaysReview),
                ("六、当前饮食结构存在的问题", report.dietStructureIssues.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")),
                ("七、下一周饮食执行建议", report.nextWeekActionSuggestions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")),
                ("八、针对目标的调整建议", report.weightGoalAdjustmentAdvice)
            ]

            for (heading, content) in sections {
                drawBlock(heading, attributes: sectionAttrs, spacingAfter: 5)
                drawBlock(content, attributes: bodyAttrs, spacingAfter: 14)
            }
        }
    }

    public static func writeTemporaryExportFile(data: Data, filename: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FoodLogExports", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }
}
