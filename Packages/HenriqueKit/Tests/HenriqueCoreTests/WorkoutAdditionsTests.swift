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

  @Test("servidor novo: os três campos chegam")
  func decodesNewFields() throws {
    let extra = #"""
    , "prepWeightKg": 22.5, "restSeconds": 120,
      "previousPrep": {"date": "2026-09-01", "weightKg": 20, "reps": [10], "volumeKg": 200}
    """#
    let exercise = try JSONDecoder.henrique().decode(DashboardExercise.self, from: Self.exerciseJSON(extra: extra))
    #expect(exercise.prepWeightKg == 22.5)
    #expect(exercise.restSeconds == 120)
    #expect(exercise.previousPrep == PreviousWorkSets(
      date: CalendarDate(year: 2026, month: 9, day: 1)!, weightKg: 20, reps: [10], volumeKg: 200))
  }

  @Test("nulos explícitos decodificam como ausentes")
  func decodesExplicitNulls() throws {
    let extra = #", "prepWeightKg": null, "restSeconds": null, "previousPrep": null"#
    let exercise = try JSONDecoder.henrique().decode(DashboardExercise.self, from: Self.exerciseJSON(extra: extra))
    #expect(exercise.prepWeightKg == nil)
    #expect(exercise.restSeconds == nil)
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

  private static func workout() throws -> WorkoutSummary {
    let exercise = try JSONDecoder.henrique().decode(DashboardExercise.self, from: exerciseJSON(extra: ""))
    var prep = exercise
    prep.sets.prep[0].completedAt = Date(timeIntervalSince1970: 1_757_336_000)
    return WorkoutSummary(
      id: "tpl", name: "Empurrar", focus: "peito", estimatedMinutes: 55, exerciseCount: 1,
      workSetCount: 2, completedWorkSetCount: 1, completionPercent: 50, exercises: [prep])
  }
}

@Suite("A semana do treino")
struct TrainingWeekTests {
  private func day(_ value: Int, workSets: Int) -> AttendanceDay {
    AttendanceDay(date: CalendarDate(year: 2026, month: 9, day: value)!, workSets: workSets, completed: false)
  }

  @Test("presença conta de segunda até hoje, sem o domingo anterior")
  func presentDays() {
    // 23 de setembro de 2026 é quarta. Domingo 20 é da semana anterior.
    let attendance = Dictionary(
      uniqueKeysWithValues: [day(20, workSets: 4), day(21, workSets: 3), day(22, workSets: 0), day(23, workSets: 2)]
        .map { ($0.date, $0) })
    let today = CalendarDate(year: 2026, month: 9, day: 23)!
    #expect(WorkoutStreak.presentDays(in: attendance, today: today) == 2)
  }

  @Test("a contagem de presença troca a do servidor e o anel junto")
  func countingPresence() {
    let streak = WorkoutStreak(
      attendance: StreakFigure(count: 3, target: nil), complete: StreakFigure(count: 2, target: nil),
      weeklyCompleted: 2, weeklyPlanned: 3, days: [], isTodayDone: false, isAtRisk: false,
      weekProgress: 2.0 / 3.0)
    let counted = streak.counting(presentDays: 3)
    #expect(counted.weeklyCompleted == 3)
    #expect(counted.weekProgress == 1)
  }

  @Test("o calendário de treino começa na segunda")
  func startsOnMonday() {
    #expect(Calendar.trainingWeek.firstWeekday == 2)
  }
}
