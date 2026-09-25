import Foundation
import Testing

@testable import HenriqueCore

@Suite("A estimativa do treino")
struct WorkoutEstimateTests {
  @Test("três exercícios de 2 + 3 com 90 s dão 28 min, que sobem para 30")
  func typicalWorkout() {
    // Por exercício: 5 × 40 s + 2 × 60 s + 2 × 90 s + 60 s de troca = 560 s.
    #expect(WorkoutEstimate.minutes(Array(repeating: (prep: 2, work: 3, rest: 90), count: 3)) == 30)
    #expect(WorkoutEstimate.minutes(Array(repeating: (prep: 2, work: 3, rest: nil), count: 3)) == 30)
  }

  @Test("o descanso do exercício entra na conta")
  func restMatters() {
    // 5 × 40 + 2 × 60 + 2 × 150 + 60 = 680 s por exercício, 2040 s ao todo: 34 min.
    #expect(WorkoutEstimate.minutes(Array(repeating: (prep: 2, work: 3, rest: 150), count: 3)) == 35)
  }

  @Test("múltiplo de 5 exato não sobe")
  func exactMultiple() {
    // 15 exercícios de uma série: 15 × (40 + 60) = 1500 s, 25 min.
    #expect(WorkoutEstimate.minutes(Array(repeating: (prep: 0, work: 1, rest: nil), count: 15)) == 25)
  }

  @Test("fica dentro da faixa que o servidor aceita")
  func clamped() {
    #expect(WorkoutEstimate.minutes([]) == 15)
    #expect(WorkoutEstimate.minutes([(prep: 0, work: 1, rest: nil)]) == 15)
    #expect(WorkoutEstimate.minutes(Array(repeating: (prep: 6, work: 10, rest: 600), count: 12)) == 180)
  }

  @Test("o plano e a sessão contam as próprias séries")
  func planAndSession() throws {
    let plan = WeekPlanItem(
      id: "a", weekdays: [1], name: "a", focus: "", exerciseCount: 3,
      exercises: (1...3).map {
        PlanExercise(
          exerciseId: "e\($0)", prepSets: 2, workSets: 3, repsMin: 6, repsMax: 10,
          workToFailure: false, startingWeightKg: 40, restSeconds: 150)
      },
      estimatedMinutes: 55)
    #expect(plan.estimatedMinutesComputed == 35)

    var workout = try #require(ContractTests.dashboard().workout)
    // Supino 2 + 2 e desenvolvimento 1 + 2, descanso padrão:
    // 4 × 40 + 2 × 60 + 90 + 60 = 430 s e 3 × 40 + 60 + 90 + 60 = 330 s. 760 s, 13 min.
    #expect(workout.estimatedMinutesComputed == 15)
    for _ in 0..<6 {
      workout.exercises[0].sets.work.append(
        WorkSet(index: workout.exercises[0].sets.work.count + 1, weightKg: 40, reps: 8, toFailure: false))
    }
    // Mais 6 séries de 40 s + 90 s: 760 + 780 = 1540 s, 26 min.
    #expect(workout.estimatedMinutesComputed == 30)
  }
}
