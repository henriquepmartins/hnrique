import Foundation
import Testing

@testable import HenriqueCore

/// O que o servidor manda e o que o app manda de volta. Se a API mudar de forma,
/// é aqui que quebra, e não numa tela em produção.
@Suite("Contrato com a API")
struct ContractTests {
  static func fixture(_ name: String) throws -> Data {
    let url = try #require(
      Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"),
      "a fixture \(name).json não foi copiada para o bundle de teste")
    return try Data(contentsOf: url)
  }

  static func dashboard() throws -> Dashboard {
    try JSONDecoder.henrique().decode(Dashboard.self, from: fixture("dashboard"))
  }

  @Test("o painel do dia decodifica inteiro")
  func decodesDashboard() throws {
    let dashboard = try Self.dashboard()
    #expect(dashboard.date.iso == "2026-09-08")
    #expect(dashboard.currentStreak == 4)
    #expect(dashboard.attendanceStreak == 6)
    #expect(
      dashboard.streakGoals == [
        StreakGoal(kind: .attendance, target: 10), StreakGoal(kind: .complete, target: 7),
      ])
    #expect(dashboard.streak(.attendance) == 6)
    #expect(dashboard.streak(.complete) == 4)
    #expect(dashboard.goal(.attendance)?.target == 10)
    #expect(dashboard.goal(.complete)?.target == 7)
    #expect(dashboard.weeklyCompleted == 2)
    #expect(dashboard.weeklyPlanned == 4)
    #expect(dashboard.onboardingCompleted)
    #expect(dashboard.workout?.name == "Empurrar A")
    #expect(dashboard.workout?.exercises.count == 2)
  }

  @Test("o instante da série aceita com e sem milissegundos")
  func decodesBothTimestampShapes() throws {
    let exercises = try #require(Self.dashboard().workout?.exercises)
    let comFracao = try #require(exercises[0].sets.prep.first?.completedAt)
    let semFracao = try #require(exercises[0].sets.work.first?.completedAt)
    #expect(comFracao.timeIntervalSince1970 > 0)
    #expect(semFracao.timeIntervalSince1970 > 0)
    #expect(semFracao > comFracao)
  }

  @Test("série sem completedAt fica pendente")
  func openSetHasNoTimestamp() throws {
    let exercises = try #require(Self.dashboard().workout?.exercises)
    #expect(exercises[0].sets.work[0].isDone)
    #expect(!exercises[0].sets.work[1].isDone)
    #expect(exercises[0].sets.completedWorkCount == 1)
  }

  @Test("o exercício sem histórico decodifica com previous nulo")
  func missingPreviousIsNil() throws {
    let exercises = try #require(Self.dashboard().workout?.exercises)
    #expect(exercises[0].previous?.weightKg == 42.5)
    #expect(exercises[1].previous == nil)
  }

  @Test("o exercício sem nota nem origem, do servidor antigo, decodifica com os dois nulos")
  func oldServerExerciseHasNoOverlay() throws {
    let exercises = try #require(Self.dashboard().workout?.exercises)
    #expect(exercises[0].note == nil)
    #expect(exercises[0].origin == nil)
    #expect(!exercises[0].isFromSession)
  }

  @Test("a nota e a origem do exercício decodificam quando o servidor manda")
  func exerciseOverlayDecodes() throws {
    let json = """
      {"id": "remada", "name": "Remada", "muscleGroup": "costas", "equipment": "barra", "order": 3,
       "prescription": {"prepSets": 1, "workSets": 3, "repsMin": 8, "repsMax": 12,
         "workToFailure": false, "startingWeightKg": 30},
       "previous": null, "sets": {"prep": [], "work": []},
       "note": "pegada mais aberta", "origin": "sessao"}
      """
    let exercise = try JSONDecoder.henrique().decode(DashboardExercise.self, from: Data(json.utf8))
    #expect(exercise.note == "pegada mais aberta")
    #expect(exercise.origin == .sessao)
    #expect(exercise.isFromSession)
    let doPlano = try JSONDecoder.henrique().decode(
      DashboardExercise.self, from: Data(json.replacingOccurrences(of: "sessao", with: "plano").utf8))
    #expect(doPlano.origin == .plano)
    #expect(!doPlano.isFromSession)
  }

  @Test("a contagem de séries manda o tipo pelo nome e a contagem inteira")
  func setCountEncodesKind() throws {
    let input = SetCountInput(
      date: CalendarDate(iso: "2026-09-08")!, workoutTemplateId: "t", exerciseId: "e", kind: .work, count: 4)
    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
    #expect(object["kind"] as? String == "work")
    #expect(object["count"] as? Int == 4)
    #expect(object["date"] as? String == "2026-09-08")
  }

  @Test("apagar a anotação manda a chave note com nulo, não a omite")
  func noteEncodesExplicitNull() throws {
    let input = SetExerciseNoteInput(
      date: CalendarDate(iso: "2026-09-08")!, workoutTemplateId: "t", exerciseId: "e", note: "")
    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
    #expect(object.keys.contains("note"))
    #expect(object["note"] is NSNull)
  }

  @Test("as medidas opcionais viram nulo, não zero")
  func nullMeasurementsStayNil() throws {
    let measurement = try #require(Self.dashboard().measurements.first)
    #expect(measurement.weightKg == 78.4)
    #expect(measurement.bodyFatPercent == 18.2)
    #expect(measurement.chestCm == nil)
    #expect(measurement.armCm == nil)
  }

  @Test("a confiança da projeção casa com o enum do servidor")
  func projectionConfidence() throws {
    let projection = try #require(Self.dashboard().projection)
    #expect(projection.confidence == .medium)
    #expect(projection.weeksRemaining == 4)
  }

  @Test("o exercício fica completo quando todas as séries de trabalho terminam")
  func completionMatchesPrescription() throws {
    let exercises = try #require(Self.dashboard().workout?.exercises)
    #expect(!exercises[0].isComplete)
    #expect(exercises[0].prescription.repsLabel == "6–10")
  }

  @Test("a carga de trabalho se repete nos treinos com o mesmo exercício")
  func sharedWorkWeightUpdatesEveryPlanItem() throws {
    var dashboard = try Self.dashboard()
    var otherWorkout = try #require(dashboard.weekPlan.first)
    otherWorkout.id = "tpl-quinta"
    otherWorkout.weekdays = [4]
    otherWorkout.exercises[0].startingWeightKg = 20
    dashboard.weekPlan.append(otherWorkout)

    let updated = dashboard.applyingSharedExerciseWeight(50, exerciseId: "supino-reto")

    #expect(updated.weekPlan.map { $0.exercises[0].startingWeightKg } == [50, 50])
    #expect(updated.workout?.exercises.first?.prescription.startingWeightKg == 50)
  }

  @Test("o aquecimento sai sem o campo de falha")
  func prepSetOmitsToFailure() throws {
    let input = RecordSetInput.prep(
      .init(
        date: try #require(CalendarDate(iso: "2026-09-08")), workoutTemplateId: "tpl-terca",
        exerciseId: "supino-reto", setIndex: 1, weightKg: 20, reps: 10, completed: true))
    let json = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
    #expect(json["kind"] as? String == "prep")
    #expect(json["toFailure"] == nil)
    #expect(json["date"] as? String == "2026-09-08")
    #expect(json["weightKg"] as? Double == 20)
  }

  @Test("a série de trabalho sempre leva o campo de falha")
  func workSetCarriesToFailure() throws {
    let input = RecordSetInput.work(
      .init(
        date: try #require(CalendarDate(iso: "2026-09-08")), workoutTemplateId: "tpl-terca",
        exerciseId: "supino-reto", setIndex: 2, weightKg: 42.5, reps: 9, completed: true),
      toFailure: true)
    let json = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
    #expect(json["kind"] as? String == "work")
    #expect(json["toFailure"] as? Bool == true)
    #expect(json["setIndex"] as? Int == 2)
  }

  @Test("apagar treino manda data e id do treino")
  func deleteWorkoutEncodesKeys() throws {
    let input = DeleteWorkoutInput(
      date: try #require(CalendarDate(iso: "2026-09-08")), workoutTemplateId: "tpl-terca")
    let json = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
    #expect(json["date"] as? String == "2026-09-08")
    #expect(json["workoutTemplateId"] as? String == "tpl-terca")
  }

  @Test("a meta de sequência manda data, tipo e alvo")
  func streakGoalEncodesKeys() throws {
    let input = SetStreakGoalInput(
      date: try #require(CalendarDate(iso: "2026-09-08")), kind: .complete, target: 12)
    let json = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
    #expect(Set(json.keys) == ["date", "kind", "target"])
    #expect(json["date"] as? String == "2026-09-08")
    #expect(json["kind"] as? String == "complete")
    #expect(json["target"] as? Int == 12)
  }

  @Test("a presença de hoje vem de sessionDates ou da série feita no treino do dia")
  func hasAttendedToday() throws {
    let hoje = try #require(CalendarDate(iso: "2026-09-08"))
    let ontem = try #require(CalendarDate(iso: "2026-09-07"))
    var dashboard = try Self.dashboard()

    #expect(dashboard.hasAttended(on: hoje))
    #expect(dashboard.hasAttended(on: ontem))

    dashboard.sessionDates = []
    #expect(dashboard.workout?.completedWorkSetCount == 1)
    #expect(dashboard.hasAttended(on: hoje))
    #expect(!dashboard.hasAttended(on: ontem))

    dashboard.workout?.completedWorkSetCount = 0
    #expect(!dashboard.hasAttended(on: hoje))
  }

  static func planItem(_ json: String) throws -> WeekPlanItem {
    try JSONDecoder.henrique().decode(WeekPlanItem.self, from: Data(json.utf8))
  }

  @Test("o treino do plano decodifica todos os dias")
  func planItemDecodesWeekdays() throws {
    let item = try Self.planItem(
      """
      {"id": "tpl-1", "weekdays": [1, 4], "weekday": 1, "name": "Superiores",
       "focus": "peito e costas", "exerciseCount": 0, "exercises": [], "estimatedMinutes": 55}
      """)
    #expect(item.weekdays == [1, 4])
  }

  @Test("o treino do plano decodifica a cor, e sem ela fica nulo")
  func planItemDecodesColor() throws {
    let comCor = try Self.planItem(
      """
      {"id": "tpl-1", "weekdays": [1], "name": "Superiores", "focus": "peito",
       "exerciseCount": 0, "exercises": [], "estimatedMinutes": 55, "color": "#FF8800"}
      """)
    let semCor = try Self.planItem(
      """
      {"id": "tpl-2", "weekdays": [2], "name": "Pernas", "focus": "quadríceps",
       "exerciseCount": 0, "exercises": [], "estimatedMinutes": 45}
      """)
    #expect(comCor.color == "#FF8800")
    #expect(semCor.color == nil)
  }

  @Test("salvar treino manda a cor só quando ela foi escolhida")
  func saveWorkoutEncodesColorWhenPresent() throws {
    let comCor = SaveWorkoutInput(
      date: try #require(CalendarDate(iso: "2026-09-15")), workoutTemplateId: "tpl-1",
      weekdays: [1], name: "Superiores", focus: "peito", estimatedMinutes: 55, color: "#FF8800",
      exercises: [])
    let json = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(comCor)) as? [String: Any])
    #expect(json["color"] as? String == "#FF8800")
  }

  @Test("a frequência decodifica um dia por linha, com a data como id")
  func attendanceDecodes() throws {
    struct Response: Decodable {
      let days: [AttendanceDay]
    }
    let response = try JSONDecoder.henrique().decode(
      Response.self,
      from: Data(
        """
        {"days": [{"date": "2026-09-14", "workSets": 12, "completed": true},
                  {"date": "2026-09-15", "workSets": 3, "completed": false}]}
        """.utf8))
    #expect(response.days.count == 2)
    #expect(response.days[0].id.iso == "2026-09-14")
    #expect(response.days[0].workSets == 12)
    #expect(response.days[0].completed)
    #expect(!response.days[1].completed)
  }

  @Test("o intervalo de frequência manda from e to como AAAA-MM-DD")
  func attendanceRangeEncodes() throws {
    let input = AttendanceRangeInput(
      from: try #require(CalendarDate(iso: "2026-01-01")),
      to: try #require(CalendarDate(iso: "2026-12-31")))
    let json = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
    #expect(Set(json.keys) == ["from", "to"])
    #expect(json["from"] as? String == "2026-01-01")
    #expect(json["to"] as? String == "2026-12-31")
  }

  @Test("dias fora da semana são recusados", arguments: [-1, 7])
  func planItemRejectsInvalidWeekdays(day: Int) {
    #expect(throws: DecodingError.self) {
      try Self.planItem(
        """
        {"id": "tpl-1", "weekdays": [\(day)], "name": "Superiores", "focus": "peito",
         "exerciseCount": 0, "exercises": [], "estimatedMinutes": 55}
        """)
    }
  }

  @Test("salvar treino manda o id e os dias, sem o weekday antigo")
  func saveWorkoutEncodesWeekdays() throws {
    let input = SaveWorkoutInput(
      date: try #require(CalendarDate(iso: "2026-09-15")), workoutTemplateId: "tpl-1",
      weekdays: [1, 4], name: "Superiores", focus: "peito e costas", estimatedMinutes: 55,
      exercises: [])
    let json = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
    #expect(
      Set(json.keys) == [
        "date", "workoutTemplateId", "weekdays", "name", "focus", "estimatedMinutes", "exercises",
      ])
    #expect(json["workoutTemplateId"] as? String == "tpl-1")
    #expect(json["weekdays"] as? [Int] == [1, 4])
    #expect(json["date"] as? String == "2026-09-15")
  }

  @Test("treino novo sai sem workoutTemplateId")
  func newWorkoutOmitsTemplateId() throws {
    let input = SaveWorkoutInput(
      date: try #require(CalendarDate(iso: "2026-09-15")), workoutTemplateId: nil,
      weekdays: [2], name: "Pernas", focus: "quadríceps", estimatedMinutes: 45, exercises: [])
    let json = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
    #expect(
      Set(json.keys) == ["date", "weekdays", "name", "focus", "estimatedMinutes", "exercises"])
    #expect(json["weekdays"] as? [Int] == [2])
  }

  @Test("a estimativa de 1RM bate com a do servidor")
  func oneRepMaxMatchesServer() {
    #expect(estimateOneRepMax(weightKg: 42.5, reps: 9) == 42.5 * (1 + 9.0 / 30))
    #expect(estimateOneRepMax(weightKg: 60, reps: 1) == 60)
    #expect(estimateOneRepMax(weightKg: 0, reps: 5) == 0)
    #expect(estimateOneRepMax(weightKg: 50, reps: 0) == 0)
  }

  @Test("o volume só conta série concluída")
  func volumeCountsDoneSetsOnly() throws {
    let exercise = try #require(Self.dashboard().workout?.exercises.first)
    #expect(workVolumeKg(exercise.sets.work) == 42.5 * 9)
  }
}

/// A resposta que o servidor mandou de verdade, capturada de
/// `POST /api/v1/workout/record-set` em 8 de setembro de 2026. A fixture escrita
/// à mão cobre os casos ricos; esta prova que o servidor real também decodifica.
@Suite("Resposta capturada do servidor")
struct CapturedResponseTests {
  static func dashboard() throws -> Dashboard {
    try JSONDecoder.henrique().decode(
      Dashboard.self, from: ContractTests.fixture("dashboard-servidor"))
  }

  @Test("decodifica sem perder campo")
  func decodes() throws {
    let dashboard = try Self.dashboard()
    #expect(dashboard.date.iso == "2026-09-13")
    #expect(dashboard.workout != nil)
    #expect(!dashboard.exerciseCatalog.isEmpty)
    #expect(!dashboard.weekPlan.isEmpty)
  }

  @Test("sem os campos de sequência novos, a presença cai para currentStreak")
  func oldServerHasNoStreakFields() throws {
    let dashboard = try Self.dashboard()
    #expect(dashboard.attendanceStreak == nil)
    #expect(dashboard.streakGoals == nil)
    #expect(dashboard.currentStreak == 0)
    #expect(dashboard.streak(.attendance) == 0)
    #expect(dashboard.goal(.attendance) == nil)
  }

  @Test("o painel do servidor traz os dias de cada treino")
  func serverPlanDecodesWeekdays() throws {
    #expect(try Self.dashboard().weekPlan.map(\.weekdays) == [[0], [1], [3], [5]])
  }

  @Test("o instante gravado pelo Postgres decodifica")
  func recordedTimestampDecodes() throws {
    let exercise = try #require(Self.dashboard().workout?.exercises.first)
    let first = try #require(exercise.sets.work.first)
    #expect(first.isDone)
    #expect(first.weightKg == 12.5)
    #expect(first.reps == 11)
    #expect(first.toFailure)
  }

  @Test("a prescrição sem aquecimento vem com lista vazia, não nula")
  func emptyPrepIsEmptyList() throws {
    let exercise = try #require(Self.dashboard().workout?.exercises.first)
    #expect(exercise.sets.prep.isEmpty)
    #expect(exercise.prescription.prepSets == 0)
  }
}
