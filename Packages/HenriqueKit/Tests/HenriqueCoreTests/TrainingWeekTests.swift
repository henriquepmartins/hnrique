import Foundation
import Testing

@testable import HenriqueCore

/// Semana de 14 (segunda) a 20 (domingo) de setembro de 2026. O plano treina
/// segunda (a), quarta (b) e sexta (c).
@Suite("A semana do treino")
struct TrainingWeekTests {
  private static let plan = [item("a", [1]), item("b", [3]), item("c", [5])]

  private static func item(_ id: String, _ weekdays: [Int]) -> WeekPlanItem {
    WeekPlanItem(
      id: id, weekdays: weekdays, name: id, focus: "", exerciseCount: 0, exercises: [],
      estimatedMinutes: 45)
  }

  private static func day(_ value: Int) -> CalendarDate {
    CalendarDate(year: 2026, month: 9, day: value)!
  }

  private func week(attended: [Int], today: Int) -> TrainingWeek {
    TrainingWeek(
      schedule: PlanSchedule(plan: Self.plan, swaps: []),
      attended: Set(attended.map(Self.day)), today: Self.day(today))
  }

  private func states(_ week: TrainingWeek) -> [String: TrainingWeek.State] {
    Dictionary(uniqueKeysWithValues: week.slots.map { ($0.date.iso, $0.state) })
  }

  @Test("só terça feita, hoje quinta: a terça cobre a segunda e a quarta fica perdida")
  func tuesdayCoversMonday() {
    let week = week(attended: [15], today: 17)
    #expect(week.monday == Self.day(14))
    #expect(week.planned == 3)
    #expect(week.done == 1)
    #expect(
      states(week) == ["2026-09-14": .done, "2026-09-16": .missed, "2026-09-18": .upcoming])
  }

  @Test("terça e quinta feitas, hoje quinta: segunda e quarta cobertas")
  func twoDaysCoverTwoSlots() {
    let week = week(attended: [15, 17], today: 17)
    #expect(week.done == 2)
    #expect(
      states(week) == ["2026-09-14": .done, "2026-09-16": .done, "2026-09-18": .upcoming])
  }

  @Test("terça, quinta e sexta feitas, hoje sexta: a semana fecha")
  func weekCloses() {
    let week = week(attended: [15, 17, 18], today: 18)
    #expect(week.done == 3)
    #expect(week.slots.map(\.state) == [.done, .done, .done])
  }

  @Test("sábado extra não passa de 3 de 3")
  func extraDayIsCapped() {
    let week = week(attended: [15, 17, 18, 19], today: 19)
    #expect(week.attended.count == 4)
    #expect(week.done == 3)
    #expect(week.slots.map(\.state) == [.done, .done, .done])
  }

  @Test("hoje planejado e sem treino fica como hoje; o domingo anterior e o futuro não contam")
  func todayAndOutsideDays() {
    let week = week(attended: [13, 20], today: 16)
    #expect(week.attended.isEmpty)
    #expect(week.done == 0)
    #expect(
      states(week) == ["2026-09-14": .missed, "2026-09-16": .today, "2026-09-18": .upcoming])
  }

  @Test("a troca de dia vira um dia do plano")
  func swapAddsSlot() {
    let schedule = PlanSchedule(
      plan: Self.plan, swaps: [DaySwap(date: Self.day(19), workoutTemplateId: "a")])
    let week = TrainingWeek(schedule: schedule, attended: [], today: Self.day(14))
    #expect(week.slots.map(\.date.iso) == ["2026-09-14", "2026-09-16", "2026-09-18", "2026-09-19"])
    #expect(week.slots.last?.workout.id == "a")
  }

  // O painel da fixture é de terça, 8 de setembro, com o treino tpl-terca e a
  // primeira série valendo do supino feita.
  private static let terca = CalendarDate(year: 2026, month: 9, day: 8)!
  private static let segunda = CalendarDate(year: 2026, month: 9, day: 7)!

  private static func unmarkAll(_ dashboard: inout Dashboard) {
    for index in dashboard.workout!.exercises.indices {
      for set in dashboard.workout!.exercises[index].sets.work.indices {
        dashboard.workout!.exercises[index].sets.work[set].completedAt = nil
      }
    }
    dashboard.workout!.completedWorkSetCount = 0
  }

  @Test("hoje sai do painel: desmarcar tira o dia mesmo com o servidor dizendo que teve")
  func todayFollowsTheDashboard() throws {
    var dashboard = try ContractTests.dashboard()
    dashboard.weekAttendance = [
      AttendanceDay(date: Self.segunda, workSets: 3, completed: true, workoutTemplateIds: ["x"]),
      AttendanceDay(date: Self.terca, workSets: 1, completed: false, workoutTemplateIds: ["tpl-terca"]),
    ]
    #expect(dashboard.attendedThisWeek(today: Self.terca) == [Self.segunda, Self.terca])
    Self.unmarkAll(&dashboard)
    #expect(dashboard.attendedThisWeek(today: Self.terca) == [Self.segunda])
  }

  @Test("outro treino feito hoje segura o dia mesmo sem série no treino do painel")
  func otherWorkoutTodayKeepsTheDay() throws {
    var dashboard = try ContractTests.dashboard()
    Self.unmarkAll(&dashboard)
    dashboard.weekAttendance = [
      AttendanceDay(date: Self.terca, workSets: 2, completed: false, workoutTemplateIds: ["x"])
    ]
    #expect(dashboard.attendedThisWeek(today: Self.terca) == [Self.terca])
  }

  @Test("servidor velho: cai na frequência carregada, depois em sessionDates")
  func oldServerFallsBack() throws {
    var dashboard = try ContractTests.dashboard()
    #expect(dashboard.weekAttendance == nil)
    #expect(dashboard.attendedThisWeek(today: Self.terca) == [Self.segunda, Self.terca])

    let loaded = [Self.segunda: AttendanceDay(date: Self.segunda, workSets: 0, completed: false)]
    #expect(dashboard.attendedThisWeek(today: Self.terca, fallback: loaded) == [Self.terca])

    Self.unmarkAll(&dashboard)
    #expect(dashboard.attendedThisWeek(today: Self.terca) == [Self.segunda])
  }

  @Test("painel de outra semana não empresta a presença dele")
  func dashboardOfAnotherWeek() throws {
    var dashboard = try ContractTests.dashboard()
    let nextMonday = CalendarDate(year: 2026, month: 9, day: 14)!
    dashboard.weekAttendance = [
      AttendanceDay(date: nextMonday, workSets: 3, completed: true, workoutTemplateIds: ["x"])
    ]
    #expect(dashboard.attendedThisWeek(today: nextMonday) == [nextMonday])
    let nextTuesday = CalendarDate(year: 2026, month: 9, day: 15)!
    #expect(dashboard.attendedThisWeek(today: nextTuesday).isEmpty)
  }

  @Test("a semana do painel usa a troca e a presença juntas")
  func trainingWeekFromDashboard() throws {
    let dashboard = try ContractTests.dashboard()
    let week = dashboard.trainingWeek(today: Self.terca)
    #expect(week.planned == 1)
    #expect(week.done == 1)
    #expect(week.slots.map(\.date) == [Self.terca])
  }

  @Test("presença conta de segunda até hoje, sem o domingo anterior")
  func presentDays() {
    let attendance = Dictionary(
      uniqueKeysWithValues: [(20, 4), (21, 3), (22, 0), (23, 2)].map {
        let date = Self.day($0.0)
        return (date, AttendanceDay(date: date, workSets: $0.1, completed: false))
      })
    #expect(WorkoutStreak.presentDays(in: attendance, today: Self.day(23)) == 2)
  }

  @Test("a contagem de presença troca a do servidor e o anel junto")
  func countingPresence() {
    let streak = WorkoutStreak(
      attendance: StreakFigure(count: 3, target: nil), complete: StreakFigure(count: 2, target: nil),
      weeklyCompleted: 2, weeklyPlanned: 3, days: [], isTodayDone: false, isAtRisk: false,
      weekProgress: 2.0 / 3.0)
    let counted = streak.counting(presentDays: 3)
    #expect(counted.weeklyCompleted == 3)
    #expect(counted.weekProgress == 1)
  }

  @Test("o calendário de treino começa na segunda")
  func startsOnMonday() {
    #expect(Calendar.trainingWeek.firstWeekday == 2)
  }
}
