import Foundation

/// O que o mapa de frequência mostra de cada vez: um mês ou um ano inteiro.
public enum AttendancePeriod: Hashable, Sendable {
  case month(year: Int, month: Int)
  case year(Int)

  public static func month(containing date: CalendarDate) -> AttendancePeriod {
    .month(year: date.year, month: date.month)
  }

  public func range(in calendar: Calendar = .autoupdatingCurrent) -> ClosedRange<CalendarDate> {
    switch self {
    case .month(let year, let month):
      let first = CalendarDate(year: year, month: month, day: 1)!
      let days = calendar.range(of: .day, in: .month, for: first.date(in: calendar))?.count ?? 30
      return first...CalendarDate(year: year, month: month, day: days)!
    case .year(let year):
      return CalendarDate(year: year, month: 1, day: 1)!...CalendarDate(year: year, month: 12, day: 31)!
    }
  }

  public var next: AttendancePeriod {
    switch self {
    case .month(let year, 12): .month(year: year + 1, month: 1)
    case .month(let year, let month): .month(year: year, month: month + 1)
    case .year(let year): .year(year + 1)
    }
  }

  public var previous: AttendancePeriod {
    switch self {
    case .month(let year, 1): .month(year: year - 1, month: 12)
    case .month(let year, let month): .month(year: year, month: month - 1)
    case .year(let year): .year(year - 1)
    }
  }

  /// "setembro de 2026" ou "2026".
  public func title(locale: Locale, calendar: Calendar = .autoupdatingCurrent) -> String {
    let style = Date.FormatStyle(locale: locale, calendar: calendar)
    let first = range(in: calendar).lowerBound.date(in: calendar)
    switch self {
    case .month: return first.formatted(style.month(.wide).year())
    case .year: return first.formatted(style.year())
    }
  }

  /// "setembro" ou "2026", para "12 treinos em setembro".
  public func name(locale: Locale, calendar: Calendar = .autoupdatingCurrent) -> String {
    let style = Date.FormatStyle(locale: locale, calendar: calendar)
    let first = range(in: calendar).lowerBound.date(in: calendar)
    switch self {
    case .month: return first.formatted(style.month(.wide))
    case .year: return first.formatted(style.year())
    }
  }
}

/// A grade do mapa já resolvida: uma semana por linha, sete casas por semana na
/// ordem da semana do calendário, e o total do período. A view só desenha.
public struct AttendanceGrid: Hashable, Sendable {
  public struct Cell: Hashable, Sendable, Identifiable {
    /// O dia daquela casa, mesmo quando cai fora do período. É a identidade
    /// estável da casa na semana.
    public let slot: CalendarDate
    /// Nulo quando a casa é um buraco fora do período.
    public let date: CalendarDate?
    public let workSets: Int

    public var id: CalendarDate { slot }
    public var level: Int { AttendanceGrid.level(workSets: workSets) }
  }

  public struct Week: Hashable, Sendable, Identifiable {
    public let start: CalendarDate
    public let cells: [Cell]

    public var id: CalendarDate { start }
  }

  public let weeks: [Week]
  public let total: Int

  public init(
    period: AttendancePeriod, attendance: [CalendarDate: AttendanceDay],
    calendar: Calendar = .trainingWeek
  ) {
    let range = period.range(in: calendar)
    let offset = (range.lowerBound.weekday(in: calendar) + 1 - calendar.firstWeekday + 7) % 7
    var cursor = range.lowerBound.adding(days: -offset, in: calendar)
    var weeks: [Week] = []
    while cursor <= range.upperBound {
      let cells = (0..<7).map { column -> Cell in
        let slot = cursor.adding(days: column, in: calendar)
        guard range.contains(slot) else { return Cell(slot: slot, date: nil, workSets: 0) }
        return Cell(slot: slot, date: slot, workSets: attendance[slot]?.workSets ?? 0)
      }
      weeks.append(Week(start: cursor, cells: cells))
      cursor = cursor.adding(days: 7, in: calendar)
    }
    self.weeks = weeks
    total = attendance.values.count { range.contains($0.date) && $0.workSets > 0 }
  }

  /// A faixa de cor do dia pela quantidade de séries valendo. Zero é o dia sem
  /// treino, quatro é o mais escuro.
  public static func level(workSets: Int) -> Int {
    switch workSets {
    case ..<1: 0
    case 1...5: 1
    case 6...10: 2
    case 11...15: 3
    default: 4
    }
  }
}
