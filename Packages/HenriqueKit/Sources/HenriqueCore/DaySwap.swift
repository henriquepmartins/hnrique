import Foundation

/// Uma data que treina outro treino no lugar do que o plano marca. Só vale para
/// aquele dia; o plano continua igual.
public struct DaySwap: Codable, Hashable, Sendable {
  public var date: CalendarDate
  public var workoutTemplateId: String

  public init(date: CalendarDate, workoutTemplateId: String) {
    self.date = date
    self.workoutTemplateId = workoutTemplateId
  }
}

/// Um treino que era previsto num dia já passado da semana e não saiu.
public struct MissedWorkout: Hashable, Sendable, Identifiable {
  public let workout: WeekPlanItem
  /// O dia perdido mais recente, que é o que o rótulo mostra ("faltou terça").
  public let lastMissed: CalendarDate

  public var id: String { workout.id }
}

/// O plano da semana com as trocas por data aplicadas.
public struct PlanSchedule: Sendable {
  public let plan: [WeekPlanItem]
  private let swaps: [CalendarDate: String]
  private let calendar: Calendar

  public init(plan: [WeekPlanItem], swaps: [DaySwap], calendar: Calendar = .autoupdatingCurrent) {
    self.plan = plan
    self.swaps = Dictionary(swaps.map { ($0.date, $0.workoutTemplateId) }, uniquingKeysWith: { $1 })
    self.calendar = calendar
  }

  /// O que o plano marca para o dia da semana, sem olhar a troca.
  public func weekdayWorkout(on date: CalendarDate) -> WeekPlanItem? {
    let weekday = date.weekday(in: calendar)
    return plan.first { $0.weekdays.contains(weekday) }
  }

  public func isSwapped(_ date: CalendarDate) -> Bool { swaps[date] != nil }

  /// A troca da data, senão o dia da semana. Uma troca para um treino que saiu
  /// do plano cai no dia da semana em vez de virar descanso.
  public func workout(on date: CalendarDate) -> WeekPlanItem? {
    if let id = swaps[date], let swapped = plan.first(where: { $0.id == id }) { return swapped }
    return weekdayWorkout(on: date)
  }

  /// Os treinos da semana (segunda a ontem) que foram previstos mais vezes do que
  /// saíram, do dia perdido mais recente para o mais antigo. O treino de hoje fica
  /// de fora: ele já é o que está marcado para agora.
  public func missedWorkouts(
    today: CalendarDate, sessions: [WeeklyWorkoutSessions]
  ) -> [MissedWorkout] {
    let monday = today.adding(days: -((today.weekday(in: calendar) + 6) % 7), in: calendar)
    var planned: [String: (workout: WeekPlanItem, count: Int, last: CalendarDate)] = [:]
    var date = monday
    while date < today {
      if let workout = workout(on: date) {
        planned[workout.id, default: (workout, 0, date)].count += 1
        planned[workout.id]?.last = date
      }
      date = date.adding(days: 1, in: calendar)
    }
    let done = Dictionary(
      sessions.map { ($0.workoutTemplateId, $0.count) }, uniquingKeysWith: +)
    let todays = workout(on: today)?.id
    return planned.values
      .filter { $0.workout.id != todays && $0.count > done[$0.workout.id, default: 0] }
      .sorted { $0.last > $1.last }
      .map { MissedWorkout(workout: $0.workout, lastMissed: $0.last) }
  }
}

extension Dashboard {
  public var schedule: PlanSchedule { PlanSchedule(plan: weekPlan, swaps: daySwaps ?? []) }
}

extension Calendar {
  /// A semana do treino começa na segunda, como a do servidor, que conta
  /// `weeklyCompleted` e `daySwaps` a partir dela. Um calendário que começa no
  /// domingo punha o treino de domingo numa semana que o resto do app não vê.
  public static var trainingWeek: Calendar {
    var calendar = Calendar.autoupdatingCurrent
    calendar.firstWeekday = 2
    return calendar
  }
}

extension CalendarDate {
  /// A segunda da semana de treino deste dia. Domingo pertence à semana que
  /// começou seis dias antes.
  public func trainingWeekStart(in calendar: Calendar = .trainingWeek) -> CalendarDate {
    adding(days: -((weekday(in: calendar) + 6) % 7), in: calendar)
  }
}
