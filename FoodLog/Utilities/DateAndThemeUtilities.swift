import Foundation
import SwiftUI
import UIKit

public enum DateKeyHelper {
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let readableDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 2026
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func date(fromDayKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        components.minute = 0
        return calendar.date(from: components)
    }

    public static func timeString(for date: Date) -> String {
        timeFormatter.string(from: date)
    }

    public static func shortDateString(for date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    public static func readableChineseDate(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) {
            return "今天 · " + readableDateFormatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "昨天 · " + readableDateFormatter.string(from: date)
        }
        return readableDateFormatter.string(from: date)
    }

    public static func shiftingDays(_ date: Date, by days: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    public static func combining(day: Date, withTimeFrom timeDate: Date, calendar: Calendar = .current) -> Date {
        let dayParts = calendar.dateComponents([.year, .month, .day], from: day)
        let timeParts = calendar.dateComponents([.hour, .minute, .second], from: timeDate)
        var merged = DateComponents()
        merged.year = dayParts.year
        merged.month = dayParts.month
        merged.day = dayParts.day
        merged.hour = timeParts.hour ?? 12
        merged.minute = timeParts.minute ?? 0
        merged.second = timeParts.second ?? 0
        return calendar.date(from: merged) ?? day
    }
}

public enum FoodLogTheme {
    public static let calorieGreen = Color(red: 0.13, green: 0.72, blue: 0.44)
    public static let proteinBlue = Color(red: 0.20, green: 0.54, blue: 0.96)
    public static let fatAmber = Color(red: 0.96, green: 0.62, blue: 0.16)
    public static let carbCoral = Color(red: 0.94, green: 0.38, blue: 0.35)
    public static let weightPurple = Color(red: 0.52, green: 0.36, blue: 0.94)

    public static func mealColor(for meal: MealType) -> Color {
        switch meal {
        case .breakfast: return Color(red: 0.96, green: 0.58, blue: 0.18)
        case .lunch: return Color(red: 0.13, green: 0.72, blue: 0.44)
        case .dinner: return Color(red: 0.36, green: 0.46, blue: 0.94)
        case .lateSnack: return Color(red: 0.62, green: 0.38, blue: 0.92)
        case .snack: return Color(red: 0.92, green: 0.38, blue: 0.52)
        }
    }
}

public struct MacroTagPill: View {
    public let prefix: String
    public let grams: Double
    public let color: Color

    public init(prefix: String, grams: Double, color: Color) {
        self.prefix = prefix
        self.grams = grams
        self.color = color
    }

    public var body: some View {
        HStack(spacing: 3) {
            Text(prefix)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text("\(Int(grams.rounded()))g")
                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(color.opacity(0.11))
        )
    }
}

public struct FoodThumbnailBadge: View {
    public let photoFilename: String?
    public let mealType: MealType
    public let size: CGFloat

    public init(photoFilename: String?, mealType: MealType, size: CGFloat = 44) {
        self.photoFilename = photoFilename
        self.mealType = mealType
        self.size = size
    }

    public var body: some View {
        if let filename = photoFilename,
           let uiImage = ImageStorageService.shared.loadImage(filename: filename) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        } else {
            let tint = FoodLogTheme.mealColor(for: mealType)
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.22), tint.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: mealType.systemImage)
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(tint)
                )
        }
    }
}

public struct SettingsIconLabel: View {
    public let title: String
    public let systemImage: String
    public let color: Color

    public init(_ title: String, systemImage: String, color: Color) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
    }

    public var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color.gradient)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                )
            Text(title)
                .foregroundStyle(.primary)
        }
    }
}
