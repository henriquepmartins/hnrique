import Foundation
import Testing

@testable import HenriqueCore

@Suite("Tempo do treino")
struct WorkoutSessionTimingTests {
  @Test("começa na série mais antiga, de aquecimento ou valendo")
  func startsAtEarliestSet() throws {
    var workout = try emptyWorkout()
    workout.exercises[0].sets.work[0].completedAt = date(10)
    #expect(WorkoutSessionTiming(workout)?.startedAt == date(10))
    workout.exercises[0].sets.prep[0].completedAt = date(20)

    let timing = try #require(WorkoutSessionTiming(workout))
    #expect(timing.startedAt == date(10))
    #expect(timing.finishedAt == nil)
    #expect(timing.elapsed(at: date(103)) == 93)
  }

  @Test("desmarcar a primeira série não empurra o começo para frente")
  func anchorHoldsAfterUnmark() throws {
    var workout = try emptyWorkout()
    workout.exercises[0].sets.prep[0].completedAt = date(1_000)
    workout.exercises[0].sets.prep[1].completedAt = date(1_120)
    let anchor = try #require(WorkoutSessionTiming.anchor(workout, known: nil))
    #expect(anchor == date(1_000))

    workout.exercises[0].sets.prep[0].completedAt = nil
    #expect(WorkoutSessionTiming.anchor(workout, known: anchor) == date(1_000))
    #expect(WorkoutSessionTiming(workout, anchor: anchor)?.startedAt == date(1_000))
    #expect(WorkoutSessionTiming(workout)?.startedAt == date(1_120))

    workout.exercises[0].sets.prep[0].completedAt = date(1_540)
    #expect(WorkoutSessionTiming.anchor(workout, known: anchor) == date(1_000))
    let timing = try #require(WorkoutSessionTiming(workout, anchor: anchor, finishedAt: date(1_600)))
    #expect(timing.elapsed(at: date(9_999)) == 600)
  }

  @Test("o começo do servidor vale quando o aparelho não conhece nenhum")
  func serverStartFillsIn() throws {
    var workout = try emptyWorkout()
    workout.startedAt = date(900)
    #expect(WorkoutSessionTiming.anchor(workout, known: nil) == nil)
    workout.exercises[0].sets.work[0].completedAt = date(1_200)
    #expect(WorkoutSessionTiming.anchor(workout, known: nil) == date(900))
    #expect(WorkoutSessionTiming.anchor(workout, known: date(1_000)) == date(1_000))
    workout.startedAt = date(1_300)
    #expect(WorkoutSessionTiming.anchor(workout, known: nil) == date(1_200))
  }

  @Test("congela no instante da última série concluída")
  func freezesAfterAllSets() throws {
    var workout = try emptyWorkout()
    for exercise in workout.exercises.indices {
      for set in workout.exercises[exercise].sets.prep.indices {
        workout.exercises[exercise].sets.prep[set].completedAt = date(20)
      }
      for set in workout.exercises[exercise].sets.work.indices {
        workout.exercises[exercise].sets.work[set].completedAt = date(100)
      }
    }
    workout.exercises[1].sets.work[1].completedAt = date(3743)

    let timing = try #require(WorkoutSessionTiming(workout))
    #expect(timing.startedAt == date(20))
    #expect(timing.finishedAt == date(3743))
    #expect(timing.elapsed(at: date(4000)) == 3723)
    #expect(timing.elapsed(at: date(5000)) == 3723)
  }

  @Test("usa as datas mesmo com exercícios e séries fora de ordem")
  func usesDatesInsteadOfArrayOrder() throws {
    var workout = try emptyWorkout()
    for exercise in workout.exercises.indices {
      for set in workout.exercises[exercise].sets.prep.indices {
        workout.exercises[exercise].sets.prep[set].completedAt = date(100)
      }
      for set in workout.exercises[exercise].sets.work.indices {
        workout.exercises[exercise].sets.work[set].completedAt = date(200)
      }
    }
    workout.exercises[1].sets.prep[0].completedAt = date(20)
    workout.exercises[0].sets.prep[0].completedAt = date(300)
    workout.exercises.reverse()
    workout.exercises[1].sets.prep.reverse()

    let timing = try #require(WorkoutSessionTiming(workout))
    #expect(timing.startedAt == date(20))
    #expect(timing.finishedAt == date(300))
    #expect(timing.elapsed(at: date(500)) == 280)
  }

  @Test("continua correndo se falta aquecimento mesmo com todo o trabalho feito")
  func waitsForRemainingWarmups() throws {
    var workout = try emptyWorkout()
    workout.exercises[0].sets.prep[0].completedAt = date(20)
    for exercise in workout.exercises.indices {
      for set in workout.exercises[exercise].sets.work.indices {
        workout.exercises[exercise].sets.work[set].completedAt = date(100)
      }
    }
    let timing = try #require(WorkoutSessionTiming(workout))
    #expect(timing.finishedAt == nil)
    #expect(timing.elapsed(at: date(200)) == 180)
  }

  @Test("sem nenhuma série marcada não há cronômetro")
  func requiresWarmup() throws {
    var workout = try emptyWorkout()
    workout.exercises[0].sets.prep[0].completedAt = date(20)
    #expect(WorkoutSessionTiming(workout)?.startedAt == date(20))
    for exercise in workout.exercises.indices {
      workout.exercises[exercise].sets.prep = []
      for set in workout.exercises[exercise].sets.work.indices {
        workout.exercises[exercise].sets.work[set].completedAt = date(100)
      }
    }
    // Um treino só de séries valendo tem relógio, e ele para na última delas.
    #expect(WorkoutSessionTiming(workout)?.startedAt == date(100))
    for exercise in workout.exercises.indices { workout.exercises[exercise].sets.work = [] }
    #expect(WorkoutSessionTiming(workout) == nil)
    workout.exercises = []
    #expect(WorkoutSessionTiming(workout) == nil)
  }

  @Test("duração nunca fica negativa se o relógio recuar")
  func clampsNegativeDuration() throws {
    var workout = try emptyWorkout()
    workout.exercises[0].sets.prep[0].completedAt = date(20)
    let timing = try #require(WorkoutSessionTiming(workout))
    #expect(timing.elapsed(at: date(10)) == 0)
    #expect(timing.elapsed(at: date(30)) == 10)
  }

  @Test("considera apenas as séries existentes e permite desfazer a conclusão")
  func existingSetsDetermineCompletion() throws {
    var workout = try emptyWorkout()
    workout.exercises = [workout.exercises[0]]
    workout.exercises[0].sets.prep = [.init(index: 1, weightKg: 20, reps: 10, completedAt: date(20))]
    workout.exercises[0].sets.work = []
    let finished = try #require(WorkoutSessionTiming(workout))
    #expect(finished.finishedAt == date(20))
    #expect(finished.elapsed(at: date(100)) == 0)

    workout.exercises[0].sets.work = [
      .init(index: 1, weightKg: 40, reps: 10, toFailure: false, completedAt: nil)
    ]
    let running = try #require(WorkoutSessionTiming(workout))
    #expect(running.finishedAt == nil)
    #expect(running.elapsed(at: date(100)) == 80)
    workout.exercises[0].sets.prep[0].completedAt = nil
    #expect(WorkoutSessionTiming(workout) == nil)
  }

  private func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: seconds)
  }

  private func emptyWorkout() throws -> WorkoutSummary {
    var workout = try #require(ContractTests.dashboard().workout)
    for exercise in workout.exercises.indices {
      for set in workout.exercises[exercise].sets.prep.indices {
        workout.exercises[exercise].sets.prep[set].completedAt = nil
      }
      for set in workout.exercises[exercise].sets.work.indices {
        workout.exercises[exercise].sets.work[set].completedAt = nil
      }
    }
    return workout
  }
}
