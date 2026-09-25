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
  public var isAtRisk: Bool
  public var weekProgress: Double
}

extension WorkoutStreak {
  /// Os dias de segunda até `today` com ao menos uma série valendo. É a mesma
  /// presença do contador do topo e do calendário do plano, na mesma semana.
  public static func presentDays(
    in attendance: [CalendarDate: AttendanceDay], today: CalendarDate,
    calendar: Calendar = .trainingWeek
  ) -> Int {
    let monday = today.adding(days: -((today.weekday(in: calendar) + 6) % 7), in: calendar)
    return attendance.values.count { $0.date >= monday && $0.date <= today && $0.workSets > 0 }
  }

  /// A contagem da semana trocada pela presença. `weeklyCompleted` do servidor
  /// conta só treinos completos, e ao lado de um calendário que mostra presença
  /// os dois números não batiam.
  public func counting(presentDays: Int) -> WorkoutStreak {
    var copy = self
    copy.weeklyCompleted = presentDays
    copy.weekProgress = weeklyPlanned > 0 ? min(1, Double(presentDays) / Double(weeklyPlanned)) : 0
    return copy
  }

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
    self.isAtRisk = week.slot(on: today)?.state == .today
    self.weekProgress = week.planned > 0 ? Double(week.done) / Double(week.planned) : 0
  }
}
