import Foundation

/// O tipo de recorde. Subir carga e subir repetição com a mesma carga são progressos
/// diferentes, e a lista precisa dizer qual dos dois aconteceu.
public enum RecordKind: String, Codable, Hashable, Sendable {
  case carga, reps, estreia

  /// O selo da estreia é um símbolo, não texto: "1º" ao lado de "estreia"
  /// dizia a mesma coisa duas vezes.
  public var badgeSymbol: String? { self == .estreia ? "sparkle" : nil }

  /// O selo da esquerda, com o número em cima e a unidade embaixo. Em uma linha
  /// só, "+2,5 kg" não cabe nos 42 pontos do quadrado. A estreia não tem
  /// número e usa `badgeSymbol`.
  public func badge(delta: Double) -> String? {
    switch self {
    case .carga: "+\(Formatting.trim(delta))\nkg"
    case .reps: "+\(Int(delta))\nrep"
    case .estreia: nil
    }
  }

  public var label: String {
    switch self {
    case .carga: "carga"
    case .reps: "reps"
    case .estreia: "estreia"
    }
  }
}

public struct PersonalRecord: Codable, Hashable, Sendable, Identifiable {
  public var exerciseId: String
  public var exerciseName: String
  public var kind: RecordKind
  public var weightKg: Double
  public var reps: Int
  public var date: CalendarDate
  public var delta: Double

  public var id: String { "\(exerciseId).\(date.iso)" }

  public init(
    exerciseId: String, exerciseName: String, kind: RecordKind, weightKg: Double, reps: Int,
    date: CalendarDate, delta: Double
  ) {
    self.exerciseId = exerciseId
    self.exerciseName = exerciseName
    self.kind = kind
    self.weightKg = weightKg
    self.reps = reps
    self.date = date
    self.delta = delta
  }

  /// "26 kg × 8 · há 3 dias". A data importa tanto quanto o número: um recorde de
  /// ontem lê diferente de um de duas semanas atrás.
  public func summary(today: CalendarDate) -> String {
    "\(Formatting.trim(weightKg)) kg × \(reps) · \(ago(today: today))"
  }

  private func ago(today: CalendarDate) -> String {
    switch today.daysSince(date) {
    case ..<1: "hoje"
    case 1: "ontem"
    case let days: "há \(days) dias"
    }
  }
}

public enum Formatting {
  /// 26.0 vira "26", 27.5 continua "27,5" e 1008 vira "1.008". Meio quilo
  /// existe nas anilhas, o ",0" não.
  public static func trim(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "pt_BR")))
  }
}
