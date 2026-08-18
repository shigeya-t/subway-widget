import XCTest

final class ToeiPageParserTests: XCTestCase {
    func testParsesWeekdayTimetableTimesAndDestinationMarks() throws {
        let table = try ToeiPageParser.parseTimetable(Self.fixture("yahoo_e17b_weekday"), kind: .weekday)
        XCTAssertEqual(table.kind, .weekday)
        XCTAssertEqual(table.directionLabel, "大門・六本木方面")
        XCTAssertEqual(table.defaultDestination, "光が丘")

        XCTAssertEqual(table.trains.first?.timeText, "5:06")
        XCTAssertEqual(table.trains.first?.destination, "光が丘")

        let last = table.trains.last
        XCTAssertEqual(last?.mark, "都")
        XCTAssertEqual(last?.destination, "都庁前")
        XCTAssertEqual(last?.minutesFromMidnight, 24 * 60 + 23)
    }

    func testParsesSaturdayAndHolidayCaptions() throws {
        let saturday = try ToeiPageParser.parseTimetable(Self.fixture("yahoo_e17b_saturday"), kind: .saturday)
        XCTAssertEqual(saturday.kind, .saturday)
        XCTAssertEqual(saturday.trains.first?.timeText, "5:06")

        let holiday = try ToeiPageParser.parseTimetable(Self.fixture("yahoo_e17b_holiday"), kind: .holiday)
        XCTAssertEqual(holiday.kind, .holiday)
        XCTAssertEqual(holiday.trains.first?.timeText, "5:06")
    }

    func testParsesDestinationCodesOnOppositeDirection() throws {
        let table = try ToeiPageParser.parseTimetable(Self.fixture("yahoo_e17a_weekday"), kind: .weekday)
        XCTAssertEqual(table.directionLabel, "両国・春日方面")

        let marked = table.trains.first { $0.hour == 8 && $0.minute == 30 }
        XCTAssertEqual(marked?.mark, "清")
        XCTAssertEqual(marked?.destination, "清澄白河")
    }

    func testParsesNormalOperationStatus() {
        let html = Self.fixture("yahoo_diainfo_normal")
        let statuses = ToeiPageParser.parseStatuses(html, observedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(statuses[.oedo]?.kind, .normal)
        XCTAssertEqual(statuses[.asakusa]?.kind, .normal)
        XCTAssertEqual(statuses[.oedo]?.text, "平常運転")
    }

    func testParsesDelayedAsakusaKeepsOthersNormal() {
        let html = Self.fixture("yahoo_diainfo_delayed")
        let statuses = ToeiPageParser.parseStatuses(html)
        XCTAssertEqual(statuses[.asakusa]?.kind, .delayed)
        XCTAssertEqual(statuses[.mita]?.kind, .normal)
        XCTAssertEqual(statuses[.oedo]?.kind, .normal)
        XCTAssertFalse(statuses[.asakusa]?.text.isEmpty ?? true)
    }

    private static func fixture(_ name: String) -> String {
        let url = Bundle(for: ToeiPageParserTests.self).url(forResource: name, withExtension: "html")
        XCTAssertNotNil(url, "missing fixture \(name).html")
        return try! String(contentsOf: url!, encoding: .utf8)
    }
}

final class CatalogAndURLTests: XCTestCase {
    func testDefaultStationIsKachidokiOedoTowardDaimon() {
        let key = SelectionKey.default
        let station = ToeiCatalog.station(line: key.line, code: key.stationCode)
        XCTAssertEqual(station?.name, "勝どき")
        XCTAssertEqual(key.direction, "B")
        XCTAssertEqual(station?.directionLabel("B"), "大門・六本木方面")
        XCTAssertEqual(station?.yahooStationID, 29339)
        XCTAssertEqual(station?.yahooGroupID(for: "B"), 7211)
    }

    func testTerminalsHaveOneDirection() {
        XCTAssertEqual(ToeiCatalog.station(line: .asakusa, code: "A01")?.directions, ["N"])
        XCTAssertEqual(ToeiCatalog.station(line: .asakusa, code: "A20")?.directions, ["S"])
        XCTAssertEqual(ToeiCatalog.station(line: .oedo, code: "E38")?.directions, ["A"])
        XCTAssertEqual(ToeiCatalog.station(line: .shinjuku, code: "S01")?.directions, ["E"])
        XCTAssertEqual(ToeiCatalog.station(line: .oedo, code: "E28")?.directions, ["A", "B", "C"])
    }

    func testTimetableURL() {
        let url = ToeiAPI.timetableURL(line: .oedo, stationCode: "E17", direction: "B", kind: .weekday)
        XCTAssertEqual(url?.absoluteString, "https://transit.yahoo.co.jp/timetable/29339/7211?kind=1")
        let holiday = ToeiAPI.timetableURL(line: .oedo, stationCode: "E17", direction: "B", kind: .holiday)
        XCTAssertEqual(holiday?.absoluteString, "https://transit.yahoo.co.jp/timetable/29339/7211?kind=4")
    }

    func testSelectionIDRoundTrip() {
        let key = SelectionKey(line: .mita, stationCode: "I05", direction: "N")
        XCTAssertEqual(ToeiCatalog.selection(from: key.id), key)
        XCTAssertEqual(ToeiCatalog.stations(on: .asakusa).count, 20)
        XCTAssertEqual(ToeiCatalog.stations(on: .oedo).count, 38)
    }

    func testResolvedKeyFallsBackWhenDirectionMissing() {
        var intent = SelectStationIntent()
        XCTAssertNil(intent.resolvedKey)

        let station = ToeiCatalog.station(line: .oedo, code: "E17")!
        intent.station = StationEntity(station)
        XCTAssertEqual(intent.resolvedKey?.stationCode, "E17")
        XCTAssertEqual(intent.resolvedKey?.direction, "A")

        intent.direction = DirectionEntity(
            key: SelectionKey(line: .oedo, stationCode: "E17", direction: "B"),
            name: station.directionLabel("B")
        )
        XCTAssertEqual(intent.resolvedKey, SelectionKey(line: .oedo, stationCode: "E17", direction: "B"))
    }
}

final class UpcomingTrainTests: XCTestCase {
    func testPicksTrainsAfterNowOnWeekday() throws {
        let table = try ToeiPageParser.parseTimetable(Self.fixture("yahoo_e17b_weekday"), kind: .weekday)
        let timetable = StationTimetable(
            selectionID: "oedo:E17:B",
            weekday: table,
            saturday: nil,
            holiday: nil,
            directionLabel: table.directionLabel,
            fetchedOn: "2026-08-17"
        )
        let monday = Self.date(year: 2026, month: 8, day: 17, hour: 8, minute: 0)
        let upcoming = TrainTime.upcoming(from: timetable, now: monday, holidays: [], limit: 4)
        XCTAssertEqual(upcoming?.isNextDay, false)
        XCTAssertEqual(upcoming?.kind, .weekday)
        XCTAssertEqual(upcoming?.trains.first?.departure.minute, 3)
        XCTAssertEqual(upcoming?.trains.count, 4)
    }

    func testUsesHolidayTableOnSunday() throws {
        let weekday = try ToeiPageParser.parseTimetable(Self.fixture("yahoo_e17b_weekday"), kind: .weekday)
        let holiday = try ToeiPageParser.parseTimetable(Self.fixture("yahoo_e17b_holiday"), kind: .holiday)
        let timetable = StationTimetable(
            selectionID: "oedo:E17:B",
            weekday: weekday,
            saturday: nil,
            holiday: holiday,
            directionLabel: holiday.directionLabel,
            fetchedOn: "2026-08-16"
        )
        let sunday = Self.date(year: 2026, month: 8, day: 16, hour: 8, minute: 0)
        let upcoming = TrainTime.upcoming(from: timetable, now: sunday, holidays: [], limit: 1)
        XCTAssertEqual(upcoming?.kind, .holiday)
        XCTAssertEqual(upcoming?.trains.first?.departure.minute, 6)
    }

    func testUsesSaturdayTableOnSaturday() throws {
        let weekday = try ToeiPageParser.parseTimetable(Self.fixture("yahoo_e17b_weekday"), kind: .weekday)
        let saturday = try ToeiPageParser.parseTimetable(Self.fixture("yahoo_e17b_saturday"), kind: .saturday)
        let timetable = StationTimetable(
            selectionID: "oedo:E17:B",
            weekday: weekday,
            saturday: saturday,
            holiday: nil,
            directionLabel: saturday.directionLabel,
            fetchedOn: "2026-08-15"
        )
        let day = Self.date(year: 2026, month: 8, day: 15, hour: 8, minute: 0)
        let upcoming = TrainTime.upcoming(from: timetable, now: day, holidays: [], limit: 1)
        XCTAssertEqual(upcoming?.kind, .saturday)
    }

    func testAfterLastTrainSwitchesToNextMorning() throws {
        let table = try ToeiPageParser.parseTimetable(Self.fixture("yahoo_e17b_weekday"), kind: .weekday)
        let holiday = try ToeiPageParser.parseTimetable(Self.fixture("yahoo_e17b_holiday"), kind: .holiday)
        let timetable = StationTimetable(
            selectionID: "oedo:E17:B",
            weekday: table,
            saturday: nil,
            holiday: holiday,
            directionLabel: table.directionLabel,
            fetchedOn: "2026-08-17"
        )
        let late = Self.date(year: 2026, month: 8, day: 18, hour: 1, minute: 30)
        let upcoming = TrainTime.upcoming(from: timetable, now: late, holidays: [], limit: 2)
        XCTAssertEqual(upcoming?.isNextDay, true)
        XCTAssertEqual(upcoming?.kind, .weekday)
        XCTAssertEqual(upcoming?.trains.first?.departure.timeText, "5:06")
    }

    func testHolidayOnWeekdayUsesHolidayTable() {
        let kind = ScheduleKind.kind(
            for: Self.date(year: 2026, month: 7, day: 20, hour: 10, minute: 0),
            holidays: ["2026-07-20"]
        )
        XCTAssertEqual(kind, .holiday)
        XCTAssertEqual(
            ScheduleKind.kind(for: Self.date(year: 2026, month: 7, day: 21, hour: 10, minute: 0), holidays: ["2026-07-20"]),
            .weekday
        )
    }

    func testWidgetTimelineDatesFlipEachRemainingMinute() {
        let now = Self.date(year: 2026, month: 8, day: 17, hour: 22, minute: 0)
        let first = now.addingTimeInterval(3 * 60)
        let second = now.addingTimeInterval(8 * 60)
        let dates = TrainSnapshot.widgetTimelineDates(now: now, departures: [first, second], horizon: 10 * 60)

        XCTAssertEqual(dates.first, now)
        XCTAssertTrue(dates.contains(now.addingTimeInterval(60)))
        XCTAssertTrue(dates.contains(now.addingTimeInterval(2 * 60)))
        XCTAssertTrue(dates.contains(first.addingTimeInterval(1)))
        XCTAssertGreaterThan(dates.count, 1)
        XCTAssertEqual(TrainSnapshot.remainingMinutes(until: first, now: dates[1]), 2)
    }

    func testRemainingLabelUsesHoursWhenOverOneHour() {
        XCTAssertEqual(TrainSnapshot.remainingLabel(minutes: 0, compact: true), "まもなく")
        XCTAssertEqual(TrainSnapshot.remainingLabel(minutes: 3, compact: true), "3分")
        XCTAssertEqual(TrainSnapshot.remainingLabel(minutes: 3, compact: false), "3分後")
        XCTAssertEqual(TrainSnapshot.remainingLabel(minutes: 60, compact: true), "1時間")
        XCTAssertEqual(TrainSnapshot.remainingLabel(minutes: 75, compact: true), "1時間15分")
        XCTAssertEqual(TrainSnapshot.remainingLabel(minutes: 296, compact: true), "4時間56分")
        XCTAssertEqual(TrainSnapshot.remainingLabel(minutes: 296, compact: false), "4時間56分後")
    }

    private static func fixture(_ name: String) -> String {
        let url = Bundle(for: ToeiPageParserTests.self).url(forResource: name, withExtension: "html")!
        return try! String(contentsOf: url, encoding: .utf8)
    }

    private static func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        let calendar = ToeiConfig.tokyoCalendar()
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }
}
