import Foundation

/// A marca de um dia no calendário de entregas: quantas vencem nele e em que
/// pé estão. A view só desenha.
public struct AssignmentDayMark: Hashable, Sendable {
  public let date: CalendarDate
  public let total: Int
  public let pending: Int
  public let overdue: Int
  public let done: Int

  public init(date: CalendarDate, total: Int, pending: Int, overdue: Int, done: Int) {
    self.date = date
    self.total = total
    self.pending = pending
    self.overdue = overdue
    self.done = done
  }

  public var hasOverdue: Bool { overdue > 0 }
  public var isComplete: Bool { total > 0 && pending == 0 }
}

/// O quanto o prazo aperta, para o cartão escolher cor e ícone. "Perto" cobre
/// hoje e amanhã: até 48 h do instante atual.
public enum AssignmentUrgency: Hashable, Sendable {
  case done, overdue, near, later
}

extension StudyAssignment {
  /// Vence no instante do prazo, e não no fim do dia: uma entrega das 10:00
  /// ainda está em dia às 7:00 e já está atrasada às 10:01.
  public func isOverdue(at now: Date) -> Bool {
    status != .done && dueAt < now
  }

  public func urgency(at now: Date) -> AssignmentUrgency {
    if status == .done { return .done }
    if dueAt < now { return .overdue }
    return dueAt.timeIntervalSince(now) <= 48 * 3600 ? .near : .later
  }
}

/// A grade mensal das entregas, resolvida a partir da lista inteira. O mês é o
/// que a view navega. O prazo cai no dia do fuso que o chamador passa, porque
/// o vencimento é o que o professor marcou em Fortaleza, e não no fuso do
/// aparelho.
public struct AssignmentCalendar: Hashable, Sendable {
  public struct Cell: Hashable, Sendable, Identifiable {
    /// O dia daquela casa, mesmo fora do mês. Identidade estável da casa.
    public let slot: CalendarDate
    /// Nulo quando a casa é um buraco fora do mês.
    public let date: CalendarDate?
    public let mark: AssignmentDayMark?

    public var id: CalendarDate { slot }
  }

  public struct Week: Hashable, Sendable, Identifiable {
    public let start: CalendarDate
    public let cells: [Cell]

    public var id: CalendarDate { start }
  }

  public let weeks: [Week]
  public let marks: [CalendarDate: AssignmentDayMark]

  public init(
    month: CalendarDate, assignments: [StudyAssignment], now: Date,
    calendar: Calendar = .autoupdatingCurrent
  ) {
    var marks: [CalendarDate: AssignmentDayMark] = [:]
    let grouped = Dictionary(grouping: assignments) { CalendarDate($0.dueAt, in: calendar) }
    for (date, items) in grouped {
      let done = items.count { $0.status == .done }
      let overdue = items.count { $0.isOverdue(at: now) }
      marks[date] = AssignmentDayMark(
        date: date, total: items.count, pending: items.count - done, overdue: overdue, done: done)
    }
    self.marks = marks

    let first = CalendarDate(year: month.year, month: month.month, day: 1)!
    let days = calendar.range(of: .day, in: .month, for: first.date(in: calendar))?.count ?? 30
    let last = CalendarDate(year: month.year, month: month.month, day: days)!
    let offset = (first.weekday(in: calendar) + 1 - calendar.firstWeekday + 7) % 7
    var cursor = first.adding(days: -offset, in: calendar)
    var weeks: [Week] = []
    while cursor <= last {
      let cells = (0..<7).map { column -> Cell in
        let slot = cursor.adding(days: column, in: calendar)
        guard slot.month == month.month && slot.year == month.year else {
          return Cell(slot: slot, date: nil, mark: nil)
        }
        return Cell(slot: slot, date: slot, mark: marks[slot])
      }
      weeks.append(Week(start: cursor, cells: cells))
      cursor = cursor.adding(days: 7, in: calendar)
    }
    self.weeks = weeks
  }
}

/// O que levar ao Apple Calendar, decidido sem tocar no EventKit para o teste
/// cobrir a regra. Só entrega pendente vira evento. Feita ou apagada tem o
/// evento removido. O mapeamento entrega -> evento mora no aparelho.
public struct CalendarExportPlan: Hashable, Sendable {
  /// Pendentes sem evento: criar.
  public let create: [StudyAssignment]
  /// Pendentes com evento: atualizar prazo e título no lugar.
  public let update: [StudyAssignment]
  /// IDs de evento sem entrega pendente: apagar.
  public let removeEventIDs: [String]

  public init(create: [StudyAssignment], update: [StudyAssignment], removeEventIDs: [String]) {
    self.create = create
    self.update = update
    self.removeEventIDs = removeEventIDs
  }
}

/// Monta o plano a partir da lista atual e do mapeamento guardado. Uma entrega
/// feita some do calendário do sistema, e não vira evento riscado, porque o
/// riscado já mora na aba de feitas.
public func planCalendarExport(
  assignments: [StudyAssignment], mapped: [String: String]
) -> CalendarExportPlan {
  var create: [StudyAssignment] = []
  var update: [StudyAssignment] = []
  var liveEventIDs = Set<String>()
  for assignment in assignments where assignment.status != .done {
    if let eventID = mapped[assignment.id] {
      liveEventIDs.insert(eventID)
      update.append(assignment)
    } else {
      create.append(assignment)
    }
  }
  let remove = mapped.values.filter { !liveEventIDs.contains($0) }
  return CalendarExportPlan(create: create, update: update, removeEventIDs: Array(remove))
}
