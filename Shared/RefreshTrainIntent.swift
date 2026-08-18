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
