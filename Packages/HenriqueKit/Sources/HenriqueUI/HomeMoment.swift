import Foundation
import HenriqueCore

/// Onde o dia está em relação ao treino. A home muda a ordem e o cartão do dia
/// por aqui: antes ela chama para começar, durante mostra quanto falta, depois
/// resume o que saiu e sobe a semana, e no descanso aponta o próximo treino.
enum HomeMoment: Equatable {
  case rest
  case before
  case during
  case after

  /// Encerrado no "encerrar" da sessão conta como depois, mesmo com série em
  /// aberto. `finishedAt` é esse toque.
  init(workout: WorkoutSummary?, finishedAt: Date?) {
    guard let workout else {
      self = .rest
      return
    }
    if workout.completionPercent >= 100 || finishedAt != nil {
      self = .after
    } else if workout.completionPercent > 0 {
      self = .during
    } else {
      self = .before
    }
  }

  var sections: [HomeSection] {
    switch self {
    case .before, .during: [.day, .week, .nextDays, .muscles, .records]
    case .after: [.day, .records, .week, .nextDays, .muscles]
    case .rest: [.day, .nextDays, .week, .muscles, .records]
    }
  }
}

enum HomeSection: Hashable {
  case day, week, nextDays, records, muscles
}
