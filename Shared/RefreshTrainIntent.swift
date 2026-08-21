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

    @Parameter(title: "路線")
    var lineID: String

    init() {
        lineID = SelectionKey.default.line.rawValue
    }

    init(line: LineID) {
        lineID = line.rawValue
    }

    func perform() async throws -> some IntentResult {
        guard let line = LineID(rawValue: lineID) else { return .result() }
        subwayLogger.debug("open status requested line=\(line.rawValue, privacy: .public)")
        AppSettings.notifyOpenStatusPage(line: line)
        return .result()
    }
}
