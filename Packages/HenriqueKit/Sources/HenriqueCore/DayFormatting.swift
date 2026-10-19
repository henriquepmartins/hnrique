import Foundation

/// Dia da semana, data curta e duração com uma grafia só em toda tela da
/// academia. O formato do sistema traz "Seg." e "12 de out.", e cada tela
/// tirava um pedaço diferente.
extension Formatting {
  private static let weekdays = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"]
  private static let months = [
    "jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez",
  ]

  /// "seg", "sáb".
  public static func weekday(_ date: CalendarDate, in calendar: Calendar = .autoupdatingCurrent) -> String {
    weekdays[date.weekday(in: calendar)]
  }

  /// "12 out", e "12 out 2025" fora do ano de `today`, para uma lista que
  /// atravessa janeiro não ficar ambígua.
  public static func shortDate(_ date: CalendarDate, today: CalendarDate = .today) -> String {
    let base = "\(date.day) \(months[date.month - 1])"
    return date.year == today.year ? base : "\(base) \(date.year)"
  }

  /// "25 min", "1 h" e "1 h 5 min". A estimativa e o tempo real usam a mesma
  /// grafia; "11:34" podia ser hora do dia.
  public static func duration(minutes: Int) -> String {
    let hours = minutes / 60
    let rest = minutes % 60
    guard hours > 0 else { return "\(minutes) min" }
    return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
  }

  /// Arredonda para o minuto mais perto, sem descer de 1.
  public static func duration(seconds: TimeInterval) -> String {
    duration(minutes: max(1, Int((seconds / 60).rounded())))
  }

  /// O relógio que corre na sessão: "4:13", "1:02:05".
  public static func clock(seconds: TimeInterval) -> String {
    let whole = Int(seconds)
    return Duration.seconds(whole).formatted(.time(pattern: whole >= 3600 ? .hourMinuteSecond : .minuteSecond))
  }
}
