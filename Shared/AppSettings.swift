import Foundation
import Security

extension Notification.Name {
    static let toeiPauseStateChanged = Notification.Name("jp.shigeya.SubwayWidget.pauseStateChanged")
    static let toeiManualRefreshRequested = Notification.Name("jp.shigeya.SubwayWidget.manualRefreshRequested")
}

enum AppSettings {
    private static let groupSuffix = "jp.shigeya.SubwayWidget"

    /// App Group は macOS では Team ID プレフィックスが必須。
    /// `$(DEVELOPMENT_TEAM)` が空のままだと `.jp.shigeya.SubwayWidget` になり共有できない。
    static let appGroupID: String = {
        let plist = (Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidGroupID(plist) { return plist }
        if let team = signingTeamID() {
            let resolved = "\(team).\(groupSuffix)"
            toeiLogger.error("Info.plist の AppGroupID が不正（\(plist, privacy: .public)）のため署名から組み立てます: \(resolved, privacy: .public)")
            return resolved
        }
        toeiLogger.error("App Group を利用できません（AppGroupID=\(plist, privacy: .public)）")
        return plist
    }()

    private static func isValidGroupID(_ value: String) -> Bool {
        !value.isEmpty && !value.hasPrefix(".") && value.contains(".")
    }

    static var isUsingAppGroup: Bool { isValidGroupID(appGroupID) }

    private static func signingTeamID() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any]
        else { return nil }
        if let team = dict[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty {
            return team
        }
        if let entitlements = dict[kSecCodeInfoEntitlementsDict as String] as? [String: Any] {
            if let team = entitlements["com.apple.developer.team-identifier"] as? String, !team.isEmpty {
                return team
            }
            if let appID = entitlements["com.apple.application-identifier"] as? String,
               let team = appID.split(separator: ".").first.map(String.init),
               team.count >= 8
            {
                return team
            }
        }
        return nil
    }

    private static var defaults: UserDefaults {
        guard isValidGroupID(appGroupID), let shared = UserDefaults(suiteName: appGroupID) else {
            return .standard
        }
        return shared
    }

    private enum Keys {
        static let isPaused = "isPaused"
        static let line = "selectedLine"
        static let station = "selectedStation"
        static let direction = "selectedDirection"
        static let holidays = "holidays"
        static func schedule(_ id: String) -> String { "schedule.\(id)" }
        static func status(_ line: String) -> String { "status.\(line)" }
        static func directionLabel(_ id: String) -> String { "directionLabel.\(id)" }
        static let neededSelections = "neededSelections"
    }

    static var isPaused: Bool {
        get { defaults.bool(forKey: Keys.isPaused) }
        set {
            defaults.set(newValue, forKey: Keys.isPaused)
            defaults.synchronize()
        }
    }

    static func notifyPauseStateChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            .toeiPauseStateChanged,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    static func notifyManualRefreshRequested() {
        DistributedNotificationCenter.default().postNotificationName(
            .toeiManualRefreshRequested,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    static var selectedKey: SelectionKey? {
        get {
            guard let lineRaw = defaults.string(forKey: Keys.line),
                  let line = LineID(rawValue: lineRaw),
                  let station = defaults.string(forKey: Keys.station),
                  let direction = defaults.string(forKey: Keys.direction)
            else { return nil }
            return SelectionKey(line: line, stationCode: station, direction: direction)
        }
        set {
            defaults.set(newValue?.line.rawValue, forKey: Keys.line)
            defaults.set(newValue?.stationCode, forKey: Keys.station)
            defaults.set(newValue?.direction, forKey: Keys.direction)
            defaults.synchronize()
        }
    }

    static func saveHolidays(_ holidays: Set<String>) {
        defaults.set(Array(holidays), forKey: Keys.holidays)
        defaults.synchronize()
    }

    static var holidays: Set<String> {
        Set(defaults.stringArray(forKey: Keys.holidays) ?? [])
    }

    static func saveSchedule(_ timetable: StationTimetable, selectionID: String) {
        guard !timetable.isEmpty else {
            defaults.removeObject(forKey: Keys.schedule(selectionID))
            defaults.synchronize()
            return
        }
        guard let data = try? JSONEncoder().encode(timetable) else { return }
        defaults.set(data, forKey: Keys.schedule(selectionID))
        if !timetable.directionLabel.isEmpty {
            defaults.set(timetable.directionLabel, forKey: Keys.directionLabel(selectionID))
        }
        defaults.synchronize()
    }

    static func schedule(selectionID: String) -> StationTimetable? {
        guard let data = defaults.data(forKey: Keys.schedule(selectionID)) else { return nil }
        return try? JSONDecoder().decode(StationTimetable.self, from: data)
    }

    static func directionLabel(selectionID: String) -> String? {
        defaults.string(forKey: Keys.directionLabel(selectionID)).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func saveStatus(_ status: LineStatus) {
        guard let data = try? JSONEncoder().encode(status) else { return }
        defaults.set(data, forKey: Keys.status(status.line.rawValue))
        defaults.synchronize()
    }

    static func status(line: LineID) -> LineStatus? {
        guard let data = defaults.data(forKey: Keys.status(line.rawValue)) else { return nil }
        return try? JSONDecoder().decode(LineStatus.self, from: data)
    }

    /// ウィジェットが設定した駅×方面。getCurrentConfigurations が取れないときでもホストが時刻表を取りに行く。
    static var neededSelections: [SelectionKey] {
        guard let data = defaults.data(forKey: Keys.neededSelections),
              let keys = try? JSONDecoder().decode([SelectionKey].self, from: data)
        else { return [] }
        return keys
    }

    static func noteNeededSelection(_ key: SelectionKey) {
        var keys = neededSelections
        guard !keys.contains(key) else { return }
        keys.append(key)
        guard let data = try? JSONEncoder().encode(keys) else { return }
        defaults.set(data, forKey: Keys.neededSelections)
        defaults.synchronize()
    }
}
