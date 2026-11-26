import Foundation
import Testing
@testable import SumKit

private func sum(_ lines: [String]) -> Decimal {
    NumberParser.parse(lines: lines).sum
}

@Suite("Parser kwot")
struct NumberParserTests {

    @Test("Kolumna kwot z wyciągu")
    func columnOfAmounts() {
        let lines = ["1 234,56", "-890,00", "12 135,99"]
        #expect(sum(lines) == Decimal(string: "12480.55"))
    }

    @Test("Kropka jako separator tysięcy")
    func dotAsThousands() {
        #expect(sum(["1.234,56", "2.000,00"]) == Decimal(string: "3234.56"))
    }

    @Test("Twarda i wąska spacja jako separator tysięcy")
    func hardSpaces() {
        #expect(sum(["1\u{00A0}000,00", "2\u{202F}500,50"]) == Decimal(string: "3500.50"))
    }

    @Test("Daty nie są sumowane")
    func datesIgnored() {
        let result = NumberParser.parse(lines: [
            "10.08.2026  Przelew  1 234,56",
            "2026-08-11  Opłata      -12,00",
        ])
        #expect(result.numbers.count == 2)
        #expect(result.sum == Decimal(string: "1222.56"))
    }

    @Test("Godziny nie są sumowane")
    func timesIgnored() {
        let result = NumberParser.parse(lines: ["12:34  Płatność kartą  99,90"])
        #expect(result.numbers.count == 1)
        #expect(result.sum == Decimal(string: "99.90"))
    }

    @Test("Numer konta i IBAN nie są sumowane")
    func accountNumbersIgnored() {
        let result = NumberParser.parse(lines: [
            "PL61 1090 1014 0000 0712 1981 2874",
            "Na konto 1090 1014 0000 0712 kwota 500,00",
        ])
        #expect(result.numbers.count == 1)
        #expect(result.sum == Decimal(string: "500.00"))
    }

    @Test("Procenty nie są sumowane")
    func percentagesIgnored() {
        let result = NumberParser.parse(lines: ["Prowizja 4,5 %  od  1 000,00"])
        #expect(result.numbers.count == 1)
        #expect(result.sum == Decimal(string: "1000.00"))
    }

    @Test("Nawiasy oznaczają kwotę ujemną")
    func parenthesesAreNegative() {
        #expect(sum(["(1 200,00)", "1 200,00"]) == 0)
    }

    @Test("Liczby całkowite odpadają, gdy większość kwot ma grosze")
    func integersDroppedAmongDecimals() {
        let result = NumberParser.parse(lines: ["Strona 2", "100,00", "200,50", "300,25"])
        #expect(result.numbers.count == 3)
        #expect(result.skipped.count == 1)
        #expect(result.sum == Decimal(string: "600.75"))
    }

    @Test("Same liczby całkowite są sumowane normalnie")
    func plainIntegersSummed() {
        let result = NumberParser.parse(lines: ["12", "30", "5"])
        #expect(result.skipped.isEmpty)
        #expect(result.sum == 47)
    }

    @Test("Waluta i opis w linii nie przeszkadzają")
    func currencySuffix() {
        #expect(sum(["1 234,56 PLN", "500,00 zł"]) == Decimal(string: "1734.56"))
    }

    @Test("Minus w wersji unicode")
    func unicodeMinus() {
        #expect(sum(["\u{2212}100,00", "150,00"]) == 50)
    }

    @Test("Jeden grosz po przecinku")
    func singleDecimalDigit() {
        #expect(sum(["10,5", "0,5"]) == 11)
    }

    @Test("Pusty tekst daje pusty wynik")
    func emptyInput() {
        let result = NumberParser.parse(lines: ["", "Wyciąg bankowy", "Saldo końcowe"])
        #expect(result.isEmpty)
    }

    @Test("Realistyczny fragment wyciągu")
    func realisticStatement() {
        let lines = [
            "Data operacji  Opis  Kwota  Saldo",
            "05.08.2026  BIEDRONKA 1234 WARSZAWA  -127,45",
            "06.08.2026  Przelew przychodzący  4 500,00",
            "07.08.2026  ORLEN S.A.  -312,80",
            "08.08.2026  Opłata za prowadzenie rachunku  -19,99",
        ]
        let result = NumberParser.parse(lines: lines)
        #expect(result.numbers.count == 4)
        #expect(result.sum == Decimal(string: "4039.76"))
    }

    @Test("Suma bezwzględna ignoruje znaki")
    func absoluteSum() {
        let result = NumberParser.parse(lines: ["-19,50 PLN", "-29,00 PLN", "-33,97 PLN", "-35,80 PLN"])
        #expect(result.sum == Decimal(string: "-118.27"))
        #expect(result.absoluteSum == Decimal(string: "118.27"))
        #expect(result.hasNegatives)
    }

    @Test("Suma bezwzględna przy mieszanych znakach")
    func absoluteSumMixed() {
        let result = NumberParser.parse(lines: ["100,00", "-40,00"])
        #expect(result.sum == 60)
        #expect(result.absoluteSum == 140)
    }

    @Test("Bez liczb ujemnych obie sumy są równe")
    func absoluteSumWithoutNegatives() {
        let result = NumberParser.parse(lines: ["10,50", "20,25"])
        #expect(result.sum == result.absoluteSum)
        #expect(!result.hasNegatives)
    }

    @Test("Formatowanie sumy")
    func formatting() {
        #expect(NumberFormat.display(Decimal(string: "12480.55")!) == "12\u{00A0}480,55")
        #expect(NumberFormat.clipboard(Decimal(string: "12480.55")!) == "12480,55")
    }
}
