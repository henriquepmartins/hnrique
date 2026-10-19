import Foundation
import Testing

@testable import HenriqueCore

@Suite("Dia, data e duração com uma grafia só")
struct DayFormattingTests {
  private static func day(_ iso: String) -> CalendarDate { CalendarDate(iso: iso)! }

  @Test(
    "dia da semana em minúsculas e sem ponto",
    arguments: [("2026-10-19", "seg"), ("2026-10-24", "sáb"), ("2026-10-25", "dom")])
  func weekday(iso: String, expected: String) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    #expect(Formatting.weekday(Self.day(iso), in: calendar) == expected)
  }

  @Test("data curta ganha o ano só fora do ano corrente")
  func shortDate() {
    let today = Self.day("2026-01-05")
    #expect(Formatting.shortDate(Self.day("2026-01-02"), today: today) == "2 jan")
    #expect(Formatting.shortDate(Self.day("2025-12-29"), today: today) == "29 dez 2025")
  }

  @Test(
    "estimativa e tempo real com a mesma grafia",
    arguments: [(25, "25 min"), (60, "1 h"), (62, "1 h 2 min")])
  func minutes(minutes: Int, expected: String) {
    #expect(Formatting.duration(minutes: minutes) == expected)
  }

  @Test("o tempo real arredonda para o minuto e não some abaixo de um")
  func seconds() {
    #expect(Formatting.duration(seconds: 694) == "12 min")
    #expect(Formatting.duration(seconds: 3_730) == "1 h 2 min")
    #expect(Formatting.duration(seconds: 20) == "1 min")
  }
}
