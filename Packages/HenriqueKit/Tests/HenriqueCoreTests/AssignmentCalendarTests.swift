import Foundation
import Testing

@testable import HenriqueCore

/// O calendário de entregas agrupa por dia no fuso de Fortaleza e decide o
/// que criar, atualizar e apagar no Apple Calendar sem tocar no EventKit.
@Suite("Calendário de entregas")
struct AssignmentCalendarTests {
  static var fortaleza: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Fortaleza") ?? .gmt
    calendar.locale = Locale(identifier: "pt_BR")
    return calendar
  }

  static func assignment(
    id: String, due: String, status: AssignmentStatus = .open
  ) -> StudyAssignment {
    let date = ISO8601DateFormatter().date(from: due)!
    return StudyAssignment(
      id: id, title: id, dueAt: date, status: status, source: "ava")
  }

  @Test("o vencimento cai no dia de Fortaleza")
  func groupsByFortalezaDay() {
    // 02:30 UTC ainda é dia 9 em Fortaleza.
    let entrega = Self.assignment(id: "a", due: "2026-09-10T02:30:00Z")
    let calendar = AssignmentCalendar(
      month: CalendarDate(year: 2026, month: 9, day: 1)!, assignments: [entrega],
      now: ISO8601DateFormatter().date(from: "2026-09-01T12:00:00Z")!,
      calendar: Self.fortaleza)
    #expect(calendar.marks[CalendarDate(year: 2026, month: 9, day: 9)!]?.total == 1)
    #expect(calendar.marks[CalendarDate(year: 2026, month: 9, day: 10)!] == nil)
  }

  @Test("a marca conta pendentes, atrasadas e feitas")
  func countsMarks() {
    let now = ISO8601DateFormatter().date(from: "2026-09-10T12:00:00Z")!
    let items = [
      Self.assignment(id: "atrasada", due: "2026-09-09T15:00:00Z"),
      Self.assignment(id: "hoje", due: "2026-09-10T18:00:00Z"),
      Self.assignment(id: "feita", due: "2026-09-10T18:00:00Z", status: .done),
    ]
    let calendar = AssignmentCalendar(
      month: CalendarDate(year: 2026, month: 9, day: 1)!, assignments: items, now: now,
      calendar: Self.fortaleza)
    let mark = try! #require(
      calendar.marks[CalendarDate(year: 2026, month: 9, day: 10)!])
    #expect(mark.total == 2)
    #expect(mark.pending == 1)
    #expect(mark.done == 1)
    #expect(!mark.hasOverdue)
    #expect(!mark.isComplete)
    let late = try! #require(
      calendar.marks[CalendarDate(year: 2026, month: 9, day: 9)!])
    #expect(late.hasOverdue)
  }

  /// O relógio da tela era o meio-dia do dia. Por ele, uma entrega das 10:00
  /// aparecia atrasada às 7:00, e uma das 18:00 seguia em dia às 23:00.
  @Test("atrasada conta do instante do prazo, não do dia")
  func overdueByInstant() {
    let date = ISO8601DateFormatter()
    // 10:00 e 18:00 em Fortaleza, UTC-3.
    let morning = Self.assignment(id: "manha", due: "2026-09-10T13:00:00Z")
    let evening = Self.assignment(id: "noite", due: "2026-09-10T21:00:00Z")
    let early = date.date(from: "2026-09-10T10:00:00Z")!
    let late = date.date(from: "2026-09-11T02:00:00Z")!

    #expect(!morning.isOverdue(at: early))
    #expect(morning.urgency(at: early) == .near)
    #expect(evening.isOverdue(at: late))
    #expect(evening.urgency(at: late) == .overdue)

    var done = evening
    done.status = .done
    #expect(!done.isOverdue(at: late))
    #expect(done.urgency(at: late) == .done)

    let nextWeek = Self.assignment(id: "semana", due: "2026-09-17T13:00:00Z")
    #expect(nextWeek.urgency(at: early) == .later)
  }

  @Test("a grade cobre o mês em semanas de sete")
  func buildsMonthGrid() {
    let calendar = AssignmentCalendar(
      month: CalendarDate(year: 2026, month: 9, day: 15)!, assignments: [],
      now: Date(), calendar: Self.fortaleza)
    let days = calendar.weeks.flatMap(\.cells).compactMap(\.date)
    #expect(days.count == 30)
    #expect(days.first == CalendarDate(year: 2026, month: 9, day: 1))
    #expect(days.last == CalendarDate(year: 2026, month: 9, day: 30))
    #expect(calendar.weeks.allSatisfy { $0.cells.count == 7 })
  }

  @Test("o plano cria, atualiza e apaga sem tocar no EventKit")
  func plansExport() {
    let open = Self.assignment(id: "aberta", due: "2026-09-12T15:00:00Z")
    let synced = Self.assignment(id: "sincronizada", due: "2026-09-13T15:00:00Z")
    let done = Self.assignment(id: "feita", due: "2026-09-14T15:00:00Z", status: .done)
    let plan = planCalendarExport(
      assignments: [open, synced, done],
      mapped: ["sincronizada": "ev-1", "feita": "ev-2", "apagada": "ev-3"])
    #expect(plan.create.map(\.id) == ["aberta"])
    #expect(plan.update.map(\.id) == ["sincronizada"])
    // A feita saiu do calendário do sistema e a apagada não existe mais.
    #expect(Set(plan.removeEventIDs) == ["ev-2", "ev-3"])
  }
}
