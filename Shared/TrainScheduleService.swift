import Foundation

enum TrainScheduleService {
    private static let cache = ScheduleCache()

    static func fetchTimetable(for key: SelectionKey, force: Bool = false) async throws -> StationTimetable {
        if !force, let cached = await cache.value(for: key) {
            return cached
        }
        if !force, let stored = AppSettings.schedule(selectionID: key.id), stored.fetchedOn == ToeiConfig.dateString(Date()) {
            await cache.store(stored, for: key)
            return stored
        }

        async let weekdayHTML = ToeiAPI.fetchTimetableHTML(
            line: key.line, stationCode: key.stationCode, direction: key.direction, kind: .weekday
        )
        async let saturdayHTML = ToeiAPI.fetchTimetableHTML(
            line: key.line, stationCode: key.stationCode, direction: key.direction, kind: .saturday
        )
        async let holidayHTML = ToeiAPI.fetchTimetableHTML(
            line: key.line, stationCode: key.stationCode, direction: key.direction, kind: .holiday
        )

        let weekday = try ToeiPageParser.parseTimetable(await weekdayHTML, kind: .weekday)
        let saturday = try ToeiPageParser.parseTimetable(await saturdayHTML, kind: .saturday)
        let holiday = try ToeiPageParser.parseTimetable(await holidayHTML, kind: .holiday)
        let timetable = StationTimetable(
            selectionID: key.id,
            weekday: weekday,
            saturday: saturday,
            holiday: holiday,
            directionLabel: weekday.directionLabel,
            fetchedOn: ToeiConfig.dateString(Date())
        )
        await cache.store(timetable, for: key)
        return timetable
    }
}

private actor ScheduleCache {
    private var values: [String: (StationTimetable, Date)] = [:]

    func value(for key: SelectionKey) -> StationTimetable? {
        guard let entry = values[key.id] else { return nil }
        if ToeiConfig.dateString(entry.1) != ToeiConfig.dateString(Date()) { return nil }
        return entry.0
    }

    func store(_ timetable: StationTimetable, for key: SelectionKey) {
        values[key.id] = (timetable, Date())
    }
}
