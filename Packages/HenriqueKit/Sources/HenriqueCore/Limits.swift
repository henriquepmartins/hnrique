import Foundation

/// As faixas que o servidor aceita, copiadas do zod em
/// `packages/domain/src/index.ts` do repo web. Cada grupo diz a linha de
/// origem. Uma tela ou um input que precisar de faixa lê daqui; nada de
/// número solto, que é como as faixas divergiram da primeira vez.
public enum Limits {
  // record-set: index.ts:12-20 (recordSetShape)
  public static let setIndex = 1...20
  public static let setWeightKg = 0.0...1_000.0
  public static let reps = 1...100

  // measurement/add: index.ts:27-35 (addMeasurementInputSchema)
  public static let bodyWeightKg = 20.0...500.0
  public static let bodyFatPercent = 1.0...70.0
  public static let waistCm = 30.0...300.0
  public static let chestCm = 30.0...300.0
  public static let armCm = 10.0...100.0
  public static let thighCm = 20.0...150.0

  // plan/save-workout, cada exercício: index.ts:37-54 (planExerciseInputSchema)
  public static let exerciseIdLength = 1...120
  public static let prepSets = 0...6
  public static let workSets = 1...10
  public static let planReps = 1...50
  public static let startingWeightKg = 0.0...1_000.0
  /// Ainda não está no zod; é a mesma faixa do ajuste de ±15 s da sessão.
  public static let restSeconds = 15...600
  public static let exerciseNameLength = 2...80
  public static let muscleGroupLength = 2...40
  public static let equipmentLength = 2...40
  public static let imageUrlLength = 0...500

  // plan/save-workout, o treino: index.ts:56-69 (saveWorkoutInputSchema)
  public static let workoutNameLength = 2...80
  public static let workoutFocusLength = 2...140
  public static let estimatedMinutes = 15...180
  public static let exerciseCount = 1...12

  // goal/set-strength: index.ts:76-80
  public static let strengthTarget = 1.0...1_000.0

  // goal/set-streak: index.ts:82-86
  public static let streakTarget = 2...365

  // workout/set-count e workout/add-exercise usam `prepSets` e `workSets`.
  // workout/set-note: o texto vazio vira nulo antes de sair.
  public static let exerciseNoteLength = 0...500
}

extension Comparable {
  public func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}

extension String {
  /// Corta pelo teto da faixa. O piso não tem como ser forçado numa string,
  /// então fica para a tela pedir mais caracteres.
  public func cut(to range: ClosedRange<Int>) -> String {
    String(prefix(range.upperBound))
  }
}
