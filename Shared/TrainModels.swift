import Foundation

/// 時刻表の1便。
struct TrainDeparture: Hashable, Codable, Sendable {
    /// サービス日の0:00からの分数。0時台・1時台（終電）は 24:00 以降として持つ。
    let minutesFromMidnight: Int
    /// 凡例の記号（無印は nil）。
    let mark: String?
    let destination: String

    var hour: Int { minutesFromMidnight / 60 }
    var minute: Int { minutesFromMidnight % 60 }

    var timeText: String {
        String(format: "%d:%02d", displayHour, minute)
    }

    /// 表示用の時。25時表記にはせず、0〜23で出す。
    var displayHour: Int { hour % 24 }

    func date(on serviceDay: Date) -> Date? {
        let calendar = ToeiConfig.tokyoCalendar()
        var components = calendar.dateComponents([.year, .month, .day], from: serviceDay)
        components.hour = 0
        components.minute = 0
        components.second = 0
        guard let start = calendar.date(from: components) else { return nil }
        return start.addingTimeInterval(TimeInterval(minutesFromMidnight * 60))
    }
}

/// 1駅1方面の、平日または土曜・休日の表。
struct TimetableTable: Codable, Sendable, Equatable {
    var kind: ScheduleKind
    var caption: String
    var directionLabel: String
    var trains: [TrainDeparture]
    var defaultDestination: String
}

/// 駅×方面の時刻表（平日と土曜・休日をまとめて保持する）。
struct StationTimetable: Codable, Sendable, Equatable {
    var selectionID: String
    var weekday: TimetableTable?
    var saturday: TimetableTable?
    var holiday: TimetableTable?
    var directionLabel: String
    var fetchedOn: String

    var isEmpty: Bool { weekday == nil && saturday == nil && holiday == nil }

    func table(for kind: ScheduleKind) -> TimetableTable? {
        switch kind {
        case .weekday: return weekday
        case .saturday: return saturday
        case .holiday: return holiday
        }
    }
}

struct UpcomingTrains: Equatable, Sendable {
    var trains: [DatedTrain]
    var kind: ScheduleKind
    var isNextDay: Bool
}

struct DatedTrain: Equatable, Sendable {
    var departure: TrainDeparture
    var date: Date
}

/// 運行状況。Yahoo!路線情報の掲載に合わせる。
struct LineStatus: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        case normal
        case delayed
        case unknown
    }

    /// 取得からこの時間以上経った平常運転は、遅延の三角ではなく時計で「古い」と出す。
    static let staleInterval: TimeInterval = 10 * 60

    var line: LineID
    var kind: Kind
    var text: String
    var observedAt: Date

    func isStale(at now: Date) -> Bool {
        now.timeIntervalSince(observedAt) >= Self.staleInterval
    }

    /// 運行状況の横に出す SF Symbol。遅延・取得失敗は三角。平常運転の古いキャッシュは時計。
    /// `now` は Timeline の `entry.date` を渡す。View で `Date()` を見ると、先読みした entry が誤検知する。
    func warningSymbolName(at now: Date) -> String? {
        switch kind {
        case .delayed, .unknown:
            return "exclamationmark.triangle"
        case .normal:
            return isStale(at: now) ? "clock" : nil
        }
    }
}

enum TrainSnapshot {
    /// メニューバー・ウィジェット共通の「次発」表示用。時刻表からその場で計算する。
    static func remainingMinutes(until date: Date, now: Date) -> Int {
        Int(ceil(date.timeIntervalSince(now) / 60))
    }

    /// 残り時間の表示。60分以上は「296分」ではなく時間に換算する。
    static func remainingLabel(minutes: Int, compact: Bool) -> String {
        if minutes <= 0 { return "まもなく" }
        if minutes < 60 {
            return compact ? "\(minutes)分" : "\(minutes)分後"
        }
        let hours = minutes / 60
        let rest = minutes % 60
        if compact {
            return rest == 0 ? "\(hours)時間" : "\(hours)時間\(rest)分"
        }
        return rest == 0 ? "\(hours)時間後" : "\(hours)時間\(rest)分後"
    }

    /// ウィジェットが分数と次発の切り替わりを、拡張を起こさずに表示できる日時。
    /// macOS では Timeline を1件だけ返すと `.after` が来ず、表示が止まることがある。
    static func widgetTimelineDates(now: Date, departures: [Date], horizon: TimeInterval = 30 * 60, extra: [Date] = []) -> [Date] {
        let end = now.addingTimeInterval(horizon)
        var dates: [Date] = [now]
        for date in extra where date > now && date <= end {
            dates.append(date)
        }
        for departure in departures {
            guard departure > now else { continue }
            var minutes = remainingMinutes(until: departure, now: now)
            while minutes > 1 {
                let flip = departure.addingTimeInterval(-TimeInterval((minutes - 1) * 60))
                if flip > now && flip <= end {
                    dates.append(flip)
                }
                minutes -= 1
            }
            let after = departure.addingTimeInterval(1)
            if after <= end.addingTimeInterval(60) {
                dates.append(after)
            }
            if departure >= end { break }
        }
        let unique = Set(dates.map { Int($0.timeIntervalSince1970) })
        return unique.sorted().map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
}
