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

  @Test("nota às 8h não abre o relógio; a primeira série às 18h é o começo")
  func serverStartIsIgnored() throws {
    var workout = try emptyWorkout()
    let eight = date(8 * 3_600)
    let six = date(18 * 3_600)
    #expect(WorkoutSessionTiming.anchor(workout, known: nil) == nil)
    #expect(WorkoutSessionTiming(workout) == nil)
    workout.exercises[0].sets.prep[0].completedAt = six
    #expect(WorkoutSessionTiming.anchor(workout, known: nil) == six)
    #expect(WorkoutSessionTiming(workout)?.startedAt == six)
    #expect(WorkoutSessionTiming.anchor(workout, known: eight) == eight)
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
    #expect(timing.finishedAt == date(200))
    #expect(timing.elapsed(at: date(500)) == 180)
  }

  @Test("aquecimento pulado não segura o relógio depois da última valendo")
  func skippedWarmupDoesNotHoldTheClock() throws {
    var workout = try emptyWorkout()
    workout.exercises[0].sets.prep[0].completedAt = date(20)
    for exercise in workout.exercises.indices {
      for set in workout.exercises[exercise].sets.work.indices {
        workout.exercises[exercise].sets.work[set].completedAt = date(100 + 10 * TimeInterval(set))
      }
    }
    let timing = try #require(WorkoutSessionTiming(workout))
    #expect(timing.finishedAt == date(110))
    #expect(timing.elapsed(at: date(200)) == 90)
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
    workout.exercises[0].sets.work = [
      .init(index: 1, weightKg: 40, reps: 10, toFailure: false, completedAt: nil)
    ]
    let running = try #require(WorkoutSessionTiming(workout))
    #expect(running.finishedAt == nil)
    #expect(running.elapsed(at: date(100)) == 80)

    workout.exercises[0].sets.work[0].completedAt = date(60)
    #expect(WorkoutSessionTiming(workout)?.finishedAt == date(60))
    workout.exercises[0].sets.work[0].completedAt = nil
    #expect(WorkoutSessionTiming(workout)?.finishedAt == nil)
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
