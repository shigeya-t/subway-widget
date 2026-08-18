import CoreGraphics
import Foundation

/// 小ウィジェットは幅が渡らず `lineLimit` だけでは省略される。中黒と文字数で改行位置を決める。
enum WidgetNameFit {
    static let smallMaxCharsPerLine = 8
    static let smallMaxLines = 3

    struct Layout: Equatable {
        var lines: [String]
        var text: String { lines.joined(separator: "\n") }
        var lineCount: Int { max(1, lines.count) }
        var longestLine: Int { lines.map(\.count).max() ?? 0 }
    }

    static func layout(
        _ text: String,
        smallWidget: Bool,
        maxLines: Int = smallMaxLines
    ) -> Layout {
        let capped = max(1, maxLines)
        guard smallWidget, text.count > smallMaxCharsPerLine else {
            return Layout(lines: [text])
        }
        let parts = text.split(separator: "・", omittingEmptySubsequences: false).map(String.init)
        let packed = parts.count >= 2
            ? pack(parts, maxChars: smallMaxCharsPerLine)
            : chunk(text, size: smallMaxCharsPerLine)
        let separator = parts.count >= 2 ? "・" : ""
        return Layout(lines: merge(packed, into: capped, separator: separator))
    }

    static func fontSize(
        layout: Layout,
        base: CGFloat,
        smallWidget: Bool
    ) -> CGFloat {
        guard smallWidget else {
            return layout.longestLine > 16 ? max(12, base - 3) : base
        }
        if layout.lineCount == 1 {
            return layout.longestLine <= smallMaxCharsPerLine ? base : min(base, 11)
        }
        if layout.lineCount == 2 { return 10 }
        return 8
    }

    /// ヘッダがすでに複数行なら、行き先の折り返しを抑えて小ウィジェットの縦を収める。
    static func destinationMaxLines(headerLineCount: Int) -> Int {
        max(1, smallMaxLines + 1 - max(1, headerLineCount))
    }

    /// 8文字を超えたら次の行へ。行数の上限はかけない（後で `merge` する）。
    private static func pack(_ parts: [String], maxChars: Int) -> [String] {
        var lines: [String] = []
        var current = ""
        for part in parts {
            let candidate = current.isEmpty ? part : "\(current)・\(part)"
            if !current.isEmpty, candidate.count > maxChars {
                lines.append(current)
                current = part
            } else {
                current = candidate
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }
        return lines
    }

    private static func chunk(_ text: String, size: Int) -> [String] {
        guard size > 0, text.count > size else { return [text] }
        var lines: [String] = []
        var rest = text
        while rest.count > size {
            let index = rest.index(rest.startIndex, offsetBy: size)
            lines.append(String(rest[..<index]))
            rest = String(rest[index...])
        }
        if !rest.isEmpty {
            lines.append(rest)
        }
        return lines
    }

    private static func merge(_ lines: [String], into maxLines: Int, separator: String) -> [String] {
        guard lines.count > maxLines else { return lines }
        var result = lines
        while result.count > maxLines {
            let overflow = result.removeLast()
            let glue = separator.isEmpty ? "" : separator
            result[result.count - 1] = "\(result[result.count - 1])\(glue)\(overflow)"
        }
        return result
    }
}
