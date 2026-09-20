import Foundation
import Testing

@testable import HenriqueCore

/// Os inputs saem do `init` dentro da faixa do zod do servidor, e o 400 de
/// validação vira uma frase que nomeia o campo.
@Suite("Limites do servidor")
struct LimitsTests {
  static let date = CalendarDate(iso: "2026-09-08")!

  @Test("a série gravada fica dentro da faixa do record-set")
  func recordSetClamps() {
    let above = RecordSetInput.Fields(
      date: Self.date, workoutTemplateId: "t", exerciseId: "e", setIndex: 99,
      weightKg: 5_000, reps: 400, completed: true)
    #expect(above.setIndex == 20)
    #expect(above.weightKg == 1_000)
    #expect(above.reps == 100)

    let below = RecordSetInput.Fields(
      date: Self.date, workoutTemplateId: "t", exerciseId: "e", setIndex: 0,
      weightKg: -3, reps: 0, completed: false)
    #expect(below.setIndex == 1)
    #expect(below.weightKg == 0)
    #expect(below.reps == 1)
  }

  @Test("a medida fica dentro da faixa do measurement/add")
  func measurementClamps() {
    let above = AddMeasurementInput(
      date: Self.date, weightKg: 900, bodyFatPercent: 99, waistCm: 400, chestCm: 400, armCm: 200,
      thighCm: 300)
    #expect(above.weightKg == 500)
    #expect(above.bodyFatPercent == 70)
    #expect(above.waistCm == 300)
    #expect(above.chestCm == 300)
    #expect(above.armCm == 100)
    #expect(above.thighCm == 150)

    let below = AddMeasurementInput(
      date: Self.date, weightKg: 1, bodyFatPercent: 0, waistCm: 1, chestCm: 1, armCm: 1, thighCm: 1)
    #expect(below.weightKg == 20)
    #expect(below.bodyFatPercent == 1)
    #expect(below.waistCm == 30)
    #expect(below.chestCm == 30)
    #expect(below.armCm == 10)
    #expect(below.thighCm == 20)

    let empty = AddMeasurementInput(date: Self.date, weightKg: 80)
    #expect(empty.bodyFatPercent == nil)
  }

  @Test("o treino salvo corta nome, foco, minutos e cada exercício")
  func saveWorkoutClamps() {
    let longName = String(repeating: "a", count: 200)
    let exercise = PlanExercise(
      exerciseId: String(repeating: "x", count: 300), prepSets: 9, workSets: 0, repsMin: 60,
      repsMax: 0, workToFailure: true, startingWeightKg: 5_000, name: longName,
      muscleGroup: longName, equipment: longName, imageUrl: String(repeating: "u", count: 900))
    let input = SaveWorkoutInput(
      date: Self.date, workoutTemplateId: nil, weekdays: [1], name: "  \(longName)  ",
      focus: longName, estimatedMinutes: 999, exercises: [exercise])
    #expect(input.name.count == 80)
    #expect(input.focus.count == 140)
    #expect(input.estimatedMinutes == 180)

    let saved = input.exercises[0]
    #expect(saved.exerciseId.count == 120)
    #expect(saved.prepSets == 6)
    #expect(saved.workSets == 1)
    #expect(saved.repsMin == 50)
    #expect(saved.repsMax == 50)
    #expect(saved.startingWeightKg == 1_000)
    #expect(saved.name?.count == 80)
    #expect(saved.muscleGroup?.count == 40)
    #expect(saved.equipment?.count == 40)
    #expect(saved.imageUrl?.count == 500)

    let low = SaveWorkoutInput(
      date: Self.date, workoutTemplateId: nil, weekdays: [], name: "ab", focus: "ab",
      estimatedMinutes: 1, exercises: [])
    #expect(low.estimatedMinutes == 15)
  }

  @Test("as metas ficam dentro da faixa de goal")
  func goalClamps() {
    #expect(SetStrengthGoalInput(date: Self.date, exerciseId: "e", targetValue: 5_000).targetValue == 1_000)
    #expect(SetStrengthGoalInput(date: Self.date, exerciseId: "e", targetValue: 0).targetValue == 1)
    #expect(SetStreakGoalInput(date: Self.date, kind: .attendance, target: 1_000).target == 365)
    #expect(SetStreakGoalInput(date: Self.date, kind: .attendance, target: 0).target == 2)
  }

  @Test("o 400 com issues vira a frase do campo")
  func issuesBecomeSentence() {
    let json = """
      {"defined":true,"code":"BAD_REQUEST","status":400,"message":"Input validation failed",
       "data":{"issues":[
         {"origin":"number","code":"too_big","maximum":100,"inclusive":true,
          "path":["reps"],"message":"Too big: expected number to be <=100"},
         {"origin":"number","code":"too_small","minimum":0,"path":["weightKg"],
          "message":"Too small: expected number to be >=0"}]}}
      """
    #expect(APIClient.serverMessage(from: Data(json.utf8)) == "repetições: no máximo 100")
  }

  @Test("o caminho com índice de array nomeia o campo e conta caracteres")
  func nestedPathNamesField() {
    let json = """
      {"message":"Input validation failed","data":{"issues":[
        {"origin":"string","code":"too_small","minimum":2,"path":["exercises",0,"name"],
         "message":"Too small: expected string to have >=2 characters"}]}}
      """
    #expect(APIClient.serverMessage(from: Data(json.utf8)) == "nome: no mínimo 2 caracteres")
  }

  @Test("um issue sem faixa mostra a mensagem do servidor em minúsculas")
  func issueWithoutBoundsKeepsMessage() {
    let json = """
      {"message":"Input validation failed","data":{"issues":[
        {"code":"custom","path":["repsMax"],
         "message":"O topo da faixa de repetições não pode ser menor que a base"}]}}
      """
    #expect(
      APIClient.serverMessage(from: Data(json.utf8))
        == "reps máx.: o topo da faixa de repetições não pode ser menor que a base")
  }

  @Test("sem issues fica a mensagem que já vinha")
  func withoutIssuesKeepsMessage() {
    #expect(APIClient.serverMessage(from: Data(#"{"message":"treino não existe"}"#.utf8)) == "treino não existe")
    #expect(APIClient.serverMessage(from: Data(#"{"error":"nope"}"#.utf8)) == "nope")
    #expect(APIClient.serverMessage(from: Data("não é json".utf8)) == "servidor recusou")
  }

  @Test("a contagem de séries fica na faixa do tipo: 0 a 6 no aquecimento, 1 a 10 valendo")
  func setCountClamps() {
    let prep = SetCountInput(date: Self.date, workoutTemplateId: "t", exerciseId: "e", kind: .prep, count: 9)
    #expect(prep.count == 6)
    let noPrep = SetCountInput(date: Self.date, workoutTemplateId: "t", exerciseId: "e", kind: .prep, count: -1)
    #expect(noPrep.count == 0)
    let work = SetCountInput(date: Self.date, workoutTemplateId: "t", exerciseId: "e", kind: .work, count: 40)
    #expect(work.count == 10)
    let noWork = SetCountInput(date: Self.date, workoutTemplateId: "t", exerciseId: "e", kind: .work, count: 0)
    #expect(noWork.count == 1)
  }

  @Test("o exercício acrescentado corta as contagens e deixa nulo o que não veio")
  func addSessionExerciseClamps() {
    let above = AddSessionExerciseInput(
      date: Self.date, workoutTemplateId: "t", exerciseId: "e", prepSets: 9, workSets: 40)
    #expect(above.prepSets == 6)
    #expect(above.workSets == 10)
    let empty = AddSessionExerciseInput(date: Self.date, workoutTemplateId: "t", exerciseId: "e")
    #expect(empty.prepSets == nil)
    #expect(empty.workSets == nil)
  }

  @Test("a anotação corta em 500 e o vazio vira nulo")
  func exerciseNoteClamps() {
    let long = SetExerciseNoteInput(
      date: Self.date, workoutTemplateId: "t", exerciseId: "e", note: String(repeating: "n", count: 800))
    #expect(long.note?.count == 500)
    let blank = SetExerciseNoteInput(date: Self.date, workoutTemplateId: "t", exerciseId: "e", note: "   \n")
    #expect(blank.note == nil)
    let none = SetExerciseNoteInput(date: Self.date, workoutTemplateId: "t", exerciseId: "e", note: nil)
    #expect(none.note == nil)
  }
}
