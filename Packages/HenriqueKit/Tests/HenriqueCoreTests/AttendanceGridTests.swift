import Foundation
import Testing

@testable import HenriqueCore

@Suite("A grade de frequência")
struct AttendanceGridTests {
  // Semana começando no domingo, para os buracos não dependerem do aparelho.
  private var sunday: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = 1
    calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    return calendar
  }

  private func day(_ iso: String, sets: Int) -> AttendanceDay {
    AttendanceDay(date: CalendarDate(iso: iso)!, workSets: sets, completed: sets > 0)
  }

  @Test("mês de 30 dias começando na quarta dá cinco semanas e cinco buracos")
  func aprilShape() {
    // 1 de abril de 2026 é uma quarta.
    let grid = AttendanceGrid(period: .month(year: 2026, month: 4), attendance: [:], calendar: sunday)
    #expect(grid.weeks.count == 5)
    #expect(grid.weeks.allSatisfy { $0.cells.count == 7 })
    let holes = grid.weeks.flatMap(\.cells).filter { $0.date == nil }
    #expect(holes.count == 5)
    #expect(grid.weeks[0].cells.map { $0.date?.day } == [nil, nil, nil, 1, 2, 3, 4])
    #expect(grid.weeks[4].cells.map { $0.date?.day } == [26, 27, 28, 29, 30, nil, nil])
    #expect(grid.weeks[0].start.iso == "2026-03-29")
  }

  @Test("o total soma só os dias com série dentro do período")
  func totalStaysInside() {
    let attendance = [
      day("2026-03-31", sets: 9), day("2026-04-01", sets: 12), day("2026-04-15", sets: 0),
      day("2026-04-30", sets: 3), day("2026-05-01", sets: 8),
    ]
    let grid = AttendanceGrid(
      period: .month(year: 2026, month: 4), attendance: Dictionary(uniqueKeysWithValues: attendance.map { ($0.date, $0) }),
      calendar: sunday)
    #expect(grid.total == 2)
    #expect(grid.weeks[0].cells[3].workSets == 12)
    #expect(grid.weeks[0].cells[2].workSets == 0)
  }

  @Test("o ano cobre todas as semanas e cada mês começa numa delas")
  func yearShape() {
    let grid = AttendanceGrid(period: .year(2026), attendance: [:], calendar: sunday)
    #expect(grid.weeks.count == 53)
    #expect(grid.weeks.first?.cells.first?.date == nil)
    #expect(grid.weeks.last?.cells.last?.date == nil)
    let monthStarts = grid.weeks.compactMap { $0.cells.first { $0.date?.day == 1 }?.date?.month }
    #expect(monthStarts == Array(1...12))
  }

  @Test(
    "as faixas de cor caem nos limites certos",
    arguments: [(0, 0), (1, 1), (5, 1), (6, 2), (10, 2), (11, 3), (15, 3), (16, 4), (40, 4)])
  func levels(_ sets: Int, _ level: Int) {
    #expect(AttendanceGrid.level(workSets: sets) == level)
  }

  @Test("o período anda pelo calendário e sabe o próprio intervalo")
  func periodMoves() {
    #expect(AttendancePeriod.month(year: 2026, month: 12).next == .month(year: 2027, month: 1))
    #expect(AttendancePeriod.month(year: 2026, month: 1).previous == .month(year: 2025, month: 12))
    #expect(AttendancePeriod.year(2026).next == .year(2027))
    let february = AttendancePeriod.month(year: 2028, month: 2).range(in: sunday)
    #expect(february.upperBound.iso == "2028-02-29")
    let year = AttendancePeriod.year(2026).range(in: sunday)
    #expect(year.lowerBound.iso == "2026-01-01")
    #expect(year.upperBound.iso == "2026-12-31")
  }

  @Test("o título sai por extenso e minúsculo em pt-BR")
  func titles() {
    let locale = Locale(identifier: "pt_BR")
    #expect(AttendancePeriod.month(year: 2026, month: 9).title(locale: locale, calendar: sunday) == "setembro de 2026")
    #expect(AttendancePeriod.month(year: 2026, month: 9).name(locale: locale, calendar: sunday) == "setembro")
    #expect(AttendancePeriod.year(2026).title(locale: locale, calendar: sunday) == "2026")
  }

  @Test("sem calendário, a grade começa na segunda")
  func defaultsToMonday() {
    // 1 de abril de 2026 é uma quarta.
    let grid = AttendanceGrid(period: .month(year: 2026, month: 4), attendance: [:])
    #expect(grid.weeks[0].start.iso == "2026-03-30")
    #expect(grid.weeks[0].cells.map { $0.date?.day } == [nil, nil, 1, 2, 3, 4, 5])
  }
}
