import HenriqueCore
import Testing

@testable import HenriqueUI

@Suite("O dia em que a sequência zera")
struct StreakResetTests {
  // 21 de setembro de 2026 é segunda.
  private static func day(_ value: Int) -> CalendarDate {
    CalendarDate(year: 2026, month: 9, day: value)!
  }

  @Test("último treino na segunda zera no domingo")
  func sixDaysAfterLastWorkout() {
    #expect(streakResetDay(lastAttended: Self.day(21), today: Self.day(23)) == Self.day(27))
  }

  @Test("com treino hoje não há data")
  func trainedToday() {
    #expect(streakResetDay(lastAttended: Self.day(23), today: Self.day(23)) == nil)
  }

  @Test("sequência já zerada não ganha data")
  func alreadyBroken() {
    #expect(streakResetDay(lastAttended: Self.day(21), today: Self.day(27)) == nil)
    #expect(streakResetDay(lastAttended: nil, today: Self.day(27)) == nil)
  }
}
