import Foundation
import Testing

@testable import HenriqueCore

/// 8 de setembro de 2026 é uma terça, então a janela de sete dias vai da quarta
/// anterior até ela, e o único dia da semana no plano das fixtures é o 2.
@Suite("A fita dos sete dias")
struct StreakTests {
  static let terca = CalendarDate(iso: "2026-09-08")!

  static func date(_ iso: String) throws -> CalendarDate {
    try #require(CalendarDate(iso: iso))
  }

  static func planItem(weekdays: [Int]) -> WeekPlanItem {
    WeekPlanItem(
      id: "tpl-\(weekdays.map(String.init).joined(separator: "-"))", weekdays: weekdays,
      name: "Empurrar A", focus: "peito", exerciseCount: 0, exercises: [], estimatedMinutes: 45)
  }

  /// Cada item de `plan` é um treino com os seus dias.
  static func dashboard(
    currentStreak: Int = 0, weeklyCompleted: Int = 0, weeklyPlanned: Int = 0,
    plan: [[Int]] = [], sessionDates: [CalendarDate]? = []
  ) -> Dashboard {
    Dashboard(
      date: Self.terca, workout: nil, consistencyPercent: 0, currentStreak: currentStreak,
      weeklyCompleted: weeklyCompleted, weeklyPlanned: weeklyPlanned,
      weekPlan: plan.map(planItem(weekdays:)), sessionDates: sessionDates,
      exerciseCatalog: [], strengthGoal: nil, progress: [], measurements: [], projection: nil,
      onboardingCompleted: true)
  }

  static func state(_ iso: String, in streak: WorkoutStreak) throws -> StreakDayState {
    try #require(
      streak.days.first { $0.date.iso == iso }?.state, "o dia \(iso) não está na fita")
  }

  @Test("saem sete dias em ordem, terminando em hoje")
  func sevenDaysEndingToday() {
    let streak = WorkoutStreak(dashboard: Self.dashboard(), today: Self.terca)
    #expect(
      streak.days.map(\.date.iso) == [
        "2026-09-02", "2026-09-03", "2026-09-04", "2026-09-05", "2026-09-06", "2026-09-07",
        "2026-09-08",
      ])
    #expect(streak.days.last?.date == Self.terca)
  }

  @Test("o dia com sessão fica feito mesmo fora do plano")
  func sessionOutsideThePlanIsDone() throws {
    let domingo = try Self.date("2026-09-06")
    let streak = WorkoutStreak(
      dashboard: Self.dashboard(plan: [[2]], sessionDates: [domingo]), today: Self.terca)
    #expect(try Self.state("2026-09-06", in: streak) == .done)
  }

  @Test("dia passado com treino no plano e sem sessão fica perdido, sem plano vira folga")
  func pastDaySplitsByThePlan() throws {
    let streak = WorkoutStreak(dashboard: Self.dashboard(plan: [[4]]), today: Self.terca)
    #expect(try Self.state("2026-09-03", in: streak) == .missed)
    #expect(try Self.state("2026-09-04", in: streak) == .rest)
  }

  @Test("um treino em dois dias marca os dois na fita")
  func oneWorkoutOnTwoDays() {
    let streak = WorkoutStreak(dashboard: Self.dashboard(plan: [[2, 4]]), today: Self.terca)
    #expect(
      streak.days.map(\.state) == [.rest, .missed, .rest, .rest, .rest, .rest, .planned])
    #expect(streak.isAtRisk)
  }

  @Test("hoje planejado e ainda não feito deixa a fita em risco")
  func plannedTodayIsAtRisk() throws {
    let streak = WorkoutStreak(dashboard: Self.dashboard(plan: [[2]]), today: Self.terca)
    #expect(try Self.state("2026-09-08", in: streak) == .planned)
    #expect(streak.isAtRisk)
    #expect(!streak.isTodayDone)
  }

  @Test("hoje já feito tira a fita do risco")
  func doneTodayLeavesNoRisk() throws {
    let streak = WorkoutStreak(
      dashboard: Self.dashboard(plan: [[2]], sessionDates: [Self.terca]), today: Self.terca)
    #expect(streak.isTodayDone)
    #expect(!streak.isAtRisk)
  }

  @Test("hoje sem treino no plano fica livre")
  func todayWithoutPlanIsOpen() throws {
    let streak = WorkoutStreak(dashboard: Self.dashboard(plan: [[4]]), today: Self.terca)
    #expect(try Self.state("2026-09-08", in: streak) == .open)
    #expect(!streak.isAtRisk)
  }

  @Test("semana sem nada planejado devolve progresso zero em vez de estourar")
  func emptyWeekHasZeroProgress() {
    let streak = WorkoutStreak(
      dashboard: Self.dashboard(weeklyCompleted: 2, weeklyPlanned: 0), today: Self.terca)
    #expect(streak.weekProgress == 0)
    #expect(streak.weeklyPlanned == 0)
  }

  @Test("o progresso da semana é o completo sobre o planejado, preso em um")
  func weekProgressIsClamped() {
    let metade = WorkoutStreak(
      dashboard: Self.dashboard(weeklyCompleted: 2, weeklyPlanned: 4), today: Self.terca)
    let demais = WorkoutStreak(
      dashboard: Self.dashboard(weeklyCompleted: 5, weeklyPlanned: 4), today: Self.terca)
    #expect(metade.weekProgress == 0.5)
    #expect(demais.weekProgress == 1)
  }

  @Test("sem sessionDates nenhum dia fica feito")
  func nilSessionDatesMarksNothingDone() {
    let streak = WorkoutStreak(
      dashboard: Self.dashboard(plan: [[2]], sessionDates: nil), today: Self.terca)
    #expect(!streak.days.contains { $0.state == .done })
    #expect(!streak.isTodayDone)
    #expect(streak.isAtRisk)
  }

  @Test("a fixture do painel monta a fita inteira")
  func buildsFromFixture() throws {
    let dashboard = try ContractTests.dashboard()
    let streak = WorkoutStreak(dashboard: dashboard, today: dashboard.date)
    #expect(streak.attendance == StreakFigure(count: 6, target: 10))
    #expect(streak.complete == StreakFigure(count: 4, target: 7))
    #expect(streak.weeklyCompleted == 2)
    #expect(streak.weekProgress == 0.5)
    #expect(
      streak.days.map(\.state) == [.rest, .rest, .done, .rest, .done, .done, .planned])
    #expect(streak.isAtRisk)
    #expect(!streak.isTodayDone)
  }

  @Test("a captura do servidor real não tem o campo e a fita ainda sai")
  func capturedServerHasNoSessionDates() throws {
    let dashboard = try CapturedResponseTests.dashboard()
    #expect(dashboard.sessionDates == nil)
    let streak = WorkoutStreak(dashboard: dashboard)
    #expect(streak.days.count == 7)
    #expect(streak.attendance == StreakFigure(count: 0, target: nil))
    #expect(streak.complete == StreakFigure(count: 0, target: nil))
  }
}

@Suite("A insígnia dos meses de presença")
struct InsigniaTests {
  static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    return calendar
  }()
  static let today = CalendarDate(iso: "2026-09-25")!

  static func date(_ iso: String) -> CalendarDate { CalendarDate(iso: iso)! }

  /// Um dia de presença a cada `step` dias, de `from` até `to`.
  static func attendance(
    from: String, to: String, every step: Int, workSets: Int = 3
  ) -> [CalendarDate: AttendanceDay] {
    var days: [CalendarDate: AttendanceDay] = [:]
    var cursor = date(from)
    while cursor <= date(to) {
      days[cursor] = AttendanceDay(date: cursor, workSets: workSets, completed: true)
      cursor = cursor.adding(days: step, in: calendar)
    }
    return days
  }

  static func tenure(_ attendance: [CalendarDate: AttendanceDay]) -> StreakTenure? {
    StreakTenure(attendance: attendance, today: today, calendar: calendar)
  }

  @Test("os meses viram nível, e do décimo em diante é radiante")
  func tierFromMonths() {
    #expect(StreakTier(months: 0) == nil)
    #expect(StreakTier(months: -2) == nil)
    #expect(StreakTier(months: 1) == .ferro)
    #expect(StreakTier(months: 9) == .surreal)
    #expect(StreakTier(months: 10) == .radiante)
    #expect(StreakTier(months: 11) == .radiante)
    #expect(StreakTier(months: 12) == .radiante)
    #expect(StreakTier(months: 15) == .radiante)
    #expect(
      StreakTier.allCases.map(\.name) == [
        "ferro", "bronze", "prata", "ouro", "platina", "diamante", "épico", "imortal",
        "surreal", "radiante",
      ])
  }

  @Test("sem presença não há sequência")
  func emptyAttendance() {
    #expect(Self.tenure([:]) == nil)
  }

  @Test("presença a cada 3 dias desde 20 de junho dá 3 meses, prata")
  func steadyAttendance() {
    let tenure = Self.tenure(Self.attendance(from: "2026-06-20", to: "2026-09-24", every: 3))
    #expect(tenure?.start == Self.date("2026-06-20"))
    #expect(tenure?.months == 3)
    #expect(tenure?.tier == .prata)
  }

  @Test("um buraco de 6 dias corta o começo para depois dele")
  func gapCutsTheStart() {
    var days = Self.attendance(from: "2026-06-20", to: "2026-07-20", every: 3)
    days.merge(Self.attendance(from: "2026-07-26", to: "2026-09-24", every: 2)) { $1 }
    let tenure = Self.tenure(days)
    #expect(tenure?.start == Self.date("2026-07-26"))
    #expect(tenure?.months == 1)
    #expect(tenure?.tier == .ferro)
  }

  @Test("o último treino a 6 dias de hoje já quebrou a sequência")
  func staleNewestDay() {
    #expect(Self.tenure(Self.attendance(from: "2026-06-20", to: "2026-09-19", every: 1)) == nil)
    #expect(
      Self.tenure(Self.attendance(from: "2026-09-20", to: "2026-09-20", every: 1))?.start
        == Self.date("2026-09-20"))
  }

  @Test("dia sem série valendo não conta")
  func zeroWorkSetsAreIgnored() {
    var days = Self.attendance(from: "2026-06-20", to: "2026-09-24", every: 3)
    for day in Self.attendance(from: "2026-08-01", to: "2026-08-10", every: 1, workSets: 0).values {
      days[day.date] = day
    }
    let tenure = Self.tenure(days)
    #expect(tenure?.start == Self.date("2026-08-13"))
    #expect(tenure?.months == 1)
    #expect(Self.tenure(Self.attendance(from: "2026-09-20", to: "2026-09-24", every: 1, workSets: 0)) == nil)
  }

  @Test("sequência de menos de um mês não tem nível nem comemoração")
  func noTierBeforeAMonth() {
    let tenure = StreakTenure(start: Self.date("2026-09-01"), months: 0)
    #expect(tenure.tier == nil)
    #expect(tenure.celebration(after: nil) == nil)
  }

  @Test("comemora sem registro, quando o nível sobe e quando a sequência recomeça")
  func whatToCelebrate() {
    let start = Self.date("2026-06-20")
    let tenure = StreakTenure(start: start, months: 3)
    let prata = CelebratedTier(start: start, tier: .prata)
    #expect(tenure.celebration(after: nil) == prata)
    #expect(tenure.celebration(after: prata) == nil)
    #expect(
      tenure.celebration(after: CelebratedTier(start: start, tier: .bronze)) == prata)
    #expect(
      tenure.celebration(after: CelebratedTier(start: Self.date("2026-01-10"), tier: .surreal))
        == prata)
  }
}
