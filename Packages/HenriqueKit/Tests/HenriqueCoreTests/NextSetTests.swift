import Foundation
import Testing

@testable import HenriqueCore

@Suite("A próxima série")
struct NextSetTests {
  private static let at = Date(timeIntervalSince1970: 1_000)

  /// Aquecimento com 20 e 30 kg, valendo com 40, 45 e 50 kg. `true` é série feita.
  private static func exercise(
    _ id: String = "supino", prep: [Bool] = [false, false], work: [Bool] = [false, false, false]
  ) -> DashboardExercise {
    DashboardExercise(
      id: id, name: "Supino Reto", muscleGroup: "peito", equipment: "barra", order: 1,
      prescription: ExercisePrescription(
        prepSets: prep.count, workSets: work.count, repsMin: 6, repsMax: 10, workToFailure: true,
        startingWeightKg: 40),
      sets: ExerciseSets(
        prep: prep.enumerated().map {
          PrepSet(index: $0.offset + 1, weightKg: Double(20 + 10 * $0.offset), reps: 10,
                  completedAt: $0.element ? at : nil)
        },
        work: work.enumerated().map {
          WorkSet(index: $0.offset + 1, weightKg: Double(40 + 5 * $0.offset), reps: 8,
                  toFailure: true, completedAt: $0.element ? at : nil)
        }))
  }

  private func label(_ next: NextSet?) -> String? {
    next.map { "\($0.kind == .prep ? "A" : "W")\($0.index)" }
  }

  @Test("sem nada feito, começa pelo primeiro aquecimento")
  func startsWithWarmup() throws {
    let next = try #require(NextSet.next(in: Self.exercise()))
    #expect(next.exerciseId == "supino")
    #expect(next.exerciseName == "Supino Reto")
    #expect(next.kind == .prep)
    #expect(next.index == 1)
    #expect(next.weightKg == 20)
    #expect(next.reps == 10)
    #expect(!next.toFailure)
  }

  @Test("depois do primeiro aquecimento vem o segundo")
  func secondWarmup() {
    #expect(label(NextSet.next(in: Self.exercise(prep: [true, false]))) == "A2")
  }

  @Test("aquecimento pulado fica para trás")
  func skippedWarmupStaysBehind() throws {
    let next = try #require(
      NextSet.next(in: Self.exercise(prep: [false, false], work: [true, false, false])))
    #expect(next.kind == .work)
    #expect(next.index == 2)
    #expect(next.weightKg == 45)
    #expect(next.toFailure)
    #expect(label(NextSet.next(in: Self.exercise(prep: [true, false], work: [true, false, false]))) == "W2")
  }

  @Test("série valendo pulada volta quando não sobra nenhuma depois")
  func skippedWorkComesBack() {
    #expect(label(NextSet.next(in: Self.exercise(prep: [true, true], work: [false, true, true]))) == "W1")
  }

  @Test("com todas as valendo feitas, o aquecimento em aberto não é próxima")
  func doneExerciseHasNoNext() {
    #expect(NextSet.next(in: Self.exercise(prep: [false, true], work: [true, true, true])) == nil)
  }

  @Test("procura a partir do exercício e dá a volta no treino")
  func searchesAcrossExercises() {
    let done = Self.exercise("remada", prep: [true, true], work: [true, true, true])
    let fresh = Self.exercise("supino")
    let workout = WorkoutSummary(
      id: "tpl", name: "Empurrar", focus: "", estimatedMinutes: 45, exerciseCount: 2,
      workSetCount: 6, completedWorkSetCount: 3, completionPercent: 50,
      exercises: [fresh, done])
    #expect(NextSet(from: 1, in: workout)?.exerciseId == "supino")
    #expect(NextSet(from: 1, in: workout)?.kind == .prep)
    #expect(NextSet(from: 0, in: workout)?.exerciseId == "supino")
    #expect(NextSet(from: 2, in: workout) == nil)

    var finished = workout
    finished.exercises[0] = Self.exercise("supino", prep: [false, false], work: [true, true, true])
    #expect(NextSet(from: 0, in: finished) == nil)
  }
}
