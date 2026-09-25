import Foundation

/// A semana de treino do app, de segunda a domingo. A semana conta presença,
/// não o treino exato do dia: os `done` primeiros dias do plano ficam feitos,
/// então um treino na terça cobre a segunda que ficou para trás. Home,
/// sequência e calendário leem a mesma conta.
public struct TrainingWeek: Equatable, Sendable {
  public struct Slot: Equatable, Sendable, Identifiable {
    /// O dia que o plano marca, já com a troca aplicada.
    public let date: CalendarDate
    public let workout: WeekPlanItem
    public let state: State

    public var id: CalendarDate { date }
  }

  public enum State: Equatable, Sendable { case done, missed, today, upcoming }

  public let monday: CalendarDate
  /// Só os dias com treino no plano, em ordem.
  public let slots: [Slot]
  /// Os dias da semana com ao menos uma série valendo, de segunda até hoje.
  public let attended: [CalendarDate]

  public var planned: Int { slots.count }
  /// Treino além do planejado não passa do teto: "3 de 3".
  public var done: Int { min(planned, attended.count) }

  public init(
    schedule: PlanSchedule, attended: Set<CalendarDate>, today: CalendarDate,
    calendar: Calendar = .trainingWeek
  ) {
    let monday = today.trainingWeekStart(in: calendar)
    let days = (0..<7).map { monday.adding(days: $0, in: calendar) }
    let attended = days.filter { $0 <= today && attended.contains($0) }
    let planned = days.compactMap { date in schedule.workout(on: date).map { (date, $0) } }
    let done = min(planned.count, attended.count)
    self.monday = monday
    self.attended = attended
    slots = planned.enumerated().map { position, entry in
      let state: State =
        if position < done { .done }
        else if entry.0 < today { .missed }
        else if entry.0 == today { .today }
        else { .upcoming }
      return Slot(date: entry.0, workout: entry.1, state: state)
    }
  }

  public func slot(on date: CalendarDate) -> Slot? { slots.first { $0.date == date } }
}
