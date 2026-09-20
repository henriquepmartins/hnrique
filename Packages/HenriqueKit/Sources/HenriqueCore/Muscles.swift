import Foundation

/// O catálogo guarda o grupo muscular como texto livre ("Peito", "Costas"). O mapa do
/// corpo precisa de uma chave estável, então a normalização vive aqui e não na tela.
public enum MuscleSlug: String, Codable, CaseIterable, Sendable {
  case peito, dorsal, ombro, trapezio, biceps, triceps, antebraco, abdomen
  case obliquos, lombar, gluteo, quadriceps, posterior, panturrilha, adutores, abdutores

  public var label: String {
    switch self {
    case .peito: "peitoral"
    case .dorsal: "dorsais"
    case .ombro: "ombros"
    case .trapezio: "trapézio"
    case .biceps: "bíceps"
    case .triceps: "tríceps"
    case .antebraco: "antebraço"
    case .abdomen: "abdômen"
    case .obliquos: "oblíquos"
    case .lombar: "lombar"
    case .gluteo: "glúteos"
    case .quadriceps: "quadríceps"
    case .posterior: "posteriores"
    case .panturrilha: "panturrilhas"
    case .adutores: "adutores"
    case .abdutores: "abdutores"
    }
  }
}

public struct MuscleLoad: Codable, Hashable, Sendable, Identifiable {
  public var group: MuscleSlug
  public var setsWeek: Int
  public var setsMonth: Int
  public var lastTrainedDate: CalendarDate?

  public var id: MuscleSlug { group }

  public func sets(in period: MusclePeriod) -> Int {
    period == .week ? setsWeek : setsMonth
  }
}

public enum MusclePeriod: String, CaseIterable, Sendable {
  case week, month

  public var label: String { self == .week ? "semana" : "mês" }
  public var span: String { self == .week ? "7 dias" : "28 dias" }
}

public struct VolumeSummary: Codable, Hashable, Sendable {
  public var weekKg: Double
  public var previousWeekKg: Double
  public var weekSessions: Int

  /// Nulo quando não há semana anterior com que comparar, que é diferente de zero
  /// por cento, e o cartão então não promete uma variação que não existe.
  public var deltaPercent: Int? {
    guard previousWeekKg > 0 else { return nil }
    return Int((((weekKg - previousWeekKg) / previousWeekKg) * 100).rounded())
  }
}
