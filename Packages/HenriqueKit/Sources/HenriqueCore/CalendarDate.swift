import Foundation

/// Um dia do calendário, sem hora e sem fuso. A API troca esses dias como
/// "AAAA-MM-DD" e o app nunca deve confundi-los com um instante no tempo.
public struct CalendarDate: Hashable, Sendable, Comparable, Codable {
  public let year: Int
  public let month: Int
  public let day: Int

  public init?(year: Int, month: Int, day: Int) {
    guard (1...12).contains(month), (1...31).contains(day), year > 0 else { return nil }
    self.year = year
    self.month = month
    self.day = day
  }

  public init?(iso: String) {
    let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
      let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
    else { return nil }
    self.init(year: year, month: month, day: day)
  }

  public init(_ date: Date, in calendar: Calendar = .autoupdatingCurrent) {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    self.year = parts.year!
    self.month = parts.month!
    self.day = parts.day!
  }

  public static var today: CalendarDate { CalendarDate(Date()) }

  public var iso: String {
    String(format: "%04d-%02d-%02d", year, month, day)
  }

  public func date(in calendar: Calendar = .autoupdatingCurrent) -> Date {
    var parts = DateComponents()
    parts.year = year
    parts.month = month
    parts.day = day
    parts.hour = 12
    return calendar.date(from: parts) ?? Date()
  }

  public func adding(days: Int, in calendar: Calendar = .autoupdatingCurrent) -> CalendarDate {
    CalendarDate(calendar.date(byAdding: .day, value: days, to: date(in: calendar))!, in: calendar)
  }

  /// Segunda é 1 e domingo é 0, igual ao `getUTCDay` que a API usa para casar
  /// o dia da semana com o modelo de treino.
  public func daysSince(_ other: CalendarDate, in calendar: Calendar = .autoupdatingCurrent) -> Int {
    calendar.dateComponents([.day], from: other.date(in: calendar), to: date(in: calendar)).day ?? 0
  }

  public func weekday(in calendar: Calendar = .autoupdatingCurrent) -> Int {
    calendar.component(.weekday, from: date(in: calendar)) - 1
  }

  public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
    (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
  }

  public init(from decoder: any Decoder) throws {
    let iso = try decoder.singleValueContainer().decode(String.self)
    guard let parsed = CalendarDate(iso: iso) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "data inválida: \(iso)"))
    }
    self = parsed
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(iso)
  }
}
