import Foundation
import os

let subwayLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "jp.shigeya.SubwayWidget",
    category: "Data"
)

enum ToeiAPIError: LocalizedError {
    case invalidURL
    case httpStatus(Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URLを組み立てられません"
        case .httpStatus(let code): return "サーバーがエラーを返しました（HTTP \(code)）"
        case .emptyResponse: return "サーバーの応答が空です"
        }
    }
}

/// Yahoo!路線情報の公開 HTML。 Imperva のないこちらのページなら `URLSession` で取れる。
/// 型名の Toei は当初都営専用だった名残で、メトロも同じ経路で取る。
enum ToeiAPI {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15"

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

    static func timetableURL(line: LineID, stationCode: String, direction: String, kind: ScheduleKind) -> URL? {
        guard let station = ToeiCatalog.station(line: line, code: stationCode),
              let groupID = station.yahooGroupID(for: direction)
        else { return nil }
        return URL(string: "https://\(ToeiConfig.yahooHost)/timetable/\(station.yahooStationID)/\(groupID)?kind=\(kind.yahooKind)")
    }

    static func fetchTimetableHTML(line: LineID, stationCode: String, direction: String, kind: ScheduleKind) async throws -> String {
        guard let url = timetableURL(line: line, stationCode: stationCode, direction: direction, kind: kind) else {
            throw ToeiAPIError.invalidURL
        }
        return try await fetchHTML(url)
    }

    static func fetchStatusHTML() async throws -> String {
        try await fetchHTML(ToeiConfig.statusURL)
    }

    static func fetchHTML(_ url: URL) async throws -> String {
        subwayLogger.debug("GET \(url.absoluteString, privacy: .public)")
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("ja-JP,ja;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ToeiAPIError.httpStatus(http.statusCode)
        }
        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .shiftJIS)
            ?? ""
        if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ToeiAPIError.emptyResponse
        }
        return html
    }
}
