import Foundation
import Testing

@testable import HenriqueCore

/// O contrato das rotas de estudos. O corpo da página de caderno é escrito pelo
/// BlockNote no web, então a prova mais importante daqui é o conteúdo voltar
/// byte a byte igual depois de passar pelo app.
@Suite("Contrato dos estudos")
struct EstudosContractTests {
  static func amostra() throws -> StudySample {
    try JSONDecoder.henrique().decode(StudySample.self, from: ContractTests.fixture("estudos"))
  }

  @Test("a amostra de estudos decodifica inteira")
  func decodesSample() throws {
    let amostra = try Self.amostra()
    #expect(amostra.subjects.count == 3)
    #expect(amostra.subjects.map(\.color) == ["#0075de", "#ffb110", "#9d95ff"])
    #expect(amostra.subjects[2].code == nil)
    #expect(amostra.subjects[2].semester == nil)
    #expect(amostra.assignments.count == 3)
    #expect(amostra.assignments.flatMap(\.items).count == 4)
    #expect(amostra.queue.cards.count == 2)
    #expect(amostra.queue.bySubject.count == 2)
    #expect(amostra.notebooks.count == 2)
    #expect(amostra.notes.count == 3)
    #expect(amostra.note.links == ["eda/hash", "so/deadlock"])
    #expect(amostra.subject.materials.count == 3)
    #expect(amostra.subject.materials.last?.kind == .link)
    #expect(amostra.subject.materials.last?.lessonNumber == nil)
    #expect(amostra.syncLog.createdCount == 2)
  }

  @Test("o resumo do dia traz a data do calendário")
  func decodesOverview() throws {
    let resumo = try Self.amostra().overview
    #expect(resumo.date.iso == "2026-09-08")
    #expect(resumo.reviewCount == 12)
    #expect(resumo.weekMinutes == 260)
    #expect(resumo.dueSoon.count == 3)
    #expect(resumo.lastSession?.completedMinutes == 50)
    #expect(resumo.lastSync?.status == "ok")
  }

  @Test("a entrega sem matéria decodifica com os três campos nulos")
  func assignmentWithoutSubject() throws {
    let solta = try #require(
      try Self.amostra().assignments.flatMap(\.items).first { $0.id == "a-leitura" })
    #expect(solta.subjectId == nil)
    #expect(solta.subjectName == nil)
    #expect(solta.subjectColor == nil)
    #expect(solta.source == "manual")
  }

  @Test("o status em andamento decodifica e sabe qual é o próximo")
  func inProgressStatus() throws {
    let lista = try #require(
      try Self.amostra().assignments.flatMap(\.items).first { $0.id == "a-lista3" })
    #expect(lista.status == .in_progress)
    #expect(AssignmentStatus.in_progress.next == .done)
    #expect(AssignmentStatus.open.next == .done)
    #expect(AssignmentStatus.done.next == .open)
  }

  @Test("a entrega atrasada fica antes do dia de hoje")
  func overdueAssignment() throws {
    let lista = try #require(
      try Self.amostra().assignments.flatMap(\.items).first { $0.id == "a-lista3" })
    let hoje = try #require(parseTimestamp("2026-09-08T00:00:00.000Z"))
    #expect(lista.dueAt < hoje)
  }

  @Test("o prazo da entrega guarda os milissegundos")
  func dueDateKeepsMilliseconds() throws {
    let leitura = try #require(
      try Self.amostra().assignments.flatMap(\.items).first { $0.id == "a-leitura" })
    let comFracao = try #require(parseTimestamp("2026-09-08T18:30:45.250Z"))
    let semFracao = try #require(parseTimestamp("2026-09-08T18:30:45Z"))
    #expect(leitura.dueAt == comFracao)
    #expect(leitura.dueAt != semFracao)
    #expect(leitura.dueAt.timeIntervalSince(semFracao) == 0.25)
  }

  @Test("o conteúdo do caderno volta igual depois de ir e voltar")
  func notebookContentSurvivesRoundTrip() throws {
    let original = try Self.amostra().page.content
    let dados = try JSONEncoder.henrique().encode(original)
    let devolta = try JSONDecoder.henrique().decode([JSONValue].self, from: dados)
    #expect(devolta == original)
  }

  @Test("o número inteiro do bloco não vira decimal")
  func integralNumberStaysIntegral() throws {
    let dados = try JSONEncoder.henrique().encode(try Self.amostra().page.content)
    let texto = try #require(String(data: dados, encoding: .utf8))
    #expect(
      texto.contains("\"level\":2"),
      "o nível do título sumiu do JSON reenviado ao servidor")
    #expect(
      !texto.contains("\"level\":2.0"),
      "o BlockNote rejeita 2.0 no nível do título, e o app guarda o número como Double")
  }

  @Test("os blocos da página leem o título e o item marcado")
  func blocksReadThePage() throws {
    let blocos = try Self.amostra().page.blocks
    #expect(blocos.count == 4)
    #expect(blocos.first?.type == .paragraph)

    let titulo = try #require(blocos.first { $0.type == .heading })
    #expect(titulo.level == 2)
    #expect(titulo.text == "Rotação dupla esquerda-direita")

    let tarefa = try #require(blocos.first { $0.type == .checkListItem })
    #expect(tarefa.checked == true)
    #expect(tarefa.text == "Refazer o exercício 7 da lista 3")

    #expect(blocos.contains { $0.type == .bulletListItem })
  }

  @Test("nulo no topo vira opcional vazio")
  func topLevelNullDecodesToNil() throws {
    let nulo = Data("null".utf8)
    let decoder = JSONDecoder.henrique()
    #expect(try decoder.decode(Optional<StudyNote>.self, from: nulo) == nil)
    #expect(try decoder.decode(Optional<SubjectDetail>.self, from: nulo) == nil)
    #expect(try decoder.decode(Optional<NotebookPage>.self, from: nulo) == nil)
  }

  @Test("a nota do cartão só manda expectedDueAt quando ele existe")
  func gradeInputOmitsMissingDueDate() throws {
    let prazo = try #require(parseTimestamp("2026-09-12T10:15:30.480Z"))
    let comPrazo = try #require(
      JSONSerialization.jsonObject(
        with: try JSONEncoder.henrique().encode(
          GradeFlashcardInput(id: "card-avl", rating: .facil, expectedDueAt: prazo)))
        as? [String: Any])
    let texto = try #require(comPrazo["expectedDueAt"] as? String)
    #expect(texto.wholeMatch(of: #/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z/#) != nil)
    #expect(texto.hasPrefix("2026-09-12T10:15:30."))

    let semPrazo = try #require(
      JSONSerialization.jsonObject(
        with: try JSONEncoder.henrique().encode(
          GradeFlashcardInput(id: "card-avl", rating: .errei)))
        as? [String: Any])
    #expect(!semPrazo.keys.contains("expectedDueAt"))
    #expect(semPrazo["rating"] as? String == "errei")
  }

  @Test("a entrada com id opcional omite o campo em vez de mandar nulo")
  func optionalIdIsOmitted() throws {
    let sessao = try #require(
      JSONSerialization.jsonObject(
        with: try JSONEncoder.henrique().encode(StartSessionInput(subjectId: "s-eda")))
        as? [String: Any])
    #expect(!sessao.keys.contains("id"))
    #expect(!sessao.keys.contains("materialId"))
    #expect(sessao["subjectId"] as? String == "s-eda")

    let pagina = try #require(
      JSONSerialization.jsonObject(
        with: try JSONEncoder.henrique().encode(
          SaveNotebookPageInput(
            subjectId: "s-eda", title: "Rotações em árvore AVL",
            content: try Self.amostra().page.content)))
        as? [String: Any])
    #expect(!pagina.keys.contains("id"))
    #expect(pagina["title"] as? String == "Rotações em árvore AVL")
    #expect((pagina["content"] as? [Any])?.count == 4)
  }
}

/// A forma do arquivo de fixture: uma resposta de cada rota de estudos. Mora no
/// alvo de testes porque só o teste de contrato decodifica esse arquivo.
struct StudySample: Codable, Hashable, Sendable {
  var overview: StudyOverview
  var subjects: [StudySubject]
  var subject: SubjectDetail
  var assignments: [AssignmentGroup]
  var notes: [NoteSummary]
  var note: StudyNote
  var queue: ReviewQueue
  var notebooks: [Notebook]
  var page: NotebookPage
  var syncLog: SyncLog
}
