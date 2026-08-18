import AppIntents

enum WidgetEntityMatch {
    static func station(id: String, line: LineID?) -> Station? {
        guard let station = ToeiCatalog.station(id: id) else { return nil }
        if let line, station.line != line { return nil }
        return station
    }

    static func direction(id: String, line: LineID?, stationID: String?) -> SelectionKey? {
        guard let key = ToeiCatalog.selection(from: id) else { return nil }
        if let line, key.line != line { return nil }
        if let stationID, "\(key.line.rawValue):\(key.stationCode)" != stationID { return nil }
        return key
    }

    /// 駅クエリの初期値と同じ駅。丸ノ内線なら東京を優先する。
    static func defaultStation(for line: LineID) -> Station? {
        if line == SelectionKey.default.line,
           let preferred = ToeiCatalog.station(line: line, code: SelectionKey.default.stationCode)
        {
            return preferred
        }
        return ToeiCatalog.stations(on: line).first
            ?? ToeiCatalog.station(line: SelectionKey.default.line, code: SelectionKey.default.stationCode)
    }

    /// 路線ピッカーの初期値。メトロなら丸ノ内線、都営なら浅草線。
    static func defaultLine(for railwayOperator: RailwayOperator) -> LineID? {
        if railwayOperator == SelectionKey.default.line.railwayOperator {
            return SelectionKey.default.line
        }
        return LineID.lines(of: railwayOperator).first
    }

    static func defaultLineIfNeeded(_ line: LineID, operator railwayOperator: RailwayOperator) -> LineID {
        guard line.railwayOperator != railwayOperator else { return line }
        return defaultLine(for: railwayOperator) ?? line
    }

    static func defaultStationIfNeeded(_ station: Station?, line: LineID) -> Station? {
        if let station, station.line == line { return station }
        return defaultStation(for: line)
    }

    /// 事業者が変わっても `$line` はすぐには更新されないので、ここで合わせる。
    static func resolvedLine(_ line: LineID?, operator railwayOperator: RailwayOperator?) -> LineID? {
        if let railwayOperator {
            if let line { return defaultLineIfNeeded(line, operator: railwayOperator) }
            return defaultLine(for: railwayOperator)
        }
        return line
    }

    static func resolvedStation(_ stationID: String?, line: LineID?) -> Station? {
        guard let line else { return nil }
        let station = stationID.flatMap { ToeiCatalog.station(id: $0) }
        return defaultStationIfNeeded(station, line: line)
    }

    static func defaultDirection(for station: Station) -> SelectionKey? {
        guard let code = station.directions.first else { return nil }
        return SelectionKey(line: station.line, stationCode: station.code, direction: code)
    }

    /// `entities(for:)` 専用。`$line` がまだ無いときはカタログだけで ID を解決し、デフォルト路線へ付け替えない。
    static func stationsMatchingIdentifiers(
        _ identifiers: [String],
        line: LineID?,
        operator railwayOperator: RailwayOperator?
    ) -> [Station] {
        if let line {
            let resolved = resolvedLine(line, operator: railwayOperator) ?? line
            return identifiers.compactMap { station(id: $0, line: resolved) }
        }
        return identifiers.compactMap { ToeiCatalog.station(id: $0) }
    }

    /// 空配列を返すとウィジェット設定が古い選択のまま残るので、親が変わったらデフォルトを返す。
    static func matchingOrDefault<T>(_ matched: [T], fallback: T?) -> [T] {
        if !matched.isEmpty { return matched }
        if let fallback { return [fallback] }
        return []
    }
}

struct OperatorEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "事業者")
    }
    static var defaultQuery = OperatorQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: "building.2.fill", isTemplate: true)
        )
    }

    init(_ railwayOperator: RailwayOperator) {
        self.id = railwayOperator.rawValue
        self.name = railwayOperator.displayName
    }
}

struct OperatorQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [OperatorEntity] {
        identifiers.compactMap { RailwayOperator(rawValue: $0).map(OperatorEntity.init) }
    }

    func suggestedEntities() async throws -> [OperatorEntity] {
        RailwayOperator.allCases.map(OperatorEntity.init)
    }

    func defaultResult() async -> OperatorEntity? {
        OperatorEntity(.metro)
    }
}

struct LineEntity: AppEntity {
    let id: String
    let name: String
    let operatorName: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "路線")
    }
    static var defaultQuery = LineQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(operatorName)",
            image: .init(systemName: "tram.fill", isTemplate: true)
        )
    }

    init(_ line: LineID) {
        self.id = line.rawValue
        self.name = line.displayName
        self.operatorName = line.railwayOperator.displayName
    }
}

struct LineQuery: EntityQuery {
    @IntentParameterDependency<SelectStationIntent>(\.$railwayOperator)
    var selection

    func entities(for identifiers: [String]) async throws -> [LineEntity] {
        guard !identifiers.isEmpty else { return [] }
        let matched: [LineEntity] = identifiers.compactMap { id in
            guard let line = LineID(rawValue: id) else { return nil }
            if let op = resolvedOperator(), line.railwayOperator != op {
                return nil
            }
            return LineEntity(line)
        }
        let op = resolvedOperator() ?? SelectionKey.default.line.railwayOperator
        return WidgetEntityMatch.matchingOrDefault(
            matched,
            fallback: WidgetEntityMatch.defaultLine(for: op).map(LineEntity.init)
        )
    }

    func suggestedEntities() async throws -> [LineEntity] {
        LineID.lines(of: resolvedOperator() ?? SelectionKey.default.line.railwayOperator).map(LineEntity.init)
    }

    func defaultResult() async -> LineEntity? {
        let op = resolvedOperator() ?? SelectionKey.default.line.railwayOperator
        return WidgetEntityMatch.defaultLine(for: op).map(LineEntity.init)
    }

    private func resolvedOperator() -> RailwayOperator? {
        guard let selection else { return nil }
        return RailwayOperator(rawValue: selection.railwayOperator.id)
    }
}

struct StationEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "駅")
    }
    static var defaultQuery = StationQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: "mappin.and.ellipse", isTemplate: true)
        )
    }

    init(_ station: Station) {
        self.id = station.id
        self.name = "\(station.numbering) \(station.name)"
    }
}

struct StationQuery: EntityQuery {
    /// 路線の defaultResult は駅クエリまで伝播しないので、事業者にも直接依存する。
    @IntentParameterDependency<SelectStationIntent>(\.$railwayOperator)
    var operatorSelection

    @IntentParameterDependency<SelectStationIntent>(\.$line)
    var selection

    func entities(for identifiers: [String]) async throws -> [StationEntity] {
        guard !identifiers.isEmpty else { return [] }
        let pickedLine = selection.flatMap { LineID(rawValue: $0.line.id) }
        let matched = WidgetEntityMatch.stationsMatchingIdentifiers(
            identifiers,
            line: pickedLine,
            operator: resolvedOperator()
        ).map(StationEntity.init)
        guard pickedLine != nil else { return matched }
        return WidgetEntityMatch.matchingOrDefault(matched, fallback: defaultStationEntity())
    }

    func suggestedEntities() async throws -> [StationEntity] {
        ToeiCatalog.stations(on: resolvedLine() ?? SelectionKey.default.line).map(StationEntity.init)
    }

    func defaultResult() async -> StationEntity? {
        defaultStationEntity()
    }

    private func defaultStationEntity() -> StationEntity? {
        WidgetEntityMatch.defaultStation(for: resolvedLine() ?? SelectionKey.default.line).map(StationEntity.init)
    }

    private func resolvedOperator() -> RailwayOperator? {
        guard let operatorSelection else { return nil }
        return RailwayOperator(rawValue: operatorSelection.railwayOperator.id)
    }

    private func resolvedLine() -> LineID? {
        WidgetEntityMatch.resolvedLine(
            selection.flatMap { LineID(rawValue: $0.line.id) },
            operator: resolvedOperator()
        )
    }
}

struct DirectionEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "方面")
    }
    static var defaultQuery = DirectionQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: "arrow.right.circle.fill", isTemplate: true)
        )
    }

    init(key: SelectionKey, name: String) {
        self.id = key.id
        self.name = name
    }
}

struct DirectionQuery: EntityQuery {
    /// 1段ずつ依存させる。まとめて必須にすると、上流が空のとき defaultResult が呼べない。
    @IntentParameterDependency<SelectStationIntent>(\.$railwayOperator)
    var operatorSelection

    @IntentParameterDependency<SelectStationIntent>(\.$line)
    var lineSelection

    @IntentParameterDependency<SelectStationIntent>(\.$station)
    var stationSelection

    func entities(for identifiers: [String]) async throws -> [DirectionEntity] {
        guard !identifiers.isEmpty else { return [] }
        let station = resolvedStation()
        let matched = identifiers.compactMap { id in
            WidgetEntityMatch.direction(
                id: id,
                line: station?.line ?? resolvedLine(),
                stationID: station?.id
            ).flatMap { directionEntity(for: $0) }
        }
        return WidgetEntityMatch.matchingOrDefault(matched, fallback: defaultDirectionEntity())
    }

    func suggestedEntities() async throws -> [DirectionEntity] {
        guard let station = resolvedStation() else { return [] }
        return station.directions.compactMap { code in
            directionEntity(for: SelectionKey(line: station.line, stationCode: station.code, direction: code))
        }
    }

    func defaultResult() async -> DirectionEntity? {
        defaultDirectionEntity()
    }

    private func defaultDirectionEntity() -> DirectionEntity? {
        guard let station = resolvedStation(),
              let key = WidgetEntityMatch.defaultDirection(for: station)
        else { return nil }
        return directionEntity(for: key)
    }

    private func resolvedOperator() -> RailwayOperator? {
        guard let operatorSelection else { return nil }
        return RailwayOperator(rawValue: operatorSelection.railwayOperator.id)
    }

    private func resolvedLine() -> LineID? {
        let fromLine = lineSelection.flatMap { LineID(rawValue: $0.line.id) }
        let fromStation = stationSelection.flatMap { ToeiCatalog.station(id: $0.station.id)?.line }
        return WidgetEntityMatch.resolvedLine(fromLine ?? fromStation, operator: resolvedOperator())
    }

    /// 選ばれている駅が今の路線と一致すればそれを使い、そうでなければ路線のデフォルト駅にする。
    private func resolvedStation() -> Station? {
        WidgetEntityMatch.resolvedStation(
            stationSelection?.station.id,
            line: resolvedLine()
        ) ?? WidgetEntityMatch.defaultStation(for: SelectionKey.default.line)
    }

    private func directionEntity(for key: SelectionKey) -> DirectionEntity? {
        guard let station = ToeiCatalog.station(line: key.line, code: key.stationCode) else { return nil }
        let stored = AppSettings.directionLabel(selectionID: key.id)
        let name = (stored.flatMap { $0.isEmpty ? nil : $0 }) ?? station.directionLabel(key.direction)
        return DirectionEntity(key: key, name: name)
    }
}

struct SelectStationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "駅を選択" }
    static var description: IntentDescription {
        IntentDescription("次発を表示する都営・東京メトロの路線・駅・方面を選びます。")
    }

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$railwayOperator) \(\.$line) \(\.$station) \(\.$direction)")
    }

    @Parameter(title: "事業者")
    var railwayOperator: OperatorEntity?

    @Parameter(title: "路線")
    var line: LineEntity?

    @Parameter(title: "駅")
    var station: StationEntity?

    @Parameter(title: "方面")
    var direction: DirectionEntity?

    init() {}

    init(
        railwayOperator: OperatorEntity,
        line: LineEntity,
        station: StationEntity,
        direction: DirectionEntity
    ) {
        self.railwayOperator = railwayOperator
        self.line = line
        self.station = station
        self.direction = direction
    }

    var resolvedKey: SelectionKey? {
        let op = railwayOperator.flatMap { RailwayOperator(rawValue: $0.id) }
        let pickedLine = line.flatMap { LineID(rawValue: $0.id) }
        let lineFromStation = station.flatMap { ToeiCatalog.station(id: $0.id)?.line }
        let lineID = WidgetEntityMatch.resolvedLine(pickedLine ?? lineFromStation, operator: op)
        let resolvedStation = WidgetEntityMatch.resolvedStation(station?.id, line: lineID)

        if let direction,
           let key = WidgetEntityMatch.direction(id: direction.id, line: lineID, stationID: resolvedStation?.id)
        {
            return key
        }
        if let resolvedStation, let key = WidgetEntityMatch.defaultDirection(for: resolvedStation) {
            return key
        }
        return nil
    }
}
