import Foundation

enum TrainTime {
    /// ウィジェットは通信しないため、App が保存した祝日一覧を渡す。
    static func upcoming(
        from timetable: StationTimetable,
        now: Date,
        holidays: Set<String>,
        limit: Int
    ) -> UpcomingTrains? {
        let calendar = ToeiConfig.tokyoCalendar()
        let serviceDay = Self.serviceDay(for: now, calendar: calendar)
        let todayKind = ScheduleKind.kind(for: serviceDay, holidays: holidays)
        if let today = trains(from: timetable, kind: todayKind, on: serviceDay, after: now, limit: limit), !today.isEmpty {
            return UpcomingTrains(trains: today, kind: todayKind, isNextDay: false)
        }
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: serviceDay) else { return nil }
        let nextKind = ScheduleKind.kind(for: nextDay, holidays: holidays)
        let next = trains(from: timetable, kind: nextKind, on: nextDay, after: nil, limit: limit) ?? []
        return UpcomingTrains(trains: next, kind: nextKind, isNextDay: true)
    }

    static func serviceDay(for now: Date, calendar: Calendar = ToeiConfig.tokyoCalendar()) -> Date {
        let hour = calendar.component(.hour, from: now)
        if hour < ToeiConfig.serviceDayRolloverHour {
            return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) ?? now
        }
        return calendar.startOfDay(for: now)
    }

    private static func trains(
        from timetable: StationTimetable,
        kind: ScheduleKind,
        on day: Date,
        after: Date?,
        limit: Int
    ) -> [DatedTrain]? {
        guard let table = timetable.table(for: kind) else { return nil }
        var result: [DatedTrain] = []
        for train in table.trains {
            guard let date = train.date(on: day) else { continue }
            if let after, date <= after { continue }
            result.append(DatedTrain(departure: train, date: date))
            if result.count >= limit { break }
        }
        return result
    }
}
