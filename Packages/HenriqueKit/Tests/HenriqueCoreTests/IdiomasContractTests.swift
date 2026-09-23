import Foundation
import Testing

@testable import HenriqueCore

/// O contrato compartilhado das rotas de idiomas. O app e o servidor precisam
/// decodificar a mesma forma antes de uma tela entrar em produção.
@Suite("Contrato dos idiomas")
struct IdiomasContractTests {
  static func bundle() throws -> LanguageRoutineBundle {
    try JSONDecoder.henrique().decode(
      LanguageRoutineBundle.self, from: ContractTests.fixture("idiomas"))
  }

  @Test("as rotas usam os caminhos do servidor")
  func routes() {
    #expect(Route.idiomasRoutineGet.rawValue == "/api/v1/idiomas/routine/get")
    #expect(Route.idiomasDrillComplete.rawValue == "/api/v1/idiomas/drill/complete")
    #expect(Route.idiomasCorrectionGrade.rawValue == "/api/v1/idiomas/correction/grade")
    #expect(Route.idiomasSessionFinish.rawValue == "/api/v1/idiomas/session/finish")
  }

  @Test("o pacote da rotina traz treinos, fila e progresso")
  func bundleDecodes() throws {
    let bundle = try Self.bundle()
    #expect(bundle.routine.drills.count == 4)
    #expect(bundle.queue.drills.count == 2)
    #expect(bundle.progress.streakCount == 2)
    #expect(bundle.progress.target == 7)
    #expect(bundle.progress.doneDates.map(\.iso) == ["2026-09-14", "2026-09-15"])
  }

  @Test("o treino sem chave do aparelho ganha uma na leitura")
  func missingClientKeyGetsOne() throws {
    let drill = try JSONDecoder.henrique().decode(
      LanguageDrill.self,
      from: Data(
        "{\"id\": \"d1\", \"kind\": \"listen\", \"promptDE\": \"Guten Tag.\", \"glossPT\": \"Boa tarde.\"}".utf8))
    #expect(drill.expectedDE == nil)
    #expect(drill.dueAt == nil)
  }

  @Test("o treino sem chave ganha ids diferentes a cada leitura")
  func missingClientKeyIsUnique() throws {
    let data = Data(
      "{\"id\": \"d1\", \"kind\": \"listen\", \"promptDE\": \"Guten Tag.\", \"glossPT\": \"Boa tarde.\"}".utf8)
    let first = try JSONDecoder.henrique().decode(LanguageDrill.self, from: data)
    let second = try JSONDecoder.henrique().decode(LanguageDrill.self, from: data)
    #expect(first.clientDrillId != second.clientDrillId)
  }

  @Test("o progresso sem alvo decodifica com alvo nulo")
  func missingTargetIsNil() throws {
    let progress = try JSONDecoder.henrique().decode(
      LanguageProgressPayload.self,
      from: Data("{\"doneDates\": [], \"streakCount\": 0}".utf8))
    #expect(progress.target == nil)
    #expect(progress.doneDates.isEmpty)
  }

  @Test("o resultado do treino decodifica prazo e intervalo")
  func completeResultDecodes() throws {
    let sample = try JSONDecoder.henrique().decode(
      LanguageSample.self, from: ContractTests.fixture("idiomas"))
    #expect(sample.complete.id == "drill-ouvir-1")
    #expect(sample.complete.interval == 1)
  }

  @Test("o treino concluído manda attemptId, treino, texto e microfone")
  func completeInputEncodes() throws {
    let attemptId = UUID()
    let json = try #require(
      JSONSerialization.jsonObject(
        with: JSONEncoder.henrique().encode(
          LanguageCompleteInput(
            attemptId: attemptId, drillId: "drill-sombra-1", text: "ich lerne", micUsed: true)))
        as? [String: Any])
    #expect((json["attemptId"] as? String)?.lowercased() == attemptId.uuidString.lowercased())
    #expect(json["drillId"] as? String == "drill-sombra-1")
    #expect(json["text"] as? String == "ich lerne")
    #expect(json["micUsed"] as? Bool == true)
  }

  @Test("a correção com attemptId manda, sem attemptId omite")
  func correctionInputEncodes() throws {
    let attemptId = UUID()
    let comChave = try #require(
      JSONSerialization.jsonObject(
        with: JSONEncoder.henrique().encode(
          LanguageCorrectionInput(attemptId: attemptId, drillId: "d", text: "ich frühstücke")))
        as? [String: Any])
    #expect(comChave["attemptId"] as? String != nil)
    let semChave = try #require(
      JSONSerialization.jsonObject(
        with: JSONEncoder.henrique().encode(
          LanguageCorrectionInput(drillId: "d", text: "ich frühstücke")))
        as? [String: Any])
    #expect(!semChave.keys.contains("attemptId"))
  }

  @Test("o fim da sessão manda os treinos feitos e o dia do aparelho")
  func finishInputEncodes() throws {
    let day = try #require(CalendarDate(iso: "2026-09-22"))
    let json = try #require(
      JSONSerialization.jsonObject(
        with: JSONEncoder.henrique().encode(LanguageFinishInput(drillIds: ["a", "b"], date: day)))
        as? [String: Any])
    #expect(json["drillIds"] as? [String] == ["a", "b"])
    #expect(json["date"] as? String == "2026-09-22")
  }

  @Test("o treino concluído leva o dia do aparelho, que por padrão é hoje")
  func completeInputSendsTheLocalDay() throws {
    let day = try #require(CalendarDate(iso: "2026-09-22"))
    let fixed = try #require(
      JSONSerialization.jsonObject(
        with: JSONEncoder.henrique().encode(
          LanguageCompleteInput(drillId: "d", text: "t", micUsed: false, date: day)))
        as? [String: Any])
    #expect(fixed["date"] as? String == "2026-09-22")
    let standard = try #require(
      JSONSerialization.jsonObject(
        with: JSONEncoder.henrique().encode(
          LanguageCompleteInput(drillId: "d", text: "t", micUsed: false)))
        as? [String: Any])
    #expect(standard["date"] as? String == CalendarDate(Date()).iso)
  }

  @Test("a nota da revisão só vai quando existe")
  func completeRatingOmitted() throws {
    let semNota = try #require(
      JSONSerialization.jsonObject(
        with: JSONEncoder.henrique().encode(
          LanguageCompleteInput(drillId: "d", text: "t", micUsed: false)))
        as? [String: Any])
    #expect(!semNota.keys.contains("rating"))
    let comNota = try #require(
      JSONSerialization.jsonObject(
        with: JSONEncoder.henrique().encode(
          LanguageCompleteInput(drillId: "d", text: "", micUsed: false, rating: .facil)))
        as? [String: Any])
    #expect(comNota["rating"] as? String == "facil")
  }

  @Test("sem a IA a autoavaliação ainda dá prazo")
  func localGradeDegrades() {
    #expect(FlashcardRating.errei.localInterval == 0)
    #expect(FlashcardRating.dificil.localInterval == 1)
    #expect(FlashcardRating.facil.localInterval == 3)
    #expect(FlashcardRating.errei.localHint == "hoje")
    #expect(FlashcardRating.dificil.localHint == "amanhã")
    #expect(FlashcardRating.facil.localHint == "3 dias")
  }

  @Test("o erro de transporte não mostra o endereço do servidor")
  func transportErrorMessage() {
    #expect(APIError.transport(detail: "x").message == "sem conexão")
  }
}
