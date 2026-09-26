import Foundation
import Testing

@testable import HenriqueCore

@Suite("Aquecimento, descanso e encerramento no contrato")
struct WorkoutAdditionsTests {
  private static func exerciseJSON(extra: String) -> Data {
    Data(#"""
    {"id": "supino-reto", "name": "Supino reto", "muscleGroup": "peito", "equipment": "barra",
     "order": 1, "prescription": {"prepSets": 1, "workSets": 2, "repsMin": 6, "repsMax": 10,
     "workToFailure": false, "startingWeightKg": 40},
     "previous": {"date": "2026-09-01", "weightKg": 42.5, "reps": [9, 7], "volumeKg": 680},
     "sets": {"prep": [{"index": 1, "weightKg": 20, "reps": 10, "completedAt": null}],
      "work": [{"index": 1, "weightKg": 40, "reps": 8, "toFailure": false, "completedAt": "2026-09-08T13:09:40Z"},
               {"index": 2, "weightKg": 40, "reps": 8, "toFailure": false, "completedAt": null}]}\#(extra)}
    """#.utf8)
  }

  @Test("servidor antigo: sem carga de aquecimento, descanso nem aquecimento anterior")
  func decodesWithoutNewFields() throws {
    let exercise = try JSONDecoder.henrique().decode(DashboardExercise.self, from: Self.exerciseJSON(extra: ""))
    #expect(exercise.prepWeightKg == nil)
    #expect(exercise.restSeconds == nil)
    #expect(exercise.previousPrep == nil)
    #expect(exercise.previous?.weightKg == 42.5)
  }

  @Test("servidor novo: os três campos chegam, o aquecimento série a série")
  func decodesNewFields() throws {
    let extra = #"""
    , "prepWeightKg": 22.5, "restSeconds": 120,
      "previousPrep": {"date": "2026-09-01", "sets": [{"index": 1, "weightKg": 20, "reps": 10}, {"index": 2, "weightKg": 30, "reps": 6}]}
    """#
    let exercise = try JSONDecoder.henrique().decode(DashboardExercise.self, from: Self.exerciseJSON(extra: extra))
    #expect(exercise.prepWeightKg == 22.5)
    #expect(exercise.restSeconds == 120)
    #expect(exercise.previousPrep == PreviousPrepSets(
      date: CalendarDate(year: 2026, month: 9, day: 1)!,
      sets: [.init(index: 1, weightKg: 20, reps: 10), .init(index: 2, weightKg: 30, reps: 6)]))
    #expect(exercise.previousPrep?.set(2)?.weightKg == 30)
    #expect(exercise.previousPrep?.set(3) == nil)
  }

  @Test("nulos explícitos decodificam como ausentes")
  func decodesExplicitNulls() throws {
    let extra = #", "prepWeightKg": null, "restSeconds": null, "previousPrep": null"#
    let exercise = try JSONDecoder.henrique().decode(DashboardExercise.self, from: Self.exerciseJSON(extra: extra))
    #expect(exercise.prepWeightKg == nil)
    #expect(exercise.restSeconds == nil)
    #expect(exercise.previousPrep == nil)
  }

  @Test("formato inesperado nos campos novos não derruba o exercício")
  func toleratesShapeSurprises() throws {
    let extra = #"""
    , "prepWeightKg": "vinte", "restSeconds": 90,
      "previousPrep": {"date": "2026-09-01", "weightKg": 20, "reps": [10], "volumeKg": 200}
    """#
    let exercise = try JSONDecoder.henrique().decode(DashboardExercise.self, from: Self.exerciseJSON(extra: extra))
    #expect(exercise.previousPrep == nil)
    #expect(exercise.prepWeightKg == nil)
    #expect(exercise.restSeconds == 90)
    #expect(exercise.previous?.weightKg == 42.5)
  }

  @Test("o exercício codificado volta igual, com o aquecimento anterior")
  func roundTripsPreviousPrep() throws {
    let extra = #", "previousPrep": {"date": "2026-09-01", "sets": [{"index": 1, "weightKg": 20, "reps": 10}]}"#
    let exercise = try JSONDecoder.henrique().decode(DashboardExercise.self, from: Self.exerciseJSON(extra: extra))
    let again = try JSONDecoder.henrique().decode(
      DashboardExercise.self, from: JSONEncoder.henrique().encode(exercise))
    #expect(again == exercise)
  }

  @Test("o plano decodifica com e sem os campos novos")
  func planExercise() throws {
    let old = #"{"exerciseId": "supino", "prepSets": 2, "workSets": 3, "repsMin": 6, "repsMax": 10, "workToFailure": false, "startingWeightKg": 40}"#
    let new = #"{"exerciseId": "supino", "prepSets": 2, "workSets": 3, "repsMin": 6, "repsMax": 10, "workToFailure": false, "startingWeightKg": 40, "prepWeightKg": 20, "restSeconds": 150}"#
    let before = try JSONDecoder.henrique().decode(PlanExercise.self, from: Data(old.utf8))
    let after = try JSONDecoder.henrique().decode(PlanExercise.self, from: Data(new.utf8))
    #expect(before.prepWeightKg == nil && before.restSeconds == nil)
    #expect(after.prepWeightKg == 20 && after.restSeconds == 150)
  }

  @Test("salvar o plano manda carga de aquecimento e descanso dentro da faixa")
  func saveWorkoutEncodesNewFields() throws {
    let exercises = [
      PlanExercise(
        exerciseId: "supino", prepSets: 2, workSets: 3, repsMin: 6, repsMax: 10, workToFailure: false,
        startingWeightKg: 40, prepWeightKg: 20, restSeconds: 900),
      PlanExercise(
        exerciseId: "remada", prepSets: 1, workSets: 3, repsMin: 8, repsMax: 12, workToFailure: false,
        startingWeightKg: 30),
    ]
    let input = SaveWorkoutInput(
      date: CalendarDate(year: 2026, month: 9, day: 23)!, workoutTemplateId: "tpl", weekdays: [1],
      name: "Empurrar", focus: "peito", estimatedMinutes: 55, exercises: exercises)
    let json = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder.henrique().encode(input)) as? [String: Any])
    let sent = try #require(json["exercises"] as? [[String: Any]])
    #expect(sent[0]["prepWeightKg"] as? Double == 20)
    #expect(sent[0]["restSeconds"] as? Int == 600)
    #expect(sent[1]["prepWeightKg"] == nil)
    #expect(sent[1]["restSeconds"] == nil)
  }

  @Test("gravar série manda a hora do toque só quando a série está feita")
  func recordSetEncodesCompletedAt() throws {
    let date = CalendarDate(year: 2026, month: 9, day: 23)!
    let tapped = Date(timeIntervalSince1970: 1_790_000_000.25)
    func body(_ completed: Bool) throws -> [String: Any] {
      let input = RecordSetInput.work(
        .init(
          date: date, workoutTemplateId: "tpl", exerciseId: "supino", setIndex: 1, weightKg: 40,
          reps: 8, completed: completed, completedAt: tapped),
        toFailure: false)
      return try #require(
        JSONSerialization.jsonObject(with: JSONEncoder.henrique().encode(input)) as? [String: Any])
    }
    #expect(try body(true)["completedAt"] as? String == "2026-09-21T14:13:20.250Z")
    #expect(try body(false)["completedAt"] == nil)
  }

  @Test("encerrar para o relógio na hora do toque")
  func closedTiming() throws {
    let workout = try Self.workout()
    let closed = Date(timeIntervalSince1970: 1_757_337_000)
    let open = try #require(WorkoutSessionTiming(workout))
    #expect(open.finishedAt == nil)
    let timing = try #require(WorkoutSessionTiming(workout, finishedAt: closed))
    #expect(timing.finishedAt == closed)
    #expect(timing.elapsed(at: closed.addingTimeInterval(3_600)) == closed.timeIntervalSince(timing.startedAt))
  }

  @Test("o resumo conta só série valendo e compara com a última vez")
  func recap() throws {
    let workout = try Self.workout()
    let recap = WorkoutRecap(workout, timing: nil)
    #expect(recap.workVolumeKg == 320)
    #expect(recap.doneSets == 1)
    #expect(recap.totalSets == 2)
    #expect(recap.durationSeconds == nil)
    #expect(recap.comparison == WorkoutRecap.VolumeComparison(today: 320, previous: 680))
  }

  @Test("o resumo traz uma linha por exercício com a maior série e os recordes do dia")
  func recapLines() throws {
    var workout = try Self.workout()
    workout.exercises[0].sets.work[1].completedAt = Date(timeIntervalSince1970: 1_757_337_000)
    workout.exercises[0].sets.work[1].weightKg = 45
    workout.exercises[0].sets.work[1].reps = 6
    let day = CalendarDate(iso: "2026-09-08")!
    let today = PersonalRecord(
      exerciseId: "supino-reto", exerciseName: "Supino reto", kind: .carga, weightKg: 45, reps: 6,
      date: day, delta: 2.5)
    let older = PersonalRecord(
      exerciseId: "supino-reto", exerciseName: "Supino reto", kind: .reps, weightKg: 40, reps: 9,
      date: CalendarDate(iso: "2026-09-01")!, delta: 1)
    let recap = WorkoutRecap(workout, timing: nil, records: [older, today], on: day)
    #expect(recap.exercises.count == 1)
    #expect(recap.exercises[0].name == "Supino reto")
    #expect(recap.exercises[0].doneSets == 2)
    #expect(recap.exercises[0].totalSets == 2)
    #expect(recap.exercises[0].top?.weightKg == 45)
    #expect(recap.exercises[0].top?.reps == 6)
    #expect(recap.records == [today])
  }

  @Test("a carga do plano é a série valendo mais pesada feita, não a última")
  func topWorkWeight() throws {
    var workout = try Self.workout()
    workout.exercises[0].sets.work = [
      WorkSet(index: 1, weightKg: 100, reps: 5, toFailure: false, completedAt: .now),
      WorkSet(index: 2, weightKg: 90, reps: 6, toFailure: false, completedAt: .now),
      WorkSet(index: 3, weightKg: 120, reps: 8, toFailure: false),
      WorkSet(index: 4, weightKg: 80, reps: 8, toFailure: false, completedAt: .now),
    ]
    #expect(workout.topWorkWeight(exerciseId: "supino-reto") == 100)
    #expect(workout.topWorkWeight(exerciseId: "outro") == nil)
    workout.exercises[0].sets.work = workout.exercises[0].sets.work.map {
      var set = $0
      set.completedAt = nil
      return set
    }
    #expect(workout.topWorkWeight(exerciseId: "supino-reto") == nil)
  }

  @Test("o número de kg agrupa milhar e só mostra a casa decimal quando existe")
  func trimGroupsThousands() {
    #expect(Formatting.trim(1008) == "1.008")
    #expect(Formatting.trim(26) == "26")
    #expect(Formatting.trim(27.5) == "27,5")
    #expect(Formatting.trim(12_345.5) == "12.345,5")
  }

  @Test("só a estreia usa símbolo no selo")
  func badgeSymbol() {
    #expect(RecordKind.estreia.badgeSymbol == "sparkle")
    #expect(RecordKind.carga.badgeSymbol == nil)
    #expect(RecordKind.carga.badge(delta: 2.5) == "+2,5\nkg")
    #expect(RecordKind.reps.badgeSymbol == nil)
  }

  private static func workout() throws -> WorkoutSummary {
    let exercise = try JSONDecoder.henrique().decode(DashboardExercise.self, from: exerciseJSON(extra: ""))
    var prep = exercise
    prep.sets.prep[0].completedAt = Date(timeIntervalSince1970: 1_757_336_000)
    return WorkoutSummary(
      id: "tpl", name: "Empurrar", focus: "peito", exerciseCount: 1,
      workSetCount: 2, completedWorkSetCount: 1, completionPercent: 50, exercises: [prep])
  }
}
