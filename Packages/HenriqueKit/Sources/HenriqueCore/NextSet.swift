import Foundation

/// A série que vem depois, aquecimento antes de valendo. O descanso só ajuda com
/// o próximo peso à vista, e a busca segue para o exercício seguinte porque
/// terminar um exercício não encerra a pausa.
public struct NextSet: Equatable, Sendable {
  public let exerciseId: String
  public let exerciseName: String
  public let kind: SetKind
  public let index: Int
  public let weightKg: Double
  public let reps: Int
  public let toFailure: Bool

  /// A primeira série não feita depois da última feita no exercício. Um
  /// aquecimento pulado fica para trás e não volta a ser a próxima; uma série
  /// valendo pulada volta quando não sobra nenhuma depois.
  public static func next(in exercise: DashboardExercise) -> NextSet? {
    func set(_ kind: SetKind, _ index: Int, _ weightKg: Double, _ reps: Int, _ toFailure: Bool)
      -> NextSet
    {
      NextSet(
        exerciseId: exercise.id, exerciseName: exercise.name, kind: kind, index: index,
        weightKg: weightKg, reps: reps, toFailure: toFailure)
    }
    let prep = exercise.sets.prep.sorted { $0.index < $1.index }
      .map { (set: set(.prep, $0.index, $0.weightKg, $0.reps, false), isDone: $0.isDone) }
    let work = exercise.sets.work.sorted { $0.index < $1.index }
      .map { (set: set(.work, $0.index, $0.weightKg, $0.reps, $0.toFailure), isDone: $0.isDone) }
    let ordered = prep + work
    let start = ordered.lastIndex { $0.isDone }.map { $0 + 1 } ?? 0
    return ordered[start...].first { !$0.isDone }?.set ?? work.first { !$0.isDone }?.set
  }

  /// Procura a partir de `exerciseIndex` e dá a volta no treino.
  public init?(from exerciseIndex: Int, in workout: WorkoutSummary) {
    guard workout.exercises.indices.contains(exerciseIndex) else { return nil }
    for step in 0..<workout.exercises.count {
      let exercise = workout.exercises[(exerciseIndex + step) % workout.exercises.count]
      if let next = Self.next(in: exercise) {
        self = next
        return
      }
    }
    return nil
  }

  private init(
    exerciseId: String, exerciseName: String, kind: SetKind, index: Int, weightKg: Double,
    reps: Int, toFailure: Bool
  ) {
    self.exerciseId = exerciseId
    self.exerciseName = exerciseName
    self.kind = kind
    self.index = index
    self.weightKg = weightKg
    self.reps = reps
    self.toFailure = toFailure
  }
}
