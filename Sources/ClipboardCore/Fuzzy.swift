import Foundation

/// 一次模糊匹配的结果。`ranges` 指向 `target.string`,高亮时用 `nsRanges(clampedTo:)`。
public struct FuzzyMatch: Sendable {
    public let score: Int
    /// 命中字符区间(连续命中已合并),索引属于 `target.string`。
    public let ranges: [Range<String.Index>]
    public let target: RowText

    /// 转为 `target.string` 上的 NSRange;`length` 为实际要高亮的字符串的 UTF-16 长度,越界部分会被裁掉。
    public func nsRanges(clampedTo length: Int? = nil) -> [NSRange] {
        Highlight.nsRanges(ranges, in: target, clampedTo: length)
    }
}

/// 子序列模糊匹配:query 的每个字符按顺序在目标中出现即命中(不区分大小写)。
/// 每个命中字符基础分 4;与上一个命中字符相邻 +8;位于词边界(串首或前一字符属于边界字符集)+4。
/// 以字符簇(Character)为单位匹配,高亮区间不会切开 emoji / 组合字符。
public enum Fuzzy {
    public static let baseScore = 4
    public static let consecutiveBonus = 8
    public static let boundaryBonus = 4
    public static let boundaryCharacters: Set<Character> = Set(" /_-.,:;()[]{}\"'")

    /// 在列表行文本上匹配。空 query 返回分数 0、无区间的结果;不命中返回 nil。
    public static func match(_ query: String, in target: RowText) -> FuzzyMatch? {
        guard let (score, ranges) = match(query, in: target.string) else { return nil }
        return FuzzyMatch(score: score, ranges: ranges, target: target)
    }

    /// 过滤并按分数降序排列;同分保持原顺序(即 pinned / created_at 顺序)。空 query 返回全部。
    public static func rank<T>(_ query: String, _ items: [T], rowText: (T) -> RowText) -> [(item: T, match: FuzzyMatch)] {
        var results: [(offset: Int, item: T, match: FuzzyMatch)] = []
        for (offset, item) in items.enumerated() {
            if let m = match(query, in: rowText(item)) {
                results.append((offset, item, m))
            }
        }
        results.sort { a, b in
            a.match.score != b.match.score ? a.match.score > b.match.score : a.offset < b.offset
        }
        return results.map { ($0.item, $0.match) }
    }

    /// 第一个起点之后,其余候选起点共享的扫描步数上限,避免超长文本上退化为平方复杂度。
    static let extraStartBudget = 20_000

    /// 从 query 首字符的每个出现位置各做一次贪心匹配,取最高分(同分取最靠前)。
    static func match(_ query: String, in string: String) -> (score: Int, ranges: [Range<String.Index>])? {
        let needle = query.map(Folded.init)
        guard !needle.isEmpty else { return (0, []) }
        let maxScore = needle.count * (baseScore + boundaryBonus) + (needle.count - 1) * consecutiveBonus

        var best: (score: Int, ranges: [Range<String.Index>])?
        var budget = extraStartBudget
        var previous: Character?
        var idx = string.startIndex
        while idx < string.endIndex {
            let ch = string[idx]
            if needle[0].matches(ch) {
                let isFirst = best == nil
                var steps = 0
                // 某起点无法匹配完整,则更靠后的起点也不可能
                guard let run = greedy(needle, in: string, from: idx, previous: previous, steps: &steps) else { break }
                if isFirst || run.score > best!.score { best = run }
                if !isFirst { budget -= steps }
                if run.score >= maxScore || budget <= 0 { break }
            }
            previous = ch
            idx = string.index(after: idx)
        }
        return best
    }

    private static func greedy(_ needle: [Folded], in string: String, from start: String.Index,
                               previous initialPrevious: Character?, steps: inout Int) -> (score: Int, ranges: [Range<String.Index>])? {
        var score = 0
        var ranges: [Range<String.Index>] = []
        var qi = 0
        var previous = initialPrevious
        var previousMatched = false

        var idx = start
        while idx < string.endIndex, qi < needle.count {
            steps += 1
            let ch = string[idx]
            let next = string.index(after: idx)
            if needle[qi].matches(ch) {
                score += baseScore
                if previousMatched {
                    score += consecutiveBonus
                }
                if previous.map(boundaryCharacters.contains) ?? true {
                    score += boundaryBonus
                }
                if previousMatched, let last = ranges.last {
                    ranges[ranges.count - 1] = last.lowerBound..<next
                } else {
                    ranges.append(idx..<next)
                }
                qi += 1
                previousMatched = true
            } else {
                previousMatched = false
            }
            previous = ch
            idx = next
        }
        return qi == needle.count ? (score, ranges) : nil
    }
}

/// 预先折叠大小写的 query 字符。
private struct Folded {
    let raw: Character
    let lower: String

    init(_ ch: Character) {
        raw = ch
        lower = ch.lowercased()
    }

    func matches(_ ch: Character) -> Bool {
        if ch == raw { return true }
        if let a = ch.asciiValue, raw.isASCII {
            return a | 0x20 == (raw.asciiValue! | 0x20) && ch.isLetter && raw.isLetter
        }
        return ch.lowercased() == lower
    }
}

/// 高亮区间转换。所有转换都做边界检查,保证生成的 NSRange 不会越界。
public enum Highlight {
    /// 把 `rowText.string` 上的区间转换为 NSRange。
    /// 不属于该字符串(越界)的区间被丢弃;若给出 `length`,结果再裁剪到 `0..<length`,长度为 0 的结果被丢弃。
    public static func nsRanges(_ ranges: [Range<String.Index>], in rowText: RowText, clampedTo length: Int? = nil) -> [NSRange] {
        let s = rowText.string
        let utf16 = s.utf16
        let total = utf16.count
        let limit = max(0, min(length ?? total, total))
        var out: [NSRange] = []
        out.reserveCapacity(ranges.count)
        for r in ranges {
            guard r.lowerBound >= s.startIndex, r.upperBound <= s.endIndex,
                  let lo = r.lowerBound.samePosition(in: utf16),
                  let hi = r.upperBound.samePosition(in: utf16) else { continue }
            let start = utf16.distance(from: utf16.startIndex, to: lo)
            let end = utf16.distance(from: utf16.startIndex, to: hi)
            let clampedStart = min(max(start, 0), limit)
            let clampedEnd = min(max(end, clampedStart), limit)
            if clampedEnd > clampedStart {
                out.append(NSRange(location: clampedStart, length: clampedEnd - clampedStart))
            }
        }
        return out
    }
}
