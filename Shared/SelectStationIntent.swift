import AppIntents

struct LineEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "路線")
    }
    static var defaultQuery = LineQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: "tram.fill", isTemplate: true)
        )
    }

    init(_ line: LineID) {
        self.id = line.rawValue
        self.name = line.displayName
    }
}

struct LineQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [LineEntity] {
        identifiers.compactMap { LineID(rawValue: $0).map(LineEntity.init) }
    }

    func suggestedEntities() async throws -> [LineEntity] {
        LineID.allCases.map(LineEntity.init)
    }

    func defaultResult() async -> LineEntity? {
        LineEntity(.oedo)
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
    @IntentParameterDependency<SelectStationIntent>(\.$line)
    var selection

    func entities(for identifiers: [String]) async throws -> [StationEntity] {
        identifiers.compactMap { ToeiCatalog.station(id: $0).map(StationEntity.init) }
    }

    func suggestedEntities() async throws -> [StationEntity] {
        let lineID = resolvedLine() ?? .oedo
        return ToeiCatalog.stations(on: lineID).map(StationEntity.init)
    }

    func defaultResult() async -> StationEntity? {
        let lineID = resolvedLine() ?? .oedo
        let fallback = ToeiCatalog.station(line: .oedo, code: "E17")
        return (ToeiCatalog.stations(on: lineID).first ?? fallback).map(StationEntity.init)
    }

    private func resolvedLine() -> LineID? {
        guard let selection else { return nil }
        let entity = selection.line
        return LineID(rawValue: entity.id)
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
    @IntentParameterDependency<SelectStationIntent>(\.$station)
    var selection

    func entities(for identifiers: [String]) async throws -> [DirectionEntity] {
        identifiers.compactMap { id in
            guard let key = ToeiCatalog.selection(from: id),
                  let station = ToeiCatalog.station(line: key.line, code: key.stationCode)
            else { return nil }
            // 空文字は保存済みの表示名を壊すので返さない。カタログの方面名は常にある。
            let stored = AppSettings.directionLabel(selectionID: id)
            let name = (stored.flatMap { $0.isEmpty ? nil : $0 }) ?? station.directionLabel(key.direction)
            return DirectionEntity(key: key, name: name)
        }
    }

    func suggestedEntities() async throws -> [DirectionEntity] {
        guard let station = resolvedStation()
                ?? ToeiCatalog.station(line: .oedo, code: "E17")
        else { return [] }
        return station.directions.map { code in
            let key = SelectionKey(line: station.line, stationCode: station.code, direction: code)
            let stored = AppSettings.directionLabel(selectionID: key.id)
            let name = (stored.flatMap { $0.isEmpty ? nil : $0 }) ?? station.directionLabel(code)
            return DirectionEntity(key: key, name: name)
        }
    }

    func defaultResult() async -> DirectionEntity? {
        (try? await suggestedEntities())?.first
    }

    private func resolvedStation() -> Station? {
        guard let selection else { return nil }
        let entity = selection.station
        return ToeiCatalog.station(id: entity.id)
    }
}

struct SelectStationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "駅を選択" }
    static var description: IntentDescription {
        IntentDescription("次発を表示する路線・駅・方面を選びます。")
    }

    @Parameter(title: "路線")
    var line: LineEntity?

    @Parameter(title: "駅")
    var station: StationEntity?

    @Parameter(title: "方面")
    var direction: DirectionEntity?

    init() {}

    init(line: LineEntity, station: StationEntity, direction: DirectionEntity) {
        self.line = line
        self.station = station
        self.direction = direction
    }

    var resolvedKey: SelectionKey? {
        if let direction, let key = ToeiCatalog.selection(from: direction.id) {
            return key
        }
        if let station, let resolved = ToeiCatalog.station(id: station.id),
           let code = resolved.directions.first
        {
            return SelectionKey(line: resolved.line, stationCode: resolved.code, direction: code)
        }
        if let line, let lineID = LineID(rawValue: line.id),
           let resolved = ToeiCatalog.stations(on: lineID).first,
           let code = resolved.directions.first
        {
            return SelectionKey(line: resolved.line, stationCode: resolved.code, direction: code)
        }
        return nil
    }
}
