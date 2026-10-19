import Foundation
import Testing

@testable import HenriqueCore

/// Setembro de 2026: segunda é 7, terça 8, domingo 13 e segunda 14.
@Suite("O dia em que a sequência zera")
struct StreakResetDayTests {
  private static func day(_ value: Int) -> CalendarDate {
    CalendarDate(year: 2026, month: 9, day: value)!
  }

  private static func dashboard(
    today: Int, plan: [Int], sessions: [Int], streak: Int = 3
  ) -> Dashboard {
    Dashboard(
      date: day(today), workout: nil, consistencyPercent: 0, currentStreak: streak,
      attendanceStreak: streak, weeklyCompleted: 0, weeklyPlanned: 0,
      weekPlan: plan.isEmpty ? [] : [
        WeekPlanItem(
          id: "tpl", weekdays: plan, name: "Pernas", focus: "", exerciseCount: 0, exercises: [])
      ],
      sessionDates: sessions.map(day), exerciseCatalog: [], strengthGoal: nil, progress: [],
      measurements: [], projection: nil, onboardingCompleted: true)
  }

  private static func reset(today: Int, plan: [Int], sessions: [Int], streak: Int = 3) -> CalendarDate? {
    dashboard(today: today, plan: plan, sessions: sessions, streak: streak)
      .streakResetDay(lastAttended: sessions.map(day).max(), today: day(today))
  }

  @Test("sem plano, zera seis dias depois do último treino")
  func gapOnly() {
    #expect(Self.reset(today: 8, plan: [], sessions: [7]) == Self.day(13))
  }

  @Test("hoje planejado e sem treino zera amanhã, não no fim do intervalo")
  func plannedTodayResetsTomorrow() {
    #expect(Self.reset(today: 8, plan: [2], sessions: [5]) == Self.day(9))
  }

  @Test("o próximo dia do plano zera no dia seguinte a ele")
  func nextPlannedDay() {
    #expect(Self.reset(today: 8, plan: [4], sessions: [6]) == Self.day(11))
  }

  @Test("o dia do plano da semana seguinte também conta")
  func plannedNextWeek() {
    #expect(Self.reset(today: 13, plan: [1], sessions: [7, 12]) == Self.day(15))
  }

  @Test("a data do servidor vence a conta local")
  func serverWins() {
    var data = Self.dashboard(today: 8, plan: [2], sessions: [5])
    data.streakResetsOn = Self.day(12)
    #expect(data.streakResetDay(lastAttended: Self.day(5), today: Self.day(8)) == Self.day(12))
  }

  @Test("sequência em 0 não ganha data")
  func alreadyBroken() {
    #expect(Self.reset(today: 8, plan: [], sessions: [7], streak: 0) == nil)
  }
}
