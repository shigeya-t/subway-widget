import Foundation

enum HolidayChecker {
    private static let apiURL = URL(string: "https://holidays-jp.github.io/api/v1/date.json")!
    private static let cache = HolidayCache()

    static func holidays() async -> Set<String> {
        (try? await fetchHolidays()) ?? []
    }

    /// 指定日のダイヤ区分。祝日取得に失敗した場合は曜日のみで判定する。
    static func kind(for date: Date) async -> ScheduleKind {
        ScheduleKind.kind(for: date, holidays: await holidays())
    }

    private static func fetchHolidays() async throws -> Set<String> {
        if let cached = await cache.value() { return cached }
        let (data, _) = try await URLSession.shared.data(from: apiURL)
        let map = try JSONDecoder().decode([String: String].self, from: data)
        let keys = Set(map.keys)
        await cache.store(keys)
        return keys
    }
}

private actor HolidayCache {
    private var holidays: Set<String>?
    private var fetchedAt: Date?
    private let lifetime: TimeInterval = 24 * 60 * 60

    func value() -> Set<String>? {
        guard let holidays, let fetchedAt, Date().timeIntervalSince(fetchedAt) < lifetime else { return nil }
        return holidays
    }

    func store(_ holidays: Set<String>) {
        self.holidays = holidays
        self.fetchedAt = Date()
    }
}
