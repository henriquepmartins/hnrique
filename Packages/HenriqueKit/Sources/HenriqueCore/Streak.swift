import Foundation

/// O estado de um dia da fita. O passado e o futuro têm casos separados porque a
/// mesma ausência de treino significa coisas diferentes: um dia sem plano que já
/// passou é folga, um que ainda vem é dia livre.
public enum StreakDayState: Sendable, Hashable {
  case done
  case missed
  case rest
  case planned
  case open
}

public struct StreakDay: Sendable, Hashable, Identifiable {
  public var date: CalendarDate
  public var state: StreakDayState

  public var id: CalendarDate { date }
}

/// Um dos dois números da sequência com a meta dele, se houver.
public struct StreakFigure: Sendable, Hashable {
  public var count: Int
  public var target: Int?

  public init(count: Int, target: Int?) {
    self.count = count
    self.target = target
  }

  public init(dashboard: Dashboard, kind: StreakKind) {
    self.init(count: dashboard.streak(kind), target: dashboard.goal(kind)?.target)
  }
}

public struct WorkoutStreak: Sendable, Hashable {
  public var attendance: StreakFigure
  public var complete: StreakFigure
  public var weeklyCompleted: Int
  public var weeklyPlanned: Int
  public var days: [StreakDay]
  public var isTodayDone: Bool
}

extension WorkoutStreak {
  /// A fita vai de segunda a domingo da semana de hoje, com a mesma conta da
  /// home: um dia do plano coberto por treino em outro dia fica feito. Dia sem
  /// plano fica feito só se teve treino, senão é folga no passado e livre
  /// adiante. Sem `weekAttendance`, `fallback` nem `sessionDates`, nenhum dia
  /// fica feito; esconder a fita inteira é decisão da tela.
  public init(
    dashboard: Dashboard, today: CalendarDate = .today,
    fallback: [CalendarDate: AttendanceDay]? = nil
  ) {
    let week = dashboard.trainingWeek(today: today, fallback: fallback)
    let attended = Set(week.attended)

    let days = (0..<7).map { offset in
      let date = week.monday.adding(days: offset)
      let state: StreakDayState =
        switch week.slot(on: date)?.state {
        case .done: .done
        case .missed: .missed
        case .today, .upcoming: .planned
        case nil where attended.contains(date): .done
        case nil: date < today ? .rest : .open
        }
      return StreakDay(date: date, state: state)
    }

    self.attendance = StreakFigure(dashboard: dashboard, kind: .attendance)
    self.complete = StreakFigure(dashboard: dashboard, kind: .complete)
    self.weeklyCompleted = week.done
    self.weeklyPlanned = week.planned
    self.days = days
    self.isTodayDone = attended.contains(today)
  }
}

extension Dashboard {
  /// O dia em que a sequência de presença zera se ninguém treinar até lá. Nulo
  /// com a sequência em 0 ou já zerando hoje.
  ///
  /// Vale o `streakResetsOn` do servidor. Sem ele, a mesma conta feita aqui: o
  /// servidor corta a sequência com mais de 5 dias entre dois treinos (o
  /// último treino mais 6) e na falta do plano, o dia planejado que passa sem
  /// treino e sem cobertura. Sem treinar mais, todo dia planejado de hoje em
  /// diante fica sem cobertura e vira falta no dia seguinte.
  public func streakResetDay(
    lastAttended: CalendarDate?, today: CalendarDate,
    fallback: [CalendarDate: AttendanceDay]? = nil
  ) -> CalendarDate? {
    if let streakResetsOn { return streakResetsOn > today ? streakResetsOn : nil }
    guard streak(.attendance) > 0, let last = lastAttended, last < today else { return nil }
    let gap = last.adding(days: 6)
    let week = trainingWeek(today: today, fallback: fallback)
    let sunday = week.monday.adding(days: 6)
    let openThisWeek = week.slots.first { $0.state == .today || $0.state == .upcoming }?.date
    let plannedAfter = sequence(first: sunday.adding(days: 1)) { $0.adding(days: 1) }
      .prefix(while: { $0 < gap })
      .first { schedule.plannedWorkout(on: $0) != nil }
    let miss = (openThisWeek ?? plannedAfter).map { $0.adding(days: 1) }
    let reset = min(gap, miss ?? gap)
    return reset > today ? reset : nil
  }
}
