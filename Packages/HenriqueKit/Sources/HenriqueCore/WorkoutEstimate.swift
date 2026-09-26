import Foundation

/// Quanto um treino leva, calculado das séries em vez de digitado.
public enum WorkoutEstimate {
  static let secondsPerSet = 40
  static let restAfterPrep = 60
  static let changeoverPerExercise = 60

  /// 40 s por série, o descanso do exercício depois de cada série valendo
  /// (`rest` nulo é o padrão), 60 s depois de cada aquecimento, sem o descanso
  /// da última série, e 60 s de troca por exercício. Arredonda para cima de 5 em
  /// 5 minutos, dentro da faixa que o servidor aceita.
  public static func minutes(_ exercises: [(prep: Int, work: Int, rest: Int?)]) -> Int {
    let seconds = exercises.reduce(0) { total, exercise in
      let rest = exercise.rest ?? defaultRestSeconds
      return total + secondsPerSet * (exercise.prep + exercise.work)
        + restAfterPrep * exercise.prep + rest * max(0, exercise.work - 1)
        + changeoverPerExercise
    }
    let minutes = (seconds + 299) / 300 * 5
    return minutes.clamped(to: Limits.estimatedMinutes)
  }

  public static func minutes(plan exercises: [PlanExercise]) -> Int {
    minutes(exercises.map { ($0.prepSets, $0.workSets, $0.restSeconds) })
  }
}

extension WorkoutSummary {
  /// Conta as séries da sessão, então "+ série" já muda a estimativa.
  public var estimatedMinutes: Int {
    WorkoutEstimate.minutes(
      exercises.map { ($0.sets.prep.count, $0.sets.work.count, $0.restSeconds) })
  }
}

extension WeekPlanItem {
  public var estimatedMinutes: Int { WorkoutEstimate.minutes(plan: exercises) }
}
