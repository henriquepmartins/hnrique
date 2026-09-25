import Foundation

/// O nível da insígnia, um por mês completo da sequência de presença. Do décimo
/// mês em diante fica em radiante.
public enum StreakTier: Int, CaseIterable, Comparable, Codable, Sendable {
  case ferro = 1, bronze, prata, ouro, platina, diamante, epico, imortal, surreal, radiante

  public init?(months: Int) {
    guard months > 0 else { return nil }
    self = StreakTier(rawValue: min(months, StreakTier.radiante.rawValue))!
  }

  public var name: String {
    switch self {
    case .ferro: "ferro"
    case .bronze: "bronze"
    case .prata: "prata"
    case .ouro: "ouro"
    case .platina: "platina"
    case .diamante: "diamante"
    case .epico: "épico"
    case .imortal: "imortal"
    case .surreal: "surreal"
    case .radiante: "radiante"
    }
  }

  public static func < (lhs: StreakTier, rhs: StreakTier) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Há quanto tempo dura a sequência de presença atual. O servidor só manda a
/// contagem, então o começo sai da frequência com a mesma regra do
/// `calculateStreak` do web: vizinhos a até 5 dias, o mais novo a até 5 de hoje.
public struct StreakTenure: Hashable, Sendable {
  public var start: CalendarDate
  public var months: Int

  public var tier: StreakTier? { StreakTier(months: months) }

  public init(start: CalendarDate, months: Int) {
    self.start = start
    self.months = months
  }

  public init?(
    attendance: [CalendarDate: AttendanceDay], today: CalendarDate,
    calendar: Calendar = .autoupdatingCurrent
  ) {
    let maxGap = 5
    let present = attendance.values.filter { $0.workSets > 0 }.map(\.date).sorted(by: >)
    guard let newest = present.first, today.daysSince(newest, in: calendar) <= maxGap else {
      return nil
    }
    var start = newest
    for day in present.dropFirst() {
      guard start.daysSince(day, in: calendar) <= maxGap else { break }
      start = day
    }
    let months =
      calendar.dateComponents(
        [.month], from: start.date(in: calendar), to: today.date(in: calendar)
      ).month ?? 0
    self.init(start: start, months: months)
  }

  /// O nível a comemorar agora, ou nulo quando não há o que comemorar. Uma
  /// sequência que quebrou e recomeçou tem outro começo e comemora de novo.
  public func celebration(after last: CelebratedTier?) -> CelebratedTier? {
    guard let tier else { return nil }
    if let last, last.start == start, last.tier >= tier { return nil }
    return CelebratedTier(start: start, tier: tier)
  }
}

/// O último nível que a insígnia já comemorou, com o começo da sequência dele.
public struct CelebratedTier: Codable, Hashable, Sendable {
  public var start: CalendarDate
  public var tier: StreakTier

  public init(start: CalendarDate, tier: StreakTier) {
    self.start = start
    self.tier = tier
  }
}
