import Foundation
import SwiftData

public enum WeightSlot: String, CaseIterable, Codable, Identifiable, Sendable {
    case morningFasting = "morningFasting"
    case postMeal = "postMeal"
    case evening = "evening"
    case other = "other"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .morningFasting: return "晨起空腹"
        case .postMeal: return "餐后"
        case .evening: return "睡前"
        case .other: return "其他"
        }
    }
}

public enum DailyRepresentativeRule: String, CaseIterable, Codable, Identifiable, Sendable {
    case morningFastingFirst = "morningFastingFirst"
    case lowestOfDay = "lowestOfDay"
    case latestOfDay = "latestOfDay"
    case averageOfDay = "averageOfDay"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .morningFastingFirst: return "晨起空腹优先（推荐）"
        case .lowestOfDay: return "当日最低体重"
        case .latestOfDay: return "当日最新一次"
        case .averageOfDay: return "当日多次平均值"
        }
    }

    public var explanation: String {
        switch self {
        case .morningFastingFirst:
            return "若当天有标记「手动代表值」或「晨起空腹」记录则优先采用，否则采用当天最早一次称重。"
        case .lowestOfDay:
            return "同一天多次称重时，取当日最低值参与趋势统计。"
        case .latestOfDay:
            return "同一天多次称重时，取时间最晚的一次参与趋势统计。"
        case .averageOfDay:
            return "同一天多次称重时，取算术平均值参与趋势统计。"
        }
    }
}

public enum WeightRangeFilter: String, CaseIterable, Identifiable, Sendable {
    case days7 = "days7"
    case days30 = "days30"
    case days90 = "days90"
    case custom = "custom"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .days7: return "7天"
        case .days30: return "30天"
        case .days90: return "90天"
        case .custom: return "自定义"
        }
    }
}

public struct WeightRecordSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var measuredAt: Date
    public var dayKey: String
    public var weightKg: Double
    public var slot: WeightSlot
    public var isRepresentativeOverride: Bool
    public var note: String

    public init(
        id: UUID = UUID(),
        measuredAt: Date = Date(),
        dayKey: String? = nil,
        weightKg: Double,
        slot: WeightSlot = .morningFasting,
        isRepresentativeOverride: Bool = false,
        note: String = ""
    ) {
        self.id = id
        self.measuredAt = measuredAt
        self.dayKey = dayKey ?? DateKeyHelper.dayKey(for: measuredAt)
        self.weightKg = max(20.0, min(350.0, (weightKg * 100).rounded() / 100))
        self.slot = slot
        self.isRepresentativeOverride = isRepresentativeOverride
        self.note = note
    }
}

@Model
public final class WeightRecord {
    @Attribute(.unique) public var id: UUID
    public var measuredAt: Date
    public var dayKey: String
    public var weightKg: Double
    public var slotRaw: String
    public var isRepresentativeOverride: Bool
    public var note: String

    public var slot: WeightSlot {
        get { WeightSlot(rawValue: slotRaw) ?? .morningFasting }
        set { slotRaw = newValue.rawValue }
    }

    public init(snapshot: WeightRecordSnapshot) {
        self.id = snapshot.id
        self.measuredAt = snapshot.measuredAt
        self.dayKey = snapshot.dayKey
        self.weightKg = snapshot.weightKg
        self.slotRaw = snapshot.slot.rawValue
        self.isRepresentativeOverride = snapshot.isRepresentativeOverride
        self.note = snapshot.note
    }

    public func update(from snapshot: WeightRecordSnapshot) {
        self.measuredAt = snapshot.measuredAt
        self.dayKey = DateKeyHelper.dayKey(for: snapshot.measuredAt)
        self.weightKg = snapshot.weightKg
        self.slotRaw = snapshot.slot.rawValue
        self.isRepresentativeOverride = snapshot.isRepresentativeOverride
        self.note = snapshot.note
    }

    public var snapshot: WeightRecordSnapshot {
        WeightRecordSnapshot(
            id: id,
            measuredAt: measuredAt,
            dayKey: dayKey,
            weightKg: weightKg,
            slot: slot,
            isRepresentativeOverride: isRepresentativeOverride,
            note: note
        )
    }
}

public struct DailyWeightPoint: Codable, Equatable, Identifiable, Sendable {
    public var id: String { dayKey }
    public var dayKey: String
    public var date: Date
    public var weightKg: Double
    public var sampleCount: Int
    public var ruleUsed: DailyRepresentativeRule
    public var rolling7DayAverageKg: Double?
}

public struct WeeklyWeightAverage: Codable, Equatable, Identifiable, Sendable {
    public var id: String { weekLabel }
    public var weekLabel: String
    public var startDate: Date
    public var endDate: Date
    public var averageKg: Double
    public var deltaFromPreviousWeekKg: Double?
    public var sampleDays: Int
}

public struct WeightTrendSummary: Codable, Equatable, Sendable {
    public var dailyPoints: [DailyWeightPoint]
    public var weeklyAverages: [WeeklyWeightAverage]
    public var latestWeightKg: Double?
    public var startWeightKg: Double?
    public var totalChangeKg: Double?
    public var weeklyRateKg: Double?
    public var minWeightKg: Double?
    public var maxWeightKg: Double?
}
