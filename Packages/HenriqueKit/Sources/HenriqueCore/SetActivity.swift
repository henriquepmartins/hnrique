import Foundation

/// O treino que a Live Activity acompanha. O dia e o treino dizem à store se o
/// painel aberto é o da atividade; o resto não muda durante a sessão.
public struct SetActivityAttributes: Codable, Hashable, Sendable {
  public var date: CalendarDate
  public var templateId: String
  public var workoutName: String
  /// `#rrggbb` da cor do treino.
  public var toneHex: String?

  public init(date: CalendarDate, templateId: String, workoutName: String, toneHex: String?) {
    self.date = date
    self.templateId = templateId
    self.workoutName = workoutName
    self.toneHex = toneHex
  }

  public typealias ContentState = SetActivityState
}

public struct SetActivityState: Codable, Hashable, Sendable {
  /// A série que o botão "feito" marca. Nula quando as séries valendo acabaram.
  public struct Up: Codable, Hashable, Sendable {
    public var exerciseName: String
    /// "A1" no aquecimento, "2" na valendo.
    public var setLabel: String
    /// "48 kg".
    public var weight: String
    public var reps: Int
    public var toFailure: Bool
    public var target: SetKey
  }

  public var up: Up?
  public var rest: ClosedRange<Date>?
  public var done: Int
  public var total: Int

  public init(workout: WorkoutSummary, date: CalendarDate, next: NextSet?, rest: ClosedRange<Date>?) {
    let open = workout.exercises.contains { !$0.sets.work.allSatisfy(\.isDone) }
    up = next.flatMap { next in
      guard open else { return nil }
      return Up(
        exerciseName: next.exerciseName.lowercased(),
        setLabel: next.kind == .prep ? "A\(next.index)" : "\(next.index)",
        weight: "\(Formatting.trim(next.weightKg)) kg",
        reps: next.reps, toFailure: next.toFailure,
        target: SetKey(
          date: date, templateId: workout.id, exerciseId: next.exerciseId, kind: next.kind,
          index: next.index))
    }
    self.rest = rest
    done = workout.completedWorkSetCount
    total = workout.workSetCount
  }
}

/// O "feito" da atividade roda no processo do app, mas o tipo do intent é
/// compilado também na extensão, que não enxerga a store. O app liga isto no
/// arranque; na extensão fica nulo e nunca é chamado.
@MainActor
public enum SetActivityBridge {
  public static var complete: (@MainActor (SetKey) async -> Void)?
}

#if canImport(ActivityKit) && os(iOS)
  import ActivityKit

  extension SetActivityAttributes: ActivityAttributes {}
#endif
