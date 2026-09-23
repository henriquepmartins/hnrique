import Foundation

/// O calendário da tela "plano" já resolvido: uma semana por linha, sete casas
/// por semana na ordem da semana do calendário, e em cada dia o que foi feito
/// ou o que o plano pede. A view só desenha.
public struct PlanCalendar: Hashable, Sendable {
  /// O que aconteceu, ou vai acontecer, no dia.
  public enum Mark: Hashable, Sendable {
    case none
    /// Ids dos treinos feitos, ordem de primeira série.
    case done([String])
    /// Id do treino que o plano pede nesse dia, ainda por fazer.
    case planned(String)
    /// Planejado, já passou, não foi feito. Só dentro da semana corrente.
    case missed(String)
  }

  public struct Cell: Hashable, Sendable, Identifiable {
    /// O dia daquela casa, mesmo quando cai fora do mês. É a identidade
    /// estável da casa na semana.
    public let slot: CalendarDate
    /// Nulo quando a casa é um buraco fora do mês.
    public let date: CalendarDate?
    public let mark: Mark
    public let isToday: Bool

    public var id: CalendarDate { slot }
  }

  public struct Week: Hashable, Sendable, Identifiable {
    public let start: CalendarDate
    public let cells: [Cell]

    public var id: CalendarDate { start }
  }

  public let weeks: [Week]

  public init(
    period: AttendancePeriod, attendance: [CalendarDate: AttendanceDay],
    weekPlan: [WeekPlanItem], swaps: [DaySwap] = [], today: CalendarDate = .today,
    calendar: Calendar = .autoupdatingCurrent
  ) {
    let range = period.range(in: calendar)
    let schedule = PlanSchedule(plan: weekPlan, swaps: swaps, calendar: calendar)
    let startOfWeek = today.adding(
      days: -((today.weekday(in: calendar) + 1 - calendar.firstWeekday + 7) % 7), in: calendar)

    func mark(for date: CalendarDate) -> Mark {
      if let ids = attendance[date]?.workoutTemplateIds, !ids.isEmpty { return .done(ids) }
      if attendance[date]?.workSets ?? 0 > 0 {
        // Servidor velho não manda os ids. O palpite é o treino que o plano
        // pede nesse weekday, para o feito sair na cor sólida do folder em
        // vez de cinza. Sem treino no dia, segue sem treino conhecido.
        if let item = schedule.workout(on: date) { return .done([item.id]) }
        return .done([])
      }
      guard let item = schedule.workout(on: date) else { return .none }
      if date >= today { return .planned(item.id) }
      if date >= startOfWeek { return .missed(item.id) }
      return .none
    }

    let offset = (range.lowerBound.weekday(in: calendar) + 1 - calendar.firstWeekday + 7) % 7
    var cursor = range.lowerBound.adding(days: -offset, in: calendar)
    var weeks: [Week] = []
    while cursor <= range.upperBound {
      let cells = (0..<7).map { column -> Cell in
        let slot = cursor.adding(days: column, in: calendar)
        guard range.contains(slot) else { return Cell(slot: slot, date: nil, mark: .none, isToday: false) }
        return Cell(slot: slot, date: slot, mark: mark(for: slot), isToday: slot == today)
      }
      weeks.append(Week(start: cursor, cells: cells))
      cursor = cursor.adding(days: 7, in: calendar)
    }
    self.weeks = weeks
  }
}
