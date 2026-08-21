import WidgetKit
import SwiftUI
import AppIntents

struct TrainEntry: TimelineEntry {
    let date: Date
    let key: SelectionKey?
    let stationName: String?
    let directionLabel: String?
    let upcoming: UpcomingTrains?
    let status: LineStatus?
    let isPaused: Bool

    static func placeholder(_ date: Date = Date()) -> TrainEntry {
        TrainEntry(date: date, key: nil, stationName: nil, directionLabel: nil, upcoming: nil, status: nil, isPaused: false)
    }

    var line: LineID? { key?.line }

    var next: DatedTrain? { upcoming?.trains.first }
    var following: [DatedTrain] {
        Array(upcoming?.trains.dropFirst() ?? [])
    }
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TrainEntry {
        TrainEntry.placeholder()
    }

    func snapshot(for configuration: SelectStationIntent, in context: Context) async -> TrainEntry {
        let entry = buildEntry(configuration: configuration, now: Date())
        requestScheduleIfNeeded(entry)
        return entry
    }

    func timeline(for configuration: SelectStationIntent, in context: Context) async -> Timeline<TrainEntry> {
        let now = Date()
        let first = buildEntry(configuration: configuration, now: now)
        requestScheduleIfNeeded(first)
        let departures = first.upcoming?.trains.map(\.date) ?? []
        if first.key == nil || first.isPaused || departures.isEmpty {
            return Timeline(entries: [first], policy: .after(reloadDate(for: first, now: now)))
        }

        let extra = staleClockDates(status: first.status)
        let dates = TrainSnapshot.widgetTimelineDates(now: now, departures: departures, extra: extra)
        let entries = dates.map { buildEntry(configuration: configuration, now: $0) }
        subwayLogger.debug("timeline entries=\(entries.count, privacy: .public)")
        let lastDate = entries.last?.date ?? now
        return Timeline(entries: entries, policy: .after(lastDate.addingTimeInterval(30)))
    }

    private func reloadDate(for entry: TrainEntry, now: Date) -> Date {
        guard entry.key != nil else { return now.addingTimeInterval(10 * 60) }
        if entry.isPaused { return now.addingTimeInterval(60 * 60) }
        if let next = entry.next {
            let remaining = TrainSnapshot.remainingMinutes(until: next.date, now: now)
            if remaining <= 2 { return now.addingTimeInterval(30) }
            return now.addingTimeInterval(60)
        }
        return now.addingTimeInterval(5 * 60)
    }

    /// 平常運転が古くなる瞬間に entry を差し、時計アイコンへ切り替えられるようにする。
    private func staleClockDates(status: LineStatus?) -> [Date] {
        guard let status, status.kind == .normal else { return [] }
        return [status.observedAt.addingTimeInterval(LineStatus.staleInterval)]
    }

    private func requestScheduleIfNeeded(_ entry: TrainEntry) {
        guard let key = entry.key else { return }
        AppSettings.noteNeededSelection(key)
        if entry.upcoming == nil {
            AppSettings.notifyManualRefreshRequested()
        }
    }

    /// ウィジェット拡張は通信しない。保存済みの設定と App Group の時刻表・運行状況だけを使う。
    private func buildEntry(configuration: SelectStationIntent, now: Date) -> TrainEntry {
        guard let key = configuration.resolvedKey,
              let station = ToeiCatalog.station(line: key.line, code: key.stationCode)
        else {
            return TrainEntry.placeholder(now)
        }
        let timetable = AppSettings.schedule(selectionID: key.id)
        let upcoming = timetable.flatMap {
            TrainTime.upcoming(from: $0, now: now, holidays: AppSettings.holidays, limit: 4)
        }
        let direction = AppSettings.directionLabel(selectionID: key.id)
            ?? configuration.direction?.name
            ?? station.directionLabel(key.direction)
        return TrainEntry(
            date: now,
            key: key,
            stationName: station.name,
            directionLabel: direction,
            upcoming: upcoming,
            status: AppSettings.status(line: key.line),
            isPaused: AppSettings.isPaused
        )
    }
}

struct SubwayWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: Provider.Entry

    private static let footnoteFont = Font.system(size: 9)

    private var isSmall: Bool { family == .systemSmall }

    /// 方面が3行になると、同じ行き先を次発でも3行にするとフッターが欠ける。
    private var headerDirectionLayout: WidgetNameFit.Layout {
        WidgetNameFit.layout(headerDirection ?? "", smallWidget: isSmall)
    }

    private var smallCrowded: Bool {
        isSmall && headerDirectionLayout.lineCount >= 3
    }

    var body: some View {
        let stack = VStack(alignment: .leading, spacing: isSmall ? (smallCrowded ? 4 : 5) : 8) {
            header
            nextTrain
            if !isSmall {
                Spacer(minLength: 0)
            }
            followingLine
            statusLine
        }
        .padding(.horizontal, isSmall ? 10 : 12)
        .padding(.vertical, smallCrowded ? 8 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())

        ZStack(alignment: .topTrailing) {
            if let line = entry.line {
                Button(intent: OpenLineStatusIntent(line: line)) {
                    stack
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                stack
            }
            if entry.key != nil {
                headerButtons
                    .padding(.top, smallCrowded ? 8 : 12)
                    .padding(.trailing, isSmall ? 10 : 12)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 6) {
            if let line = entry.line {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: line.colorHex))
                    .frame(width: 4)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .top, spacing: 6) {
                    Text(entry.line?.displayName ?? "東京地下鉄")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    if entry.key != nil {
                        headerButtons
                            .hidden()
                            .allowsHitTesting(false)
                    }
                }
                Text(entry.stationName ?? "駅を選択")
                    .font(.system(size: isSmall ? 15 : 17, weight: .bold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let direction = headerDirection {
                    fittingName(direction, baseSize: isSmall ? 13 : 15)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerButtons: some View {
        HStack(spacing: 8) {
            Button(intent: TogglePauseIntent()) {
                Image(systemName: entry.isPaused ? "play.fill" : "pause.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(entry.isPaused ? .orange : .secondary)

            Button(intent: RefreshTrainIntent(selectionID: entry.key?.id)) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var nextTrain: some View {
        if entry.key == nil {
            Label("ウィジェットを編集して路線・駅・方面を選択", systemImage: "gearshape")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        } else if entry.isPaused, entry.upcoming == nil {
            Label("一時停止中", systemImage: "pause.circle")
                .font(.callout)
                .foregroundStyle(.orange)
        } else if let next = entry.next {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: isSmall ? 5 : 8) {
                    // Date.FormatStyle は日本語ロケールで「22時42分」になり、小サイズで 22… に省略される。
                    Text(next.departure.timeText)
                        .font(.system(size: isSmall ? 20 : 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .fixedSize(horizontal: true, vertical: false)
                    remainingText(until: next.date, isNextDay: entry.upcoming?.isNextDay == true)
                }
                fittingName(
                    next.departure.destination,
                    baseSize: isSmall ? 14 : 18,
                    weight: .medium,
                    maxLines: WidgetNameFit.destinationMaxLines(headerLineCount: headerDirectionLayout.lineCount)
                )
                if !isSmall, entry.upcoming?.isNextDay == true {
                    Text("終電済 · \(ToeiConfig.scheduleHeading(kind: entry.upcoming!.kind, isNextDay: true))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        } else {
            Text("時刻表を取得できません")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// ヘッダは幅が狭いので「方面」を落とす。次発の行き先は本文側に出す。
    private var headerDirection: String? {
        guard let raw = entry.directionLabel, !raw.isEmpty else { return nil }
        if raw.hasSuffix("方面") {
            return String(raw.dropLast(2))
        }
        return raw
    }

    /// 短い名前は既定サイズのまま。小ウィジェットで長い「A・B・C」は中黒で改行する。
    /// `lineLimit` だけの折り返しは幅が渡らず省略になるので、改行は `WidgetNameFit` で入れる。
    private func fittingName(
        _ text: String,
        baseSize: CGFloat,
        weight: Font.Weight = .regular,
        maxLines: Int = WidgetNameFit.smallMaxLines
    ) -> some View {
        let layout = WidgetNameFit.layout(text, smallWidget: isSmall, maxLines: maxLines)
        let size = WidgetNameFit.fontSize(layout: layout, base: baseSize, smallWidget: isSmall)
        let lines = layout.lineCount
        return Text(layout.text)
            .font(.system(size: size, weight: weight, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(lines)
            .lineSpacing(lines >= 3 ? -1 : 0)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, lines >= 3 ? 2 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func remainingText(until date: Date, isNextDay: Bool) -> some View {
        let minutes = TrainSnapshot.remainingMinutes(until: date, now: entry.date)
        let label = isNextDay
            ? "始発"
            : TrainSnapshot.remainingLabel(minutes: minutes, compact: family == .systemSmall)
        return Text(label)
            .font(.system(size: isSmall ? 12 : 16, weight: .semibold, design: .rounded))
            .foregroundStyle(!isNextDay && minutes <= 1 ? Color.green : Color.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    @ViewBuilder
    private var followingLine: some View {
        let count = isSmall ? 2 : 3
        let shown = Array(entry.following.prefix(count))
        if !shown.isEmpty {
            HStack(spacing: 8) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, train in
                    Text(train.departure.timeText)
                        .font(Self.footnoteFont)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if let status = entry.status {
            HStack(spacing: 4) {
                if entry.isPaused {
                    Image(systemName: "pause.circle")
                        .foregroundStyle(.orange)
                } else if let symbol = status.warningSymbolName(at: entry.date) {
                    Image(systemName: symbol)
                        .foregroundStyle(.orange)
                }
                Text(status.text)
                    .foregroundStyle(status.kind == .delayed ? Color.orange : Color.secondary)
                if let kind = entry.upcoming?.kind, entry.upcoming?.isNextDay != true {
                    Text("· \(kind.label)")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(Self.footnoteFont)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }
}

struct SubwayWidget: Widget {
    let kind: String = "SubwayWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectStationIntent.self, provider: Provider()) { entry in
            SubwayWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("東京地下鉄運行情報")
        .description("選んだ駅・方面の次発時刻と運行状況を、Yahoo!路線情報から表示します。都営地下鉄と東京メトロに対応しています。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}
