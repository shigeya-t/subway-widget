import Foundation

/// タイムゾーンと Yahoo!路線情報のホスト。型名の Toei は当初都営専用だった名残。
enum ToeiConfig {
    static let timeZone = TimeZone(identifier: "Asia/Tokyo")!
    static let yahooHost = "transit.yahoo.co.jp"
    static let statusURL = URL(string: "https://transit.yahoo.co.jp/diainfo/area/4")!

    static func statusURL(for line: LineID) -> URL {
        statusURL(yahooDiaInfoID: line.yahooDiaInfoID)
    }

    static func statusURL(yahooDiaInfoID: Int) -> URL {
        URL(string: "https://\(yahooHost)/diainfo/\(yahooDiaInfoID)/0")!
    }

    static func isYahooStatusURL(_ url: URL) -> Bool {
        url.host == yahooHost && url.path.hasPrefix("/diainfo/")
    }

    /// 終電帯を翌日の暦日へまたがせて扱う境界。0〜2時は前日ダイヤの続きとみなす。
    static let serviceDayRolloverHour = 3

    static func tokyoCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = tokyoCalendar()
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func scheduleHeading(kind: ScheduleKind, isNextDay: Bool) -> String {
        isNextDay ? "翌 \(kind.label)ダイヤ" : kind.label
    }
}

enum ScheduleKind: String, Codable, Sendable {
    case weekday
    case saturday
    case holiday

    var label: String {
        switch self {
        case .weekday: return "平日"
        case .saturday: return "土曜"
        case .holiday: return "日曜・祝日"
        }
    }

    /// Yahoo!路線情報の `kind` クエリ。
    var yahooKind: Int {
        switch self {
        case .weekday: return 1
        case .saturday: return 2
        case .holiday: return 4
        }
    }

    /// 曜日と祝日一覧からダイヤ区分を決める。通信はしない。
    static func kind(for date: Date, holidays: Set<String>) -> ScheduleKind {
        let calendar = ToeiConfig.tokyoCalendar()
        let weekday = calendar.component(.weekday, from: date) // 1=日, 7=土
        if weekday == 7 { return .saturday }
        if weekday == 1 || holidays.contains(ToeiConfig.dateString(date)) { return .holiday }
        return .weekday
    }
}
