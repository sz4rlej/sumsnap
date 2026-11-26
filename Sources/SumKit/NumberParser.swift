import Foundation

/// Pojedyncza liczba znaleziona w tekście z OCR.
public struct FoundNumber: Equatable, Sendable {
    public let value: Decimal
    /// Fragment tekstu, z którego liczba została odczytana (do podglądu w menu).
    public let raw: String
    public let hasDecimals: Bool

    public init(value: Decimal, raw: String, hasDecimals: Bool) {
        self.value = value
        self.raw = raw
        self.hasDecimals = hasDecimals
    }
}

public struct ParseResult: Equatable, Sendable {
    public let numbers: [FoundNumber]
    /// Liczby odrzucone przez filtr "tylko kwoty z groszami".
    public let skipped: [FoundNumber]

    /// Suma ze znakami — wpływy minus wydatki.
    public var sum: Decimal { numbers.reduce(Decimal(0)) { $0 + $1.value } }

    /// Suma wartości bezwzględnych — ile łącznie „przeszło", niezależnie od kierunku.
    public var absoluteSum: Decimal { numbers.reduce(Decimal(0)) { $0 + $1.value.magnitude } }

    /// Suma wpływów (liczb dodatnich).
    public var positiveSum: Decimal { numbers.filter { $0.value > 0 }.reduce(Decimal(0)) { $0 + $1.value } }

    /// Suma wydatków (liczb ujemnych), jako liczba ujemna.
    public var negativeSum: Decimal { numbers.filter { $0.value < 0 }.reduce(Decimal(0)) { $0 + $1.value } }

    public var isEmpty: Bool { numbers.isEmpty }
    public var hasNegatives: Bool { numbers.contains { $0.value < 0 } }

    public init(numbers: [FoundNumber], skipped: [FoundNumber]) {
        self.numbers = numbers
        self.skipped = skipped
    }
}

/// Parser kwot w formacie polskim: `1 234,56`, `1.234,56`, `-890,00`, `(1 200,00)`.
///
/// Przed szukaniem liczb usuwa z tekstu wzorce, które na wyciągu bankowym
/// prawie nigdy nie są kwotą: daty, godziny, procenty, numery kont i inne
/// długie ciągi cyfr.
public enum NumberParser {

    // MARK: - API

    public static func parse(lines: [String]) -> ParseResult {
        var all: [FoundNumber] = []
        for line in lines {
            all.append(contentsOf: numbers(in: line))
        }
        return applyDecimalHeuristic(to: all)
    }

    public static func parse(text: String) -> ParseResult {
        parse(lines: text.components(separatedBy: .newlines))
    }

    // MARK: - Heurystyka "grosze"

    /// Na wyciągach bankowych kwoty mają grosze. Jeśli większość znalezionych
    /// liczb ma część dziesiętną, całkowite traktujemy jako śmieci z OCR
    /// (numery stron, LP, salda bez groszy itp.) i odrzucamy je.
    static func applyDecimalHeuristic(to all: [FoundNumber]) -> ParseResult {
        guard !all.isEmpty else { return ParseResult(numbers: [], skipped: []) }

        let withDecimals = all.filter(\.hasDecimals)
        let ratio = Double(withDecimals.count) / Double(all.count)

        if withDecimals.count >= 2 && ratio >= 0.6 {
            return ParseResult(numbers: withDecimals, skipped: all.filter { !$0.hasDecimals })
        }
        return ParseResult(numbers: all, skipped: [])
    }

    // MARK: - Czyszczenie linii

    private static let noise: [NSRegularExpression] = [
        // 2026-08-10 / 2026/08/10
        re(#"\b\d{4}[./-]\d{1,2}[./-]\d{1,2}\b"#),
        // 10.08.2026 / 10-08-26 / 10/08/2026
        re(#"\b\d{1,2}[./-]\d{1,2}[./-]\d{2,4}\b"#),
        // 12:34 / 12:34:56
        re(#"\b\d{1,2}:\d{2}(?::\d{2})?\b"#),
        // 4,5 % / 12%
        re(#"\b\d+(?:[.,]\d+)?\s?%"#),
        // IBAN: PL61 1090 1014 0000 0712 1981 2874
        re(#"\b[A-Z]{2}\s?\d{2}(?:[\s-]?\d{2,4}){4,}\b"#),
        // numer konta / karty w grupach: 1090 1014 0000 0712
        re(#"\b\d{4}(?:[\s-]\d{2,4}){3,}\b"#),
        // długie ciągi cyfr bez groszy: numery dokumentów, NIP, telefony
        re(#"(?<![\d,.])\d{9,}(?![\d]*,\d)"#),
    ]

    static func stripNoise(_ line: String) -> String {
        var text = normalize(line)
        for regex in noise {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
        }
        return text
    }

    /// Ujednolica znaki, które OCR i eksporty bankowe potrafią wstawić:
    /// twarde/wąskie spacje, minusy w wersji unicode, apostrof jako separator tysięcy.
    static func normalize(_ line: String) -> String {
        var out = ""
        out.reserveCapacity(line.count)
        for ch in line {
            switch ch {
            case "\u{00A0}", "\u{202F}", "\u{2009}", "\u{2007}", "\u{2019}", "'":
                out.append(" ")
            case "\u{2212}", "\u{2013}", "\u{2014}":
                out.append("-")
            default:
                out.append(ch)
            }
        }
        return out
    }

    // MARK: - Wyszukiwanie liczb

    // grupa 1: znak, grupa 2: część całkowita (opcjonalnie z separatorami tysięcy), grupa 3: grosze
    private static let numberRegex = re(
        #"(?<![\d,.])(-\s?)?(\d{1,3}(?:[ .]\d{3})+|\d{1,9})(?:,(\d{1,2}))?(?![\d])"#
    )

    static func numbers(in line: String) -> [FoundNumber] {
        let text = stripNoise(line)
        let nsText = text as NSString
        let matches = numberRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        var result: [FoundNumber] = []
        for match in matches {
            let raw = nsText.substring(with: match.range)

            let intPart = group(match, 2, in: nsText)
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: ".", with: "")
            guard !intPart.isEmpty, var value = Decimal(string: intPart) else { continue }

            let fraction = group(match, 3, in: nsText)
            let hasDecimals = !fraction.isEmpty
            if hasDecimals, let frac = Decimal(string: fraction) {
                value += frac / (fraction.count == 1 ? 10 : 100)
            }

            var negative = !group(match, 1, in: nsText).isEmpty
            if !negative, isWrappedInParens(match.range, in: nsText) { negative = true }
            if negative { value.negate() }

            result.append(FoundNumber(value: value, raw: raw.trimmingCharacters(in: .whitespaces), hasDecimals: hasDecimals))
        }
        return result
    }

    /// `(1 200,00)` w tabelach księgowych oznacza kwotę ujemną.
    private static func isWrappedInParens(_ range: NSRange, in text: NSString) -> Bool {
        guard range.location > 0, range.location + range.length < text.length else { return false }
        let before = text.substring(with: NSRange(location: range.location - 1, length: 1))
        let after = text.substring(with: NSRange(location: range.location + range.length, length: 1))
        return before == "(" && after == ")"
    }

    // MARK: - Pomocnicze

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in text: NSString) -> String {
        let range = match.range(at: index)
        guard range.location != NSNotFound else { return "" }
        return text.substring(with: range).trimmingCharacters(in: .whitespaces)
    }

    private static func re(_ pattern: String) -> NSRegularExpression {
        // Wzorce są stałymi w kodzie — błąd kompilacji regexu to błąd programisty.
        try! NSRegularExpression(pattern: pattern)
    }
}

// MARK: - Formatowanie

public enum NumberFormat {
    /// Do wyświetlenia: `12 480,55`
    public static func display(_ value: Decimal) -> String {
        formatter(grouping: true).string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    /// Do schowka: `12480,55` — wkleja się wprost do Excela/Numbers w polskiej lokalizacji.
    public static func clipboard(_ value: Decimal) -> String {
        formatter(grouping: false).string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    private static func formatter(grouping: Bool) -> NumberFormatter {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = grouping
        f.groupingSeparator = "\u{00A0}"
        f.decimalSeparator = ","
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }
}
