import Foundation
import Testing

@testable import HenriqueCore

@Suite("O calendário do plano")
struct PlanCalendarTests {
  // Semana começando no domingo, para os buracos não dependerem do aparelho.
  private var sunday: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = 1
    calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    return calendar
  }

  // 16 de setembro de 2026 é uma quarta; a semana corrente começa no dia 13.
  private let today = CalendarDate(iso: "2026-09-16")!

  // Perna às segundas e quintas (1, 4), peito às quartas (3).
  private let plan = [
    PlanCalendarTests.item(id: "perna", weekdays: [1, 4]),
    PlanCalendarTests.item(id: "peito", weekdays: [3]),
  ]

  private static func item(id: String, weekdays: [Int]) -> WeekPlanItem {
    WeekPlanItem(
      id: id, weekdays: weekdays, name: id, focus: "", exerciseCount: 0, exercises: [],
      estimatedMinutes: 0, color: nil)
  }

  private func day(_ iso: String, sets: Int, ids: [String] = []) -> (CalendarDate, AttendanceDay) {
    let date = CalendarDate(iso: iso)!
    return (date, AttendanceDay(date: date, workSets: sets, completed: sets > 0, workoutTemplateIds: ids))
  }

  private func calendar(
    month: Int = 9, attendance: [(CalendarDate, AttendanceDay)] = []
  ) -> PlanCalendar {
    PlanCalendar(
      period: .month(year: 2026, month: month),
      attendance: Dictionary(uniqueKeysWithValues: attendance),
      weekPlan: plan, today: today, calendar: sunday)
  }

  private func mark(_ grid: PlanCalendar, _ iso: String) -> PlanCalendar.Mark? {
    grid.weeks.flatMap(\.cells).first { $0.date == CalendarDate(iso: iso) }?.mark
  }

  @Test("dia com ids vira feito com os ids na ordem")
  func doneWithIds() {
    let grid = calendar(attendance: [day("2026-09-08", sets: 12, ids: ["peito", "perna"])])
    #expect(mark(grid, "2026-09-08") == .done(["peito", "perna"]))
  }

  @Test("dia com séries e sem ids, sem treino no dia, vira feito sem treino conhecido")
  func doneWithoutIds() {
    // 8 de setembro é terça, sem treino no plano.
    let grid = calendar(attendance: [day("2026-09-08", sets: 5)])
    #expect(mark(grid, "2026-09-08") == .done([]))
  }

  @Test("dia com séries e sem ids usa o treino que o plano pede no weekday")
  func doneWithoutIdsFallsBackToWeekday() {
    // 7 de setembro é segunda (perna), 9 é quarta (peito).
    let grid = calendar(attendance: [day("2026-09-07", sets: 5), day("2026-09-09", sets: 5)])
    #expect(mark(grid, "2026-09-07") == .done(["perna"]))
    #expect(mark(grid, "2026-09-09") == .done(["peito"]))
  }

  @Test("dia futuro com weekday no plano vira planejado")
  func plannedAhead() {
    let grid = calendar()
    // 21 de setembro é segunda, 23 é quarta.
    #expect(mark(grid, "2026-09-21") == .planned("perna"))
    #expect(mark(grid, "2026-09-23") == .planned("peito"))
    #expect(mark(grid, "2026-09-16") == .planned("peito"))
    #expect(mark(grid, "2026-09-22") == PlanCalendar.Mark.none)
  }

  @Test("dia planejado da semana corrente que já passou vira furado")
  func missedThisWeek() {
    let grid = calendar()
    // 14 de setembro é segunda, dentro da semana que começa no domingo 13.
    #expect(mark(grid, "2026-09-14") == .missed("perna"))
    #expect(mark(grid, "2026-09-15") == PlanCalendar.Mark.none)
  }

  @Test("o mesmo weekday num mês anterior não vira nada")
  func pastMonthStaysBlank() {
    let grid = calendar(month: 8)
    // 3 de agosto é segunda.
    #expect(mark(grid, "2026-08-03") == PlanCalendar.Mark.none)
    #expect(mark(grid, "2026-08-31") == PlanCalendar.Mark.none)
  }

  @Test("feito ganha de planejado no mesmo dia")
  func doneBeatsPlanned() {
    let grid = calendar(attendance: [day("2026-09-16", sets: 8, ids: ["perna"])])
    #expect(mark(grid, "2026-09-16") == .done(["perna"]))
  }

  @Test("as casas fora do mês não têm data e cada semana tem sete casas")
  func holesAndShape() {
    let grid = calendar()
    // 1 de setembro de 2026 é uma terça, 30 é uma quarta.
    #expect(grid.weeks.count == 5)
    #expect(grid.weeks.allSatisfy { $0.cells.count == 7 })
    #expect(grid.weeks[0].cells.map { $0.date?.day } == [nil, nil, 1, 2, 3, 4, 5])
    #expect(grid.weeks[4].cells.map { $0.date?.day } == [27, 28, 29, 30, nil, nil, nil])
    #expect(grid.weeks[0].cells[0].mark == PlanCalendar.Mark.none)
    #expect(grid.weeks[0].cells[0].isToday == false)
  }

  @Test("só hoje leva a marca de hoje")
  func todayFlag() {
    let grid = calendar()
    let todays = grid.weeks.flatMap(\.cells).filter(\.isToday).compactMap(\.date)
    #expect(todays.map(\.iso) == ["2026-09-16"])
  }

  @Test("dia do plano coberto por treino em outro dia da semana não fica furado")
  func coveredDayIsNotMissed() {
    // Terça 15 cobre a segunda 14; hoje é quarta 16.
    let grid = calendar(attendance: [day("2026-09-15", sets: 4)])
    #expect(mark(grid, "2026-09-14") == PlanCalendar.Mark.none)
    #expect(mark(grid, "2026-09-15") == .done([]))
    #expect(mark(grid, "2026-09-16") == .planned("peito"))
  }

  @Test("sem calendário, a semana começa na segunda")
  func defaultsToMonday() {
    let grid = PlanCalendar(
      period: .month(year: 2026, month: 9), attendance: [:], weekPlan: plan, today: today)
    #expect(grid.weeks[0].cells.map { $0.date?.day } == [nil, 1, 2, 3, 4, 5, 6])
    #expect(grid.weeks[0].start.iso == "2026-08-31")
  }

  @Test("a semana da store cobre o dia mesmo sem a presença no mês visível")
  func weekFromStoreCovers() {
    let schedule = PlanSchedule(plan: plan, swaps: [], calendar: sunday)
    let week = TrainingWeek(
      schedule: schedule, attended: [CalendarDate(iso: "2026-09-15")!], today: today, calendar: sunday)
    let grid = PlanCalendar(
      period: .month(year: 2026, month: 9), attendance: [:], weekPlan: plan, today: today,
      calendar: sunday, week: week)
    #expect(mark(grid, "2026-09-14") == PlanCalendar.Mark.none)
    #expect(calendar().weeks.flatMap(\.cells).first { $0.date?.iso == "2026-09-14" }?.mark == .missed("perna"))
  }
}
