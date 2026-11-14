import Foundation
import SwiftUI

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
    public static let calorieGreen = Color(red: 0.15, green: 0.74, blue: 0.45)
    public static let proteinBlue = Color(red: 0.20, green: 0.56, blue: 0.96)
    public static let fatAmber = Color(red: 0.96, green: 0.64, blue: 0.18)
    public static let carbCoral = Color(red: 0.95, green: 0.39, blue: 0.36)
    public static let weightPurple = Color(red: 0.55, green: 0.38, blue: 0.94)
}
