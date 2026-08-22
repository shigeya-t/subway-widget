import AppIntents
import WidgetKit

struct RefreshTrainIntent: AppIntent {
    static var title: LocalizedStringResource { "更新" }
    static var description: IntentDescription {
        IntentDescription("時刻表と運行状況を取り直します。")
    }

    static var openAppWhenRun: Bool { false }

    @Parameter(title: "選択")
    var selectionID: String?

    init() {}

    init(selectionID: String?) {
        self.selectionID = selectionID
    }

    func perform() async throws -> some IntentResult {
        AppSettings.notifyManualRefreshRequested()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct TogglePauseIntent: AppIntent {
    static var title: LocalizedStringResource { "自動更新の停止と再開" }
    static var description: IntentDescription {
        IntentDescription("情報の自動更新を一時停止、または再開します。")
    }

    static var openAppWhenRun: Bool { false }

    init() {}

    func perform() async throws -> some IntentResult {
        AppSettings.isPaused = !AppSettings.isPaused
        AppSettings.notifyPauseStateChanged()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// macOS のインタラクティブ・ウィジェットでは `Link` / `widgetURL` がボタンに負ける。
/// 拡張から URL は開けないので、メニューバー常駐へ通知してブラウザで開く。
/// 常駐が落ちていても起動してから開くため、一時停止・更新と違って `openAppWhenRun` は true。
struct OpenLineStatusIntent: AppIntent {
    static var title: LocalizedStringResource { "運行情報を見る" }
    static var description: IntentDescription {
        IntentDescription("Yahoo!路線情報の運行情報ページを開きます。")
    }
    static var openAppWhenRun: Bool { true }
    static var isDiscoverable: Bool { false }

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$lineID) \(\.$yahooDiaInfoID) の運行情報を見る")
    }

    /// `title: "路線"` だと `SelectStationIntent.line`（LineEntity）と同じ見出しになり、
    /// ウィジェット設定の路線解決（メトロ先頭＝銀座線）に巻き込まれる。
    @Parameter(title: "路線コード")
    var lineID: String

    @Parameter(title: "Yahoo運行情報ID")
    var yahooDiaInfoID: Int

    init() {
        lineID = ""
        yahooDiaInfoID = 0
    }

    init(line: LineID) {
        lineID = line.rawValue
        yahooDiaInfoID = line.yahooDiaInfoID
    }

    func perform() async throws -> some IntentResult {
        guard let url = statusPageURL else { return .result() }
        subwayLogger.debug("open status requested line=\(self.lineID, privacy: .public) id=\(self.yahooDiaInfoID, privacy: .public) url=\(url.absoluteString, privacy: .public)")
        AppSettings.notifyOpenStatusPage(url: url)
        return .result()
    }

    var statusPageURL: URL? {
        if yahooDiaInfoID > 0 {
            return ToeiConfig.statusURL(yahooDiaInfoID: yahooDiaInfoID)
        }
        return LineID(rawValue: lineID).map { ToeiConfig.statusURL(for: $0) }
    }
}
