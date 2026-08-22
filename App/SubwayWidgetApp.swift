import SwiftUI
import WidgetKit
import AppIntents
import AppKit

@main
struct SubwayWidgetApp: App {
    @StateObject private var model = ArrivalModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Label(model.menuBarTitle, systemImage: model.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class ArrivalModel: ObservableObject {
    private static let refreshInterval: TimeInterval = 60

    @Published var selectedOperator: RailwayOperator {
        didSet {
            guard selectedOperator != oldValue else { return }
            selectedLine = WidgetEntityMatch.defaultLineIfNeeded(selectedLine, operator: selectedOperator)
        }
    }
    @Published var selectedLine: LineID {
        didSet {
            guard selectedLine != oldValue else { return }
            selectedStation = WidgetEntityMatch.defaultStationIfNeeded(selectedStation, line: selectedLine)
        }
    }
    @Published var selectedStation: Station? {
        didSet {
            guard selectedStation?.id != oldValue?.id else { return }
            syncDirectionToStation()
            persistAndRefresh()
        }
    }
    @Published var selectedDirection: String {
        didSet {
            guard selectedDirection != oldValue else { return }
            persistAndRefresh()
        }
    }
    @Published var stationFilter = ""
    @Published var upcoming: UpcomingTrains?
    @Published var status: LineStatus?
    @Published var errorText: String?
    @Published private(set) var isPaused: Bool

    private var timer: Timer?
    private var selectionGeneration = 0

    var selectedKey: SelectionKey? {
        guard let station = selectedStation else { return nil }
        return SelectionKey(line: station.line, stationCode: station.code, direction: selectedDirection)
    }

    var filteredStations: [Station] {
        let stations = ToeiCatalog.stations(on: selectedLine)
        let query = stationFilter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return stations }
        return stations.filter { $0.name.contains(query) || $0.numbering.contains(query) || $0.code.contains(query) }
    }

    var directionOptions: [(code: String, label: String)] {
        guard let station = selectedStation else { return [] }
        return station.directions.map { code in
            let key = SelectionKey(line: station.line, stationCode: station.code, direction: code)
            let label = AppSettings.directionLabel(selectionID: key.id) ?? station.directionLabel(code)
            return (code, label)
        }
    }

    init() {
        let saved = AppSettings.selectedKey ?? .default
        let station = ToeiCatalog.station(line: saved.line, code: saved.stationCode)
            ?? ToeiCatalog.station(line: SelectionKey.default.line, code: SelectionKey.default.stationCode)
            ?? ToeiCatalog.stations(on: SelectionKey.default.line)[0]
        selectedOperator = station.line.railwayOperator
        selectedLine = station.line
        selectedStation = station
        selectedDirection = station.directions.contains(saved.direction) ? saved.direction : (station.directions.first ?? SelectionKey.default.direction)
        isPaused = AppSettings.isPaused
        if !AppSettings.isUsingAppGroup {
            errorText = "Team ID が空です。ターミナルで ./scripts/sync-team.sh を実行してから、Xcode でビルドし直してください"
        }
        observePauseChangesFromWidget()
        observeManualRefreshRequestsFromWidget()
        observeOpenStatusPageRequestsFromWidget()
        openPendingStatusPage()
        if !isPaused {
            startTimer()
            Task { await refresh(force: true) }
        }
    }

    private func persistAndRefresh() {
        if let key = selectedKey {
            AppSettings.selectedKey = key
        }
        selectionGeneration += 1
        let generation = selectionGeneration
        Task { await refresh(generation: generation) }
    }

    private func syncDirectionToStation() {
        guard let station = selectedStation else { return }
        if !station.directions.contains(selectedDirection) {
            selectedDirection = station.directions.first ?? SelectionKey.default.direction
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    private func observePauseChangesFromWidget() {
        DistributedNotificationCenter.default().addObserver(
            forName: .pauseStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.syncPauseState() }
        }
    }

    private func observeManualRefreshRequestsFromWidget() {
        DistributedNotificationCenter.default().addObserver(
            forName: .manualRefreshRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh(force: true) }
        }
    }

    private func observeOpenStatusPageRequestsFromWidget() {
        DistributedNotificationCenter.default().addObserver(
            forName: .openStatusPageRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.openPendingStatusPage() }
        }
    }

    /// mailbox が空なら何もしない。メニューバーの選択路線に落とすと、ウィジェットと違うページが開く。
    private func openPendingStatusPage() {
        guard let url = AppSettings.takePendingStatusPageURL() else { return }
        subwayLogger.debug("open status page \(url.absoluteString, privacy: .public)")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(url, configuration: config) { _, error in
            if let error {
                subwayLogger.error("status page open failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func syncPauseState() {
        let shared = AppSettings.isPaused
        guard shared != isPaused else { return }
        if shared { pause(propagate: false) } else { resume(propagate: false) }
    }

    var menuBarTitle: String {
        if isPaused { return "停止中" }
        guard let next = upcoming?.trains.first else { return selectedStation?.name ?? "--" }
        let minutes = TrainSnapshot.remainingMinutes(until: next.date, now: Date())
        let remain = upcoming?.isNextDay == true ? "始発" : TrainSnapshot.remainingLabel(minutes: minutes, compact: true)
        return "\(selectedStation?.name ?? "") \(remain)"
    }

    var menuBarSymbol: String {
        if isPaused { return "tram" }
        if status?.kind == .delayed { return "exclamationmark.triangle.fill" }
        return "tram.fill"
    }

    func pause(propagate: Bool = true) {
        isPaused = true
        timer?.invalidate()
        timer = nil
        if propagate {
            AppSettings.isPaused = true
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func resume(propagate: Bool = true) {
        isPaused = false
        if propagate { AppSettings.isPaused = false }
        startTimer()
        Task { await refresh(force: true) }
    }

    func refresh(force: Bool = false, generation: Int? = nil) async {
        let generation = generation ?? selectionGeneration
        let holidays = await HolidayChecker.holidays()
        AppSettings.saveHolidays(holidays)
        do {
            try await refreshStatuses(force: force)
        } catch {
            guard !Self.isCancellation(error) else { return }
            subwayLogger.error("運行状況の取得に失敗: \(String(describing: error), privacy: .public)")
        }
        guard generation == selectionGeneration else { return }
        do {
            try await refreshSelection(force: force, holidays: holidays)
            errorText = nil
        } catch {
            guard generation == selectionGeneration else { return }
            if !Self.isCancellation(error) {
                errorText = error.localizedDescription
                subwayLogger.error("refresh failed: \(String(describing: error), privacy: .public)")
            }
        }
        guard generation == selectionGeneration else { return }
        await refreshWidgetSelections(force: force, holidays: holidays, excluding: selectedKey?.id)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func refreshStatuses(force: Bool) async throws {
        let statuses = try await TrainStatusService.fetchStatuses(force: force)
        for status in statuses.values {
            AppSettings.saveStatus(status)
        }
        if let line = selectedStation?.line {
            status = statuses[line] ?? AppSettings.status(line: line)
        }
    }

    private func refreshSelection(force: Bool, holidays: Set<String>) async throws {
        guard let key = selectedKey else { return }
        let timetable = try await TrainScheduleService.fetchTimetable(for: key, force: force)
        AppSettings.saveSchedule(timetable, selectionID: key.id)
        upcoming = TrainTime.upcoming(from: timetable, now: Date(), holidays: holidays, limit: 4)
        subwayLogger.debug("saved timetable for \(key.id, privacy: .public) trains=\(timetable.weekday?.trains.count ?? 0, privacy: .public)")
    }

    private func refreshWidgetSelections(force: Bool, holidays: Set<String>, excluding excludedID: String?) async {
        let configured = await widgetConfiguredKeys()
        var seen = Set<String>()
        var keys: [SelectionKey] = []
        for key in configured + AppSettings.neededSelections {
            if key.id == excludedID { continue }
            if seen.insert(key.id).inserted {
                keys.append(key)
            }
        }
        subwayLogger.debug("widget-only keys to refresh: \(keys.map(\.id), privacy: .public)")
        await withTaskGroup(of: Void.self) { group in
            for key in keys {
                group.addTask {
                    do {
                        let timetable = try await TrainScheduleService.fetchTimetable(for: key, force: force)
                        AppSettings.saveSchedule(timetable, selectionID: key.id)
                    } catch {
                        subwayLogger.error("\(key.id, privacy: .public) の時刻表取得に失敗: \(String(describing: error), privacy: .public)")
                    }
                }
            }
        }
    }

    private func widgetConfiguredKeys() async -> [SelectionKey] {
        let infos: [WidgetInfo]
        do {
            infos = try await withCheckedThrowingContinuation { continuation in
                WidgetCenter.shared.getCurrentConfigurations { continuation.resume(with: $0) }
            }
        } catch {
            subwayLogger.error("getCurrentConfigurations に失敗: \(String(describing: error), privacy: .public)")
            return []
        }
        subwayLogger.debug("getCurrentConfigurations: \(infos.count, privacy: .public) 件")
        var seen = Set<String>()
        var keys: [SelectionKey] = []
        for info in infos {
            guard let intent = info.widgetConfigurationIntent(of: SelectStationIntent.self) else {
                subwayLogger.error("widgetConfigurationIntent(of:) が nil")
                continue
            }
            guard let key = intent.resolvedKey else { continue }
            if seen.insert(key.id).inserted {
                keys.append(key)
            }
        }
        return keys
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return (error as? URLError)?.code == .cancelled
    }
}

struct MenuContent: View {
    @ObservedObject var model: ArrivalModel
    @FocusState private var filterFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            pickers
            Divider()
            status
            scheduleRow
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                filterFocused = true
            }
        }
        .onChange(of: model.selectedOperator) { _, _ in
            model.stationFilter = ""
        }
        .onChange(of: model.selectedLine) { _, _ in
            model.stationFilter = ""
        }
    }

    private var pickers: some View {
        VStack(alignment: .leading, spacing: 8) {
            labeled("事業者") {
                Picker("", selection: $model.selectedOperator) {
                    ForEach(RailwayOperator.allCases) { railwayOperator in
                        Text(railwayOperator.displayName).tag(railwayOperator)
                    }
                }
                .labelsHidden()
            }
            labeled("路線") {
                Picker("", selection: $model.selectedLine) {
                    ForEach(LineID.lines(of: model.selectedOperator)) { line in
                        Text(line.displayName).tag(line)
                    }
                }
                .labelsHidden()
            }
            labeled("駅") {
                TextField("駅名で絞り込み", text: $model.stationFilter)
                    .textFieldStyle(.roundedBorder)
                    .focused($filterFocused)
                Picker("", selection: $model.selectedStation) {
                    ForEach(model.filteredStations) { station in
                        Text("\(station.numbering) \(station.name)").tag(Optional(station))
                    }
                }
                .labelsHidden()
            }
            labeled("方面") {
                Picker("", selection: $model.selectedDirection) {
                    ForEach(model.directionOptions, id: \.code) { option in
                        Text(option.label).tag(option.code)
                    }
                }
                .labelsHidden()
            }
        }
    }

    private func labeled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).foregroundStyle(.secondary).font(.caption)
            content()
        }
    }

    @ViewBuilder
    private var scheduleRow: some View {
        if let upcoming = model.upcoming, upcoming.trains.count > 1 {
            VStack(alignment: .leading, spacing: 4) {
                Text(ToeiConfig.scheduleHeading(kind: upcoming.kind, isNextDay: upcoming.isNextDay))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(Array(upcoming.trains.dropFirst().prefix(3).enumerated()), id: \.offset) { _, train in
                        Text(train.date, format: .dateTime.hour().minute())
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if let errorText = model.errorText {
            Label(errorText, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        } else if let next = model.upcoming?.trains.first {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(next.date, format: .dateTime.hour().minute())
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    remainingView(until: next.date, isNextDay: model.upcoming?.isNextDay == true)
                }
                Text(next.departure.destination)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if model.upcoming?.isNextDay == true {
                    Text("終電済")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let status = model.status {
                    Text(status.text)
                        .font(.caption)
                        .foregroundStyle(status.kind == .delayed ? Color.orange : Color.secondary)
                }
                if model.isPaused {
                    Label("一時停止中（自動更新なし）", systemImage: "pause.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        } else if model.isPaused {
            Label("一時停止中", systemImage: "pause.circle")
                .font(.callout)
                .foregroundStyle(.orange)
        } else {
            ProgressView().controlSize(.small)
        }
    }

    @ViewBuilder
    private func remainingView(until date: Date, isNextDay: Bool) -> some View {
        let minutes = TrainSnapshot.remainingMinutes(until: date, now: Date())
        Text(isNextDay ? "始発" : TrainSnapshot.remainingLabel(minutes: minutes, compact: false))
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(!isNextDay && minutes <= 1 ? Color.green : Color.primary)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Link(destination: ToeiConfig.statusURL(for: model.selectedLine)) {
                Label("運行情報を見る", systemImage: "tram")
                    .font(.caption)
            }
            Text("データ: Yahoo!路線情報。時刻は定刻です。個人の私的利用の範囲でご利用ください。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(model.isPaused ? "再開" : "一時停止") {
                    if model.isPaused { model.resume() } else { model.pause() }
                }
                Button("今すぐ更新") {
                    Task { await model.refresh(force: true) }
                }
                Spacer()
                Button("終了") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .font(.caption)
        }
    }
}
