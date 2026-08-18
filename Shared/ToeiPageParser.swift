import Foundation
import SwiftSoup

enum ToeiPageParser {
    /// Yahoo!路線情報の駅時刻表から1枚の表を取り出す。
    static func parseTimetable(_ html: String, kind: ScheduleKind) throws -> TimetableTable {
        let document = try SwiftSoup.parse(html)
        let (caption, directionLabel) = captionAndDirection(in: document, fallbackHTML: html, kind: kind)
        let legend = parseLegend(document)
        let defaultDestination = stripSuffix(legend[""] ?? directionLabel)
        let trains = parseTrains(in: document, legend: legend, defaultDestination: defaultDestination)
        guard !trains.isEmpty else {
            throw ToeiAPIError.emptyResponse
        }
        return TimetableTable(
            kind: kind,
            caption: caption,
            directionLabel: directionLabel,
            trains: trains,
            defaultDestination: defaultDestination
        )
    }

    /// 関東の運行情報ページから都営4路線を取る。
    static func parseStatuses(_ html: String, observedAt: Date = Date()) -> [LineID: LineStatus] {
        var result: [LineID: LineStatus] = [:]
        for line in LineID.allCases {
            result[line] = status(for: line, in: html, observedAt: observedAt)
        }
        return result
    }

    static func status(for line: LineID, in html: String, observedAt: Date = Date()) -> LineStatus {
        if let document = try? SwiftSoup.parse(html),
           let parsed = status(for: line, in: document, observedAt: observedAt)
        {
            return parsed
        }
        return LineStatus(line: line, kind: .unknown, text: "運行状況を取得できません", observedAt: observedAt)
    }

    // MARK: - timetable

    private static func captionAndDirection(in document: Document, fallbackHTML: String, kind: ScheduleKind) -> (String, String) {
        if let title = try? document.title(), let direction = directionFromTitle(title) {
            return (title, direction)
        }
        if let selected = try? document.select("ul.navDayOfWeek li span").first()?.text(), !selected.isEmpty {
            return ("\(selected)：", selected)
        }
        return (kind.label, kind.label)
    }

    /// `勝どき駅(都営地下鉄大江戸線 大門・六本木方面)の時刻表`
    private static func directionFromTitle(_ title: String) -> String? {
        let patterns = [#"[\(（]([^)）]*方面)[\)）]"#]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
               let range = Range(match.range(at: 1), in: title)
            {
                let inside = String(title[range])
                if let last = inside.split(separator: " ").last.map(String.init), last.hasSuffix("方面") {
                    return last
                }
                if inside.hasSuffix("方面") { return inside }
            }
        }
        return nil
    }

    private static func parseLegend(_ document: Document) -> [String: String] {
        var legend: [String: String] = [:]
        let items = (try? document.select("table.tblDiaNote li, li")) ?? Elements()
        for item in items {
            guard let text = try? item.text() else { continue }
            let normalized = text.replacingOccurrences(of: ":", with: "：")
            guard normalized.contains("：") else { continue }
            let parts = normalized.split(separator: "：", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let mark = parts[0]
            let dest = stripParenthetical(parts[1])
            if mark == "無印" {
                legend[""] = dest
            } else if mark.count <= 2, mark != "△" {
                legend[mark] = dest
            }
        }
        return legend
    }

    private static func parseTrains(in document: Document, legend: [String: String], defaultDestination: String) -> [TrainDeparture] {
        var trains: [TrainDeparture] = []
        let rows = (try? document.select("table.tblDiaDetail tr[id^=hh_], tr[id^=hh_]")) ?? Elements()
        let source = rows.size() > 0 ? rows : ((try? document.select("tr")) ?? Elements())
        for row in source {
            guard let hour = hour(from: row) else { continue }
            let numbers = (try? row.select("li.timeNumb")) ?? Elements()
            if numbers.size() > 0 {
                for item in numbers {
                    trains.append(contentsOf: departures(
                        hour: hour,
                        item: item,
                        legend: legend,
                        defaultDestination: defaultDestination
                    ))
                }
                continue
            }
        }
        return trains
    }

    private static func hour(from row: Element) -> Int? {
        let id = row.id()
        if id.hasPrefix("hh_"), let value = Int(id.dropFirst(3)) {
            return normalizedHour(value)
        }
        let text = ((try? row.select("td.hour").first()?.text()) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Int(text) {
            return normalizedHour(value)
        }
        return nil
    }

    /// Yahoo は終電を `24` 時台で出す。0時台として持ち、24:00 以降の分数へ畳む。
    private static func normalizedHour(_ value: Int) -> Int? {
        if (0...23).contains(value) { return value }
        if value == 24 { return 0 }
        return nil
    }

    private static func departures(
        hour: Int,
        item: Element,
        legend: [String: String],
        defaultDestination: String
    ) -> [TrainDeparture] {
        let minuteText = ((try? item.select("dt").first()?.text()) ?? item.ownText())
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let minute = Int(minuteText), (0...59).contains(minute) else { return [] }
        let markText = ((try? item.select("dd.trainFor").text()) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let mark = markText.isEmpty || markText == "△" ? nil : String(markText.prefix(2))
        let destination: String
        if let mark, let named = legend[mark] {
            destination = named
        } else {
            destination = defaultDestination
        }
        let serviceMinutesBase = (hour < 3 ? hour + 24 : hour) * 60
        return [
            TrainDeparture(
                minutesFromMidnight: serviceMinutesBase + minute,
                mark: mark,
                destination: stripSuffix(destination)
            )
        ]
    }

    // MARK: - status

    private static func status(for line: LineID, in document: Document, observedAt: Date) -> LineStatus? {
        let href = "/diainfo/\(line.yahooDiaInfoID)/0"
        let links = (try? document.select("a[href]")) ?? Elements()
        for link in links {
            let attr = (try? link.attr("href")) ?? ""
            guard attr.contains(href) else { continue }
            var node: Element? = link
            var nearest = link
            while let current = node {
                if current.tagName() == "tr" {
                    nearest = current
                    break
                }
                node = current.parent()
            }
            let text = ((try? nearest.text()) ?? "").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            return classify(line: line, text: text, observedAt: observedAt)
        }
        return nil
    }

    private static func classify(line: LineID, text: String, observedAt: Date) -> LineStatus {
        let compact = text.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        if compact.contains("平常運転") || compact.contains("平常通り") || compact.contains("遅延情報はありません") {
            return LineStatus(line: line, kind: .normal, text: "平常運転", observedAt: observedAt)
        }
        let cleaned = compact
            .replacingOccurrences(of: "都営\(line.displayName)", with: "")
            .replacingOccurrences(of: line.displayName, with: "")
        let summary = cleaned.isEmpty ? "遅延情報があります" : String(cleaned.prefix(40))
        return LineStatus(line: line, kind: .delayed, text: summary, observedAt: observedAt)
    }

    private static func stripParenthetical(_ text: String) -> String {
        text.replacingOccurrences(of: "（[^）]*）", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripSuffix(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix("行") {
            value.removeLast()
        }
        if value.hasSuffix("方面") {
            value = String(value.dropLast(2))
        }
        return value
    }
}
