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
        XCTAssertEqual(statuses[.ginza]?.kind, .normal)
        XCTAssertEqual(statuses[.fukutoshin]?.kind, .normal)
        XCTAssertEqual(statuses[.oedo]?.text, "平常運転")
    }

    func testParsesDelayedAsakusaKeepsOthersNormal() {
        let html = Self.fixture("yahoo_diainfo_delayed")
        let statuses = ToeiPageParser.parseStatuses(html)
        XCTAssertEqual(statuses[.asakusa]?.kind, .delayed)
        XCTAssertEqual(statuses[.mita]?.kind, .normal)
        XCTAssertEqual(statuses[.oedo]?.kind, .normal)
        XCTAssertEqual(statuses[.ginza]?.kind, .normal)
        XCTAssertFalse(statuses[.asakusa]?.text.isEmpty ?? true)
    }

    func testNormalStatusShowsClockWhenEntryDateIsStaleNotTriangle() {
        let observed = Date(timeIntervalSince1970: 1_000_000)
        let statuses = ToeiPageParser.parseStatuses(Self.fixture("yahoo_diainfo_normal"), observedAt: observed)
        let status = statuses[.oedo]
        XCTAssertEqual(status?.text, "平常運転")
        XCTAssertNil(status?.warningSymbolName(at: observed))
        XCTAssertNil(status?.warningSymbolName(at: observed.addingTimeInterval(10 * 60 - 1)))
        XCTAssertEqual(status?.warningSymbolName(at: observed.addingTimeInterval(10 * 60)), "clock")
        XCTAssertNotEqual(status?.warningSymbolName(at: observed.addingTimeInterval(11 * 60)), "exclamationmark.triangle")
    }

    func testDelayedAndUnknownStatusShowWarningRegardlessOfAge() {
        let observed = Date(timeIntervalSince1970: 1_000_000)
        let delayed = ToeiPageParser.parseStatuses(Self.fixture("yahoo_diainfo_delayed"), observedAt: observed)
        let later = observed.addingTimeInterval(30 * 60)
        XCTAssertEqual(delayed[.asakusa]?.warningSymbolName(at: later), "exclamationmark.triangle")
        XCTAssertEqual(delayed[.oedo]?.warningSymbolName(at: later), "clock")

        let unknown = LineStatus(line: .oedo, kind: .unknown, text: "運行状況を取得できません", observedAt: observed)
        XCTAssertEqual(unknown.warningSymbolName(at: later), "exclamationmark.triangle")
    }

    private static func fixture(_ name: String) -> String {
        let url = Bundle(for: ToeiPageParserTests.self).url(forResource: name, withExtension: "html")
        XCTAssertNotNil(url, "missing fixture \(name).html")
        return try! String(contentsOf: url!, encoding: .utf8)
    }
}

final class CatalogAndURLTests: XCTestCase {
    func testDefaultStationIsMarunouchiTokyoTowardIkebukuro() {
        let key = SelectionKey.default
        let station = ToeiCatalog.station(line: key.line, code: key.stationCode)
        XCTAssertEqual(station?.name, "東京")
        XCTAssertEqual(key.line, .marunouchi)
        XCTAssertEqual(key.direction, "E")
        XCTAssertEqual(station?.directionLabel("E"), "池袋・茗荷谷方面")
        XCTAssertEqual(station?.yahooStationID, 22828)
        XCTAssertEqual(station?.yahooGroupID(for: "E"), 3280)
    }

    func testTerminalsHaveOneDirection() {
        XCTAssertEqual(ToeiCatalog.station(line: .asakusa, code: "A01")?.directions, ["N"])
        XCTAssertEqual(ToeiCatalog.station(line: .asakusa, code: "A20")?.directions, ["S"])
        XCTAssertEqual(ToeiCatalog.station(line: .oedo, code: "E38")?.directions, ["A"])
        XCTAssertEqual(ToeiCatalog.station(line: .shinjuku, code: "S01")?.directions, ["E"])
        XCTAssertEqual(ToeiCatalog.station(line: .oedo, code: "E28")?.directions, ["A", "B", "C"])
    }

    func testLineStatusURL() {
        XCTAssertEqual(
            ToeiConfig.statusURL(for: .asakusa).absoluteString,
            "https://transit.yahoo.co.jp/diainfo/128/0"
        )
        XCTAssertEqual(
            ToeiConfig.statusURL(for: .fukutoshin).absoluteString,
            "https://transit.yahoo.co.jp/diainfo/540/0"
        )
        XCTAssertEqual(OpenLineStatusIntent(line: .fukutoshin).lineID, LineID.fukutoshin.rawValue)
    }

    func testTimetableURL() {
        let url = ToeiAPI.timetableURL(line: .oedo, stationCode: "E17", direction: "B", kind: .weekday)
        XCTAssertEqual(url?.absoluteString, "https://transit.yahoo.co.jp/timetable/29339/7211?kind=1")
        let holiday = ToeiAPI.timetableURL(line: .oedo, stationCode: "E17", direction: "B", kind: .holiday)
        XCTAssertEqual(holiday?.absoluteString, "https://transit.yahoo.co.jp/timetable/29339/7211?kind=4")
    }

    func testMetroGinzaTimetableURL() {
        let station = ToeiCatalog.station(line: .ginza, code: "G09")
        XCTAssertEqual(station?.name, "銀座")
        XCTAssertEqual(station?.yahooStationID, 22641)
        XCTAssertEqual(station?.yahooGroupID(for: "N"), 3270)
        XCTAssertEqual(station?.directionLabel("N"), "浅草・上野方面")
        let url = ToeiAPI.timetableURL(line: .ginza, stationCode: "G09", direction: "N", kind: .weekday)
        XCTAssertEqual(url?.absoluteString, "https://transit.yahoo.co.jp/timetable/22641/3270?kind=1")
    }

    func testMetroMarunouchiShinjukuIsSeparateFromToeiShinjuku() {
        let metro = ToeiCatalog.station(line: .marunouchi, code: "M08")
        let toei = ToeiCatalog.station(line: .shinjuku, code: "S01")
        XCTAssertEqual(metro?.name, "新宿")
        XCTAssertEqual(metro?.yahooStationID, 29342)
        XCTAssertEqual(toei?.yahooStationID, 22741)
        XCTAssertNotEqual(metro?.yahooStationID, toei?.yahooStationID)
    }

    func testMetroCatalogCountsAndNumbering() {
        XCTAssertEqual(LineID.lines(of: .toei).count, 4)
        XCTAssertEqual(LineID.lines(of: .metro).count, 9)
        XCTAssertEqual(ToeiCatalog.stations(on: .ginza).count, 19)
        XCTAssertEqual(ToeiCatalog.stations(on: .marunouchi).count, 28)
        XCTAssertEqual(ToeiCatalog.stations(on: .hibiya).count, 22)
        XCTAssertEqual(ToeiCatalog.stations(on: .tozai).count, 23)
        XCTAssertEqual(ToeiCatalog.stations(on: .chiyoda).count, 20)
        XCTAssertEqual(ToeiCatalog.stations(on: .yurakucho).count, 24)
        XCTAssertEqual(ToeiCatalog.stations(on: .hanzomon).count, 14)
        XCTAssertEqual(ToeiCatalog.stations(on: .namboku).count, 19)
        XCTAssertEqual(ToeiCatalog.stations(on: .fukutoshin).count, 16)
        XCTAssertEqual(ToeiCatalog.station(line: .ginza, code: "G01")?.numbering, "G-01")
        XCTAssertEqual(ToeiCatalog.station(line: .marunouchi, code: "m04")?.numbering, "m-04")
        XCTAssertEqual(ToeiCatalog.station(line: .ginza, code: "G01")?.directions, ["N"])
        XCTAssertEqual(ToeiCatalog.station(line: .ginza, code: "G19")?.directions, ["S"])
        XCTAssertEqual(ToeiCatalog.station(line: .marunouchi, code: "M06")?.directions, ["E", "W", "B"])
        XCTAssertEqual(ToeiCatalog.station(line: .yurakucho, code: "Y01")?.directions, ["E"])
        XCTAssertEqual(ToeiCatalog.station(line: .fukutoshin, code: "F16")?.directions, ["N"])
    }

    func testYurakuchoAndFukutoshinShareWakoshiToHikawadaiThenSplit() {
        let yWakoshi = ToeiCatalog.station(line: .yurakucho, code: "Y01")
        let fWakoshi = ToeiCatalog.station(line: .fukutoshin, code: "F01")
        XCTAssertEqual(yWakoshi?.name, "和光市")
        XCTAssertEqual(fWakoshi?.name, "和光市")
        XCTAssertEqual(yWakoshi?.yahooStationID, 22171)
        XCTAssertEqual(fWakoshi?.yahooStationID, 22171)
        XCTAssertEqual(yWakoshi?.yahooGroupID(for: "E"), 3341)
        XCTAssertEqual(fWakoshi?.yahooGroupID(for: "S"), 3341)
        XCTAssertEqual(
            ToeiAPI.timetableURL(line: .yurakucho, stationCode: "Y01", direction: "E", kind: .weekday)?.absoluteString,
            "https://transit.yahoo.co.jp/timetable/22171/3341?kind=1"
        )
        XCTAssertEqual(
            ToeiAPI.timetableURL(line: .fukutoshin, stationCode: "F01", direction: "S", kind: .weekday)?.absoluteString,
            "https://transit.yahoo.co.jp/timetable/22171/3341?kind=1"
        )

        let yHikawa = ToeiCatalog.station(line: .yurakucho, code: "Y05")
        let fHikawa = ToeiCatalog.station(line: .fukutoshin, code: "F05")
        XCTAssertEqual(yHikawa?.name, "氷川台")
        XCTAssertEqual(yHikawa?.yahooStationID, fHikawa?.yahooStationID)
        XCTAssertEqual(yHikawa?.yahooGroupID(for: "E"), 3341)
        XCTAssertEqual(fHikawa?.yahooGroupID(for: "S"), 3341)

        let yKotake = ToeiCatalog.station(line: .yurakucho, code: "Y06")
        let fKotake = ToeiCatalog.station(line: .fukutoshin, code: "F06")
        XCTAssertEqual(yKotake?.name, "小竹向原")
        XCTAssertEqual(yKotake?.yahooStationID, 22679)
        XCTAssertEqual(fKotake?.yahooStationID, 22679)
        XCTAssertEqual(yKotake?.yahooGroupID(for: "E"), 3341)
        XCTAssertEqual(fKotake?.yahooGroupID(for: "S"), 3371)
        XCTAssertEqual(
            ToeiAPI.timetableURL(line: .yurakucho, stationCode: "Y06", direction: "E", kind: .weekday)?.absoluteString,
            "https://transit.yahoo.co.jp/timetable/22679/3341?kind=1"
        )
        XCTAssertEqual(
            ToeiAPI.timetableURL(line: .fukutoshin, stationCode: "F06", direction: "S", kind: .weekday)?.absoluteString,
            "https://transit.yahoo.co.jp/timetable/22679/3371?kind=1"
        )

        let ySenkawa = ToeiCatalog.station(line: .yurakucho, code: "Y07")
        let fSenkawa = ToeiCatalog.station(line: .fukutoshin, code: "F07")
        XCTAssertEqual(ySenkawa?.name, "千川")
        XCTAssertEqual(ySenkawa?.yahooGroupID(for: "E"), 3341)
        XCTAssertEqual(ySenkawa?.yahooGroupID(for: "W"), 3340)
        XCTAssertEqual(fSenkawa?.yahooGroupID(for: "N"), 3370)
        XCTAssertEqual(fSenkawa?.yahooGroupID(for: "S"), 3371)
        XCTAssertEqual(
            ToeiAPI.timetableURL(line: .fukutoshin, stationCode: "F07", direction: "N", kind: .weekday)?.absoluteString,
            "https://transit.yahoo.co.jp/timetable/22774/3370?kind=1"
        )
        XCTAssertEqual(
            ToeiAPI.timetableURL(line: .fukutoshin, stationCode: "F07", direction: "S", kind: .weekday)?.absoluteString,
            "https://transit.yahoo.co.jp/timetable/22774/3371?kind=1"
        )
    }

    func testSelectionIDRoundTrip() {
        let key = SelectionKey(line: .mita, stationCode: "I05", direction: "N")
        XCTAssertEqual(ToeiCatalog.selection(from: key.id), key)
        let metro = SelectionKey(line: .chiyoda, stationCode: "C04", direction: "S")
        XCTAssertEqual(ToeiCatalog.selection(from: metro.id), metro)
        XCTAssertEqual(ToeiCatalog.stations(on: .asakusa).count, 20)
        XCTAssertEqual(ToeiCatalog.stations(on: .oedo).count, 38)
    }

    func testResolvedKeyIsNilWhenIntentHasNoOperator() {
        XCTAssertNil(SelectStationIntent().resolvedKey)
    }

    func testResolvedKeyFallsBackWhenDirectionMissing() {
        let intent = SelectStationIntent()
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

    func testWidgetEntityMatchDropsDirectionWhenStationChanges() {
        let tokyo = ToeiCatalog.station(line: .marunouchi, code: "M17")!
        let stale = SelectionKey(line: .oedo, stationCode: "E17", direction: "B").id
        XCTAssertNil(WidgetEntityMatch.direction(id: stale, line: .marunouchi, stationID: tokyo.id))
        XCTAssertEqual(
            WidgetEntityMatch.direction(id: "marunouchi:M17:E", line: .marunouchi, stationID: tokyo.id),
            SelectionKey(line: .marunouchi, stationCode: "M17", direction: "E")
        )
        XCTAssertNil(WidgetEntityMatch.station(id: "oedo:E17", line: .marunouchi))
        XCTAssertEqual(WidgetEntityMatch.station(id: tokyo.id, line: .marunouchi)?.name, "東京")
    }

    func testResolvedKeyIgnoresStaleSelectionAfterOperatorChange() {
        let intent = SelectStationIntent()
        let tokyo = ToeiCatalog.station(line: .marunouchi, code: "M17")!
        intent.railwayOperator = OperatorEntity(.toei)
        intent.line = LineEntity(.marunouchi)
        intent.station = StationEntity(tokyo)
        intent.direction = DirectionEntity(
            key: SelectionKey(line: .marunouchi, stationCode: "M17", direction: "E"),
            name: tokyo.directionLabel("E")
        )
        XCTAssertEqual(intent.resolvedKey?.line, .asakusa)
        XCTAssertEqual(intent.resolvedKey?.stationCode, "A01")
        XCTAssertEqual(intent.resolvedKey?.direction, "N")
    }

    func testResolvedKeyIgnoresStaleToeiSelectionAfterSwitchingToMetro() {
        let intent = SelectStationIntent()
        let nishimagome = ToeiCatalog.station(line: .asakusa, code: "A01")!
        intent.railwayOperator = OperatorEntity(.metro)
        intent.line = LineEntity(.asakusa)
        intent.station = StationEntity(nishimagome)
        intent.direction = DirectionEntity(
            key: SelectionKey(line: .asakusa, stationCode: "A01", direction: "N"),
            name: nishimagome.directionLabel("N")
        )
        XCTAssertEqual(intent.resolvedKey, SelectionKey.default)
        XCTAssertEqual(intent.resolvedKey?.stationCode, "M17")
        XCTAssertEqual(intent.resolvedKey?.direction, "E")
    }

    func testResolvedKeyUsesDefaultStationWhenLineChangesWithinOperator() {
        let intent = SelectStationIntent()
        let tokyo = ToeiCatalog.station(line: .marunouchi, code: "M17")!
        intent.railwayOperator = OperatorEntity(.metro)
        intent.line = LineEntity(.ginza)
        intent.station = StationEntity(tokyo)
        intent.direction = DirectionEntity(
            key: SelectionKey(line: .marunouchi, stationCode: "M17", direction: "E"),
            name: tokyo.directionLabel("E")
        )
        XCTAssertEqual(intent.resolvedKey?.line, .ginza)
        XCTAssertEqual(intent.resolvedKey?.stationCode, "G01")
        XCTAssertEqual(intent.resolvedKey?.direction, "N")
    }

    func testResolvedKeyIgnoresStaleDirectionAfterStationChange() {
        let intent = SelectStationIntent()
        let tokyo = ToeiCatalog.station(line: .marunouchi, code: "M17")!
        intent.line = LineEntity(.marunouchi)
        intent.station = StationEntity(tokyo)
        intent.direction = DirectionEntity(
            key: SelectionKey(line: .oedo, stationCode: "E17", direction: "B"),
            name: "大門・六本木方面"
        )
        XCTAssertEqual(intent.resolvedKey?.line, .marunouchi)
        XCTAssertEqual(intent.resolvedKey?.stationCode, "M17")
    }

    func testResolvedKeyFallsBackFromOperatorToDefaultStation() {
        let metro = SelectStationIntent()
        metro.railwayOperator = OperatorEntity(.metro)
        XCTAssertEqual(metro.resolvedKey, SelectionKey.default)
        XCTAssertEqual(metro.resolvedKey?.stationCode, "M17")

        let toei = SelectStationIntent()
        toei.railwayOperator = OperatorEntity(.toei)
        XCTAssertEqual(toei.resolvedKey?.line, .asakusa)
        XCTAssertEqual(toei.resolvedKey?.stationCode, "A01")
        XCTAssertEqual(OperatorEntity(.toei).name, "都営地下鉄")
        XCTAssertEqual(OperatorEntity(.metro).id, "metro")
    }

    func testDefaultLineAndStationFollowOperatorAndLine() {
        XCTAssertEqual(WidgetEntityMatch.defaultLine(for: .metro), .marunouchi)
        XCTAssertEqual(WidgetEntityMatch.defaultLine(for: .toei), .asakusa)
        XCTAssertEqual(WidgetEntityMatch.defaultLineIfNeeded(.oedo, operator: .metro), .marunouchi)
        XCTAssertEqual(WidgetEntityMatch.defaultLineIfNeeded(.ginza, operator: .metro), .ginza)
        let ogikubo = ToeiCatalog.station(line: .marunouchi, code: "M01")
        XCTAssertEqual(WidgetEntityMatch.defaultStationIfNeeded(ogikubo, line: .marunouchi)?.code, "M01")
        XCTAssertEqual(WidgetEntityMatch.defaultStationIfNeeded(ogikubo, line: .ginza)?.code, "G01")
        XCTAssertEqual(WidgetEntityMatch.defaultStationIfNeeded(nil, line: .marunouchi)?.code, "M17")
    }

    func testResolvedLineAndStationIgnoreStaleParent() {
        XCTAssertEqual(WidgetEntityMatch.resolvedLine(.marunouchi, operator: .toei), .asakusa)
        XCTAssertEqual(WidgetEntityMatch.resolvedLine(.oedo, operator: .toei), .oedo)
        XCTAssertEqual(WidgetEntityMatch.resolvedLine(nil, operator: .toei), .asakusa)
        XCTAssertEqual(WidgetEntityMatch.resolvedLine(.marunouchi, operator: nil), .marunouchi)
        XCTAssertEqual(WidgetEntityMatch.resolvedStation("marunouchi:M17", line: .asakusa)?.code, "A01")
        XCTAssertEqual(WidgetEntityMatch.resolvedStation("marunouchi:M17", line: .marunouchi)?.code, "M17")
    }

    func testStationsMatchingIdentifiersDoNotRemapWhenLineIsMissing() {
        let ginza = WidgetEntityMatch.stationsMatchingIdentifiers(
            ["ginza:G09"],
            line: nil,
            operator: .metro
        )
        XCTAssertEqual(ginza.map(\.code), ["G09"])
        XCTAssertEqual(ginza.first?.name, "銀座")

        let stale = WidgetEntityMatch.stationsMatchingIdentifiers(
            ["marunouchi:M17"],
            line: .marunouchi,
            operator: .toei
        )
        XCTAssertTrue(stale.isEmpty)
        XCTAssertEqual(
            WidgetEntityMatch.stationsMatchingIdentifiers(
                ["ginza:G09"],
                line: .ginza,
                operator: .metro
            ).map(\.code),
            ["G09"]
        )
    }

    func testMatchingOrDefaultKeepsMatchOtherwiseUsesFallback() {
        XCTAssertEqual(
            WidgetEntityMatch.matchingOrDefault([String](), fallback: "浅草線"),
            ["浅草線"]
        )
        XCTAssertEqual(
            WidgetEntityMatch.matchingOrDefault(["丸ノ内線"], fallback: "浅草線"),
            ["丸ノ内線"]
        )
    }

    func testDefaultDirectionExistsForEveryLine() {
        for line in LineID.allCases {
            let station = WidgetEntityMatch.defaultStation(for: line)
            XCTAssertNotNil(station, line.rawValue)
            XCTAssertEqual(station?.line, line)
            let key = station.flatMap(WidgetEntityMatch.defaultDirection(for:))
            XCTAssertNotNil(key, line.rawValue)
            XCTAssertEqual(key?.line, line)
            XCTAssertEqual(key?.stationCode, station?.code)
        }
        XCTAssertEqual(WidgetEntityMatch.defaultStation(for: .marunouchi)?.code, "M17")
        XCTAssertEqual(WidgetEntityMatch.defaultStation(for: .ginza)?.code, "G01")
        XCTAssertEqual(
            WidgetEntityMatch.defaultDirection(for: WidgetEntityMatch.defaultStation(for: .marunouchi)!),
            SelectionKey(line: .marunouchi, stationCode: "M17", direction: "E")
        )
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

    func testWidgetTimelineDatesIncludeStaleClockFlip() {
        let now = Self.date(year: 2026, month: 8, day: 17, hour: 22, minute: 0)
        let staleAt = now.addingTimeInterval(8 * 60)
        let departure = now.addingTimeInterval(20 * 60)
        let dates = TrainSnapshot.widgetTimelineDates(
            now: now,
            departures: [departure],
            horizon: 15 * 60,
            extra: [staleAt]
        )
        XCTAssertTrue(dates.contains(staleAt))
        XCTAssertFalse(dates.contains(now.addingTimeInterval(20 * 60)))
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

final class WidgetNameFitTests: XCTestCase {
    func testShortNamesStayOneLine() {
        XCTAssertEqual(lines("笹塚・橋本"), ["笹塚・橋本"])
        XCTAssertEqual("笹塚・橋本".count, 5)
    }

    func testYoyogiWrapsAtNakaguroIncludingCatalogKe() {
        XCTAssertEqual(lines("代々木上原・向ヶ丘遊園"), ["代々木上原", "向ヶ丘遊園"])
        XCTAssertEqual("代々木上原・向ヶ丘遊園".count, 11)

        let catalog = ToeiCatalog.station(line: .chiyoda, code: "C07")?.directionLabel("S")
        XCTAssertEqual(catalog, "代々木上原・向ケ丘遊園方面")
        let withoutHomen = String(catalog!.dropLast(2))
        XCTAssertEqual(withoutHomen, "代々木上原・向ケ丘遊園")
        XCTAssertEqual(lines(withoutHomen), ["代々木上原", "向ケ丘遊園"])
    }

    func testHanedaWrapsToThreeLines() {
        let name = "羽田空港第１・第２ターミナル・西馬込"
        XCTAssertEqual(name.count, 18)
        XCTAssertEqual(lines(name), ["羽田空港第１", "第２ターミナル", "西馬込"])
        XCTAssertEqual(
            ToeiCatalog.station(line: .asakusa, code: "A08")?.directionLabel("S"),
            "羽田空港第１・第２ターミナル・西馬込方面"
        )
    }

    func testFourNakaguroPartsDoNotDumpOntoLineThree() {
        let name = "第１ターミナル・第２ターミナル・第３ターミナル・西馬込"
        XCTAssertEqual(lines(name), ["第１ターミナル", "第２ターミナル", "第３ターミナル・西馬込"])
        XCTAssertEqual(WidgetNameFit.layout(name, smallWidget: true).lineCount, 3)
    }

    func testLongNameWithoutNakaguroChunksByEight() {
        let name = "国会議事堂前交差点"
        XCTAssertEqual(name.count, 9)
        XCTAssertEqual(lines(name), ["国会議事堂前交差", "点"])
    }

    func testDestinationUsesFewerLinesWhenHeaderIsAlreadyThree() {
        XCTAssertEqual(WidgetNameFit.destinationMaxLines(headerLineCount: 1), 3)
        XCTAssertEqual(WidgetNameFit.destinationMaxLines(headerLineCount: 2), 2)
        XCTAssertEqual(WidgetNameFit.destinationMaxLines(headerLineCount: 3), 1)

        let name = "羽田空港第１・第２ターミナル・西馬込"
        let dest = WidgetNameFit.layout(name, smallWidget: true, maxLines: 1)
        XCTAssertEqual(dest.lineCount, 1)
        XCTAssertEqual(dest.text, name)
        XCTAssertEqual(WidgetNameFit.fontSize(layout: dest, base: 14, smallWidget: true), 11)
    }

    func testMediumWidgetDoesNotInsertBreaks() {
        let name = "羽田空港第１・第２ターミナル・西馬込"
        XCTAssertEqual(WidgetNameFit.layout(name, smallWidget: false).text, name)
        XCTAssertEqual(
            WidgetNameFit.fontSize(layout: WidgetNameFit.layout(name, smallWidget: false), base: 18, smallWidget: false),
            15
        )
    }

    private func lines(_ text: String) -> [String] {
        WidgetNameFit.layout(text, smallWidget: true).lines
    }
}
