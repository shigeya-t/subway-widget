import Foundation

enum TrainStatusService {
    private static let cache = StatusCache()

    static func fetchStatuses(force: Bool = false) async throws -> [LineID: LineStatus] {
        if !force, let cached = await cache.value() {
            return cached
        }
        let html = try await ToeiAPI.fetchStatusHTML()
        let statuses = ToeiPageParser.parseStatuses(html)
        await cache.store(statuses)
        return statuses
    }
}

private actor StatusCache {
    private var statuses: [LineID: LineStatus]?
    private var fetchedAt: Date?
    private let lifetime: TimeInterval = 50

    func value() -> [LineID: LineStatus]? {
        guard let statuses, let fetchedAt, Date().timeIntervalSince(fetchedAt) < lifetime else { return nil }
        return statuses
    }

    func store(_ statuses: [LineID: LineStatus]) {
        self.statuses = statuses
        self.fetchedAt = Date()
    }
}
