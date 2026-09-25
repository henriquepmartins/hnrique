import Foundation
import HenriqueCore
import Testing

@testable import HenriqueUI

/// A rede do teste. Ela recusa tudo enquanto `offline` estiver ligado, que é o
/// que acontece na academia, e conta quantas vezes o app tentou gravar a série.
/// `recordStatus` faz o servidor responder um status por exercício.
final class FakeNetwork: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var offline = true
  nonisolated(unsafe) static var recordedSets = 0
  nonisolated(unsafe) static var recordStatus: [String: Int] = [:]
  /// Gravações que chegaram ao servidor, por exercício, com o corpo da última.
  nonisolated(unsafe) static var answered: [String: Int] = [:]
  nonisolated(unsafe) static var lastBody: [String: [String: Any]] = [:]

  static func reset() {
    offline = true
    recordedSets = 0
    recordStatus = [:]
    answered = [:]
    lastBody = [:]
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}

  override func startLoading() {
    let path = request.url?.path ?? ""
    if path == Route.recordSet.rawValue { Self.recordedSets += 1 }
    guard !Self.offline else {
      client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
      return
    }
    var status = 200
    var body = dashboardDeHoje()
    if path == Route.recordSet.rawValue, let json = Self.body(of: request),
      let exercise = json["exerciseId"] as? String {
      Self.answered[exercise, default: 0] += 1
      Self.lastBody[exercise] = json
      if let forced = Self.recordStatus[exercise] {
        status = forced
        body = #"{"message":"recusada no teste"}"#
      }
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  /// O URLSession entrega o corpo como stream ao protocolo, não em `httpBody`.
  private static func body(of request: URLRequest) -> [String: Any]? {
    var data = request.httpBody ?? Data()
    if data.isEmpty, let stream = request.httpBodyStream {
      stream.open()
      defer { stream.close() }
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: buffer.count)
        guard read > 0 else { break }
        data.append(buffer, count: read)
      }
    }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }
}

/// O alarme do descanso sem a central de notificações: guarda o que foi pedido.
@MainActor
final class FakeRestAlarm: RestAlarm {
  var scheduled: Date?
  var next: NextSet?
  var cancels = 0

  func schedule(at date: Date, next: NextSet?) {
    scheduled = date
    self.next = next
  }
  func cancel() {
    scheduled = nil
    cancels += 1
  }
}

struct MemoryTokenStore: TokenStore {
  nonisolated(unsafe) static var token: String? = "sessao-de-teste"
  func read() -> String? { Self.token }
  func write(_ token: String?) { Self.token = token }
}

/// Um `UserDefaults` só da suíte, limpo a cada teste, para o descanso e o
/// "encerrar" de um teste não vazarem para o outro.
let testDefaultsSuite = "henrique.testes.academia"

@MainActor
func makeStore(alarm: FakeRestAlarm = FakeRestAlarm()) -> AcademiaStore {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [FakeNetwork.self]
  let client = APIClient(
    baseURL: URL(string: "https://exemplo.invalido")!,
    tokenStore: MemoryTokenStore(),
    session: URLSession(configuration: configuration))
  let store = AcademiaStore(
    client: client, restAlarm: alarm, defaults: UserDefaults(suiteName: testDefaultsSuite)!)
  store.resendsAutomatically = false
  return store
}

@MainActor
func resetLocalState() {
  UserDefaults(suiteName: testDefaultsSuite)!.removePersistentDomain(forName: testDefaultsSuite)
  limparFila()
}

/// O painel só é aceito quando a data que volta é a data pedida, então a
/// fixture nasce com a data de hoje em vez de uma escrita à mão que vence.
func dashboardDeHoje() -> String {
  dashboardJSON.replacingOccurrences(of: "2026-09-17", with: CalendarDate.today.iso)
}

private let chave = SetKey(
  date: .today, templateId: "tpl-terca", exerciseId: "supino-reto", kind: .work, index: 1)

/// A academia começa com sinal: você abre o app em casa, o painel carrega, e o
/// sinal some lá dentro. Marcar série antes do painel existir é outro caso.
@MainActor
func lojaComPainel(alarm: FakeRestAlarm = FakeRestAlarm()) async -> AcademiaStore {
  FakeNetwork.offline = false
  let store = makeStore(alarm: alarm)
  await store.start()
  FakeNetwork.offline = true
  return store
}

@Suite("A fila de séries não enviadas", .serialized)
@MainActor
struct PendingSetQueueTests {
  init() {
    FakeNetwork.reset()
    resetLocalState()
  }

  @Test("sem rede a série continua marcada na tela")
  func keepsTheMarkOffline() async {
    let store = await lojaComPainel()
    _ = await store.record(key: chave, weightKg: 42.5, reps: 9, completed: true, toFailure: true)?
      .value

    #expect(store.isWaiting(chave))
    // Sem alerta: o alerta por cima da sessão de treino fechava a sessão.
    #expect(store.banner == nil)
    #expect(store.waitingCount == 1)
    let série = store.dashboard?.workout?.exercises
      .first { $0.id == chave.exerciseId }?.sets.work.first { $0.index == chave.index }
    #expect(série?.isDone == true)
    #expect(série?.weightKg == 42.5)
  }

  @Test("a série guardada chega ao servidor quando a rede volta")
  func resendsWhenTheNetworkReturns() async {
    let store = await lojaComPainel()
    _ = await store.record(key: chave, weightKg: 42.5, reps: 9, completed: true, toFailure: true)?
      .value
    #expect(store.isWaiting(chave))
    let tentativasOffline = FakeNetwork.recordedSets

    store.resendsAutomatically = true
    FakeNetwork.offline = false
    await store.load()
    await esperar { !store.isWaiting(chave) }

    #expect(!store.isWaiting(chave))
    #expect(FakeNetwork.recordedSets > tentativasOffline)
  }

  @Test("leituras e edições offline conservam a data da marcação", arguments: [SetKind.prep, .work])
  func preservesPendingCompletionDate(kind: SetKind) async throws {
    let store = await lojaComPainel()
    let key = SetKey(
      date: .today, templateId: chave.templateId, exerciseId: chave.exerciseId, kind: kind, index: 2)
    let before = Date.now
    _ = await store.record(key: key, weightKg: 30, reps: 10, completed: true, toFailure: false)?.value
    let after = Date.now
    let first = try #require(completionDate(in: store, key: key))
    #expect(first >= before && first <= after)
    #expect(store.isWaiting(key))
    #expect(completionDate(in: store, key: key) == first)

    _ = await store.record(key: key, weightKg: 35, reps: 8, completed: true, toFailure: false)?.value
    #expect(completionDate(in: store, key: key) == first)
    let sets = try #require(store.dashboard?.workout?.exercises.first?.sets)
    #expect(kind == .prep ? sets.prep[1].weightKg == 35 : sets.work[1].weightKg == 35)
    #expect(kind == .prep ? sets.prep[1].reps == 8 : sets.work[1].reps == 8)

    _ = await store.record(key: key, weightKg: 35, reps: 8, completed: false, toFailure: false)?.value
    #expect(completionDate(in: store, key: key) == nil)
    let remarkedAfter = Date.now
    _ = await store.record(key: key, weightKg: 35, reps: 8, completed: true, toFailure: false)?.value
    let remarked = try #require(completionDate(in: store, key: key))
    #expect(remarked >= remarkedAfter)
    #expect(remarked > first)
  }

  @Test("editar série já salva conserva a data do servidor", arguments: [SetKind.prep, .work])
  func preservesAcceptedCompletionDate(kind: SetKind) async throws {
    let store = await lojaComPainel()
    let key = SetKey(
      date: .today, templateId: chave.templateId, exerciseId: chave.exerciseId, kind: kind, index: 1)
    let expected = try Date.ISO8601FormatStyle(includingFractionalSeconds: kind == .prep).parse(
      kind == .prep ? "2026-09-08T13:02:11.482Z" : "2026-09-08T13:09:40Z")
    let original = try #require(completionDate(in: store, key: key))
    #expect(abs(original.timeIntervalSince(expected)) < 0.000001)
    _ = await store.record(key: key, weightKg: 45, reps: 8, completed: true, toFailure: true)?.value
    #expect(completionDate(in: store, key: key) == original)
  }

  @Test("rascunho antigo sem data continua decodificando")
  func decodesLegacyDraft() throws {
    let legacy = Data(#"{"weightKg":30,"reps":10,"completed":true,"toFailure":false}"#.utf8)
    let draft = try JSONDecoder.henrique().decode(SetDraft.self, from: legacy)
    #expect(draft.completed)
    #expect(draft.weightKg == 30)
    #expect(draft.completedAt == nil)

    let dated = SetDraft(weightKg: 30, reps: 10, completed: true, toFailure: false,
      completedAt: Date(timeIntervalSince1970: 100))
    let restored = try JSONDecoder.henrique().decode(
      SetDraft.self, from: JSONEncoder.henrique().encode(dated))
    #expect(restored.completedAt == Date(timeIntervalSince1970: 100))
  }

  @Test("a série manda a hora do toque, não a da chegada")
  func sendsCompletionDate() async throws {
    let store = await lojaComPainel()
    FakeNetwork.offline = false
    let key = SetKey(
      date: .today, templateId: chave.templateId, exerciseId: "desenvolvimento", kind: .work, index: 1)
    let outcome = await store.record(key: key, weightKg: 14, reps: 12, completed: true, toFailure: false)?
      .value
    #expect(outcome == .applied)
    let sent = try #require(FakeNetwork.lastBody["desenvolvimento"]?["completedAt"] as? String)
    #expect(parseTimestamp(sent) != nil)
  }

  @Test("recusa 4xx sai da fila na hora e vira aviso sem alerta")
  func dropsRefusedSet() async {
    let store = await lojaComPainel()
    FakeNetwork.offline = false
    FakeNetwork.recordStatus["supino-reto"] = 400
    let key = SetKey(
      date: .today, templateId: chave.templateId, exerciseId: "supino-reto", kind: .work, index: 2)

    let outcome = await store.record(key: key, weightKg: 42.5, reps: 8, completed: true, toFailure: true)?
      .value

    #expect(outcome == .refused)
    #expect(!store.isWaiting(key))
    #expect(store.waitingCount == 0)
    #expect(store.banner == nil)
    #expect(store.notice == "série não salva: recusada no teste")
    #expect(completionDate(in: store, key: key) == nil)
    #expect(FakeNetwork.answered["supino-reto"] == 1)
  }

  @Test("5xx repetido sai da fila na quinta vez e não segura as outras")
  func skipsPoisonedSet() async {
    let store = await lojaComPainel()
    let poisoned = SetKey(
      date: .today, templateId: chave.templateId, exerciseId: "supino-reto", kind: .work, index: 2)
    let healthy = SetKey(
      date: .today, templateId: chave.templateId, exerciseId: "desenvolvimento", kind: .work, index: 1)
    _ = await store.record(key: poisoned, weightKg: 42.5, reps: 8, completed: true, toFailure: true)?.value
    _ = await store.record(key: healthy, weightKg: 14, reps: 12, completed: true, toFailure: false)?.value
    #expect(store.waitingCount == 2)

    FakeNetwork.offline = false
    FakeNetwork.recordStatus["supino-reto"] = 500
    #expect(await store.resend() == false)
    #expect(!store.isWaiting(healthy))
    #expect(store.isWaiting(poisoned))

    for _ in 0..<3 { _ = await store.resend() }
    #expect(store.isWaiting(poisoned))
    #expect(FakeNetwork.answered["supino-reto"] == 4)
    #expect(store.notice == nil)

    _ = await store.resend()
    #expect(!store.isWaiting(poisoned))
    #expect(store.waitingCount == 0)
    #expect(FakeNetwork.answered["supino-reto"] == 5)
    #expect(store.notice == "série não salva: recusada no teste")
  }

  @Test("uma série que o servidor recusou uma vez volta do disco com a conta")
  func keepsServerFailuresAcrossRelaunch() async {
    let first = await lojaComPainel()
    FakeNetwork.offline = false
    FakeNetwork.recordStatus["supino-reto"] = 503
    let key = SetKey(
      date: .today, templateId: chave.templateId, exerciseId: "supino-reto", kind: .work, index: 2)
    _ = await first.record(key: key, weightKg: 42.5, reps: 8, completed: true, toFailure: true)?.value
    for _ in 0..<3 { _ = await first.resend() }
    #expect(FakeNetwork.answered["supino-reto"] == 4)

    let second = makeStore()
    #expect(second.isWaiting(key))
    await second.start()
    _ = await second.resend()
    #expect(!second.isWaiting(key))
    #expect(FakeNetwork.answered["supino-reto"] == 5)
  }

  @Test("a série guardada sobrevive ao app fechar")
  func survivesRelaunch() async throws {
    let primeiro = await lojaComPainel()
    _ = await primeiro.record(
      key: chave, weightKg: 42.5, reps: 9, completed: true, toFailure: true)?.value
    #expect(primeiro.isWaiting(chave))
    let completedAt = try #require(completionDate(in: primeiro, key: chave))

    let segundo = makeStore()
    #expect(segundo.isWaiting(chave))
    #expect(completionDate(in: segundo, key: chave) == completedAt)
  }
}

@MainActor
func completionDate(in store: AcademiaStore, key: SetKey) -> Date? {
  let sets = store.dashboard?.workout?.exercises.first { $0.id == key.exerciseId }?.sets
  return key.kind == .prep
    ? sets?.prep.first { $0.index == key.index }?.completedAt
    : sets?.work.first { $0.index == key.index }?.completedAt
}

/// O disco é o mesmo para toda a suíte, então cada teste começa com ele limpo.
@MainActor
func limparFila() {
  guard let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
    .first?.appending(path: "henrique-series-pendentes.json")
  else { return }
  try? FileManager.default.removeItem(at: url)
}

func esperar(_ condicao: @MainActor () -> Bool) async {
  for _ in 0..<200 {
    if await MainActor.run(body: condicao) { return }
    try? await Task.sleep(for: .milliseconds(25))
  }
}

private let dashboardJSON = #"""
{"date": "2026-09-17", "workout": {"id": "tpl-terca", "name": "Empurrar A", "focus": "peito, ombro e tríceps", "estimatedMinutes": 55, "exerciseCount": 2, "workSetCount": 4, "completedWorkSetCount": 1, "completionPercent": 25, "exercises": [{"id": "supino-reto", "name": "Supino reto", "muscleGroup": "peito", "equipment": "barra", "order": 1, "prescription": {"prepSets": 2, "workSets": 2, "repsMin": 6, "repsMax": 10, "workToFailure": true, "startingWeightKg": 40}, "previous": {"date": "2026-09-01", "weightKg": 42.5, "reps": [9, 7], "volumeKg": 680}, "sets": {"prep": [{"kind": "prep", "index": 1, "weightKg": 20, "reps": 10, "completedAt": "2026-09-08T13:02:11.482Z"}, {"kind": "prep", "index": 2, "weightKg": 30, "reps": 10, "completedAt": null}], "work": [{"kind": "work", "index": 1, "weightKg": 42.5, "reps": 9, "toFailure": true, "completedAt": "2026-09-08T13:09:40Z"}, {"kind": "work", "index": 2, "weightKg": 42.5, "reps": 10, "toFailure": true, "completedAt": null}]}}, {"id": "desenvolvimento", "name": "Desenvolvimento com halteres", "muscleGroup": "ombro", "equipment": "halteres", "order": 2, "prescription": {"prepSets": 1, "workSets": 2, "repsMin": 8, "repsMax": 12, "workToFailure": false, "startingWeightKg": 14}, "previous": null, "sets": {"prep": [{"kind": "prep", "index": 1, "weightKg": 10, "reps": 12, "completedAt": null}], "work": [{"kind": "work", "index": 1, "weightKg": 14, "reps": 12, "toFailure": false, "completedAt": null}, {"kind": "work", "index": 2, "weightKg": 14, "reps": 12, "toFailure": false, "completedAt": null}]}}]}, "consistencyPercent": 75, "currentStreak": 4, "attendanceStreak": 6, "streakGoals": [{"kind": "attendance", "target": 10}, {"kind": "complete", "target": 7}], "weeklyCompleted": 2, "weeklyPlanned": 4, "weekPlan": [{"id": "tpl-terca", "weekdays": [2], "weekday": 2, "name": "Empurrar A", "focus": "peito, ombro e tríceps", "exerciseCount": 2, "estimatedMinutes": 55, "exercises": [{"exerciseId": "supino-reto", "prepSets": 2, "workSets": 2, "repsMin": 6, "repsMax": 10, "workToFailure": true, "startingWeightKg": 40}]}], "sessionDates": [], "exerciseCatalog": [{"id": "supino-reto", "name": "Supino reto", "muscleGroup": "peito", "equipment": "barra"}], "strengthGoal": {"exerciseId": "supino-reto", "exerciseName": "Supino reto", "targetValue": 60, "lastSession": {"date": "2026-09-01", "weightKg": 42.5, "reps": [9, 7], "volumeKg": 680}}, "progress": [{"date": "2026-09-01", "estimatedOneRepMax": 55.25, "volumeKg": 680}], "measurements": [{"id": "m1", "date": "2026-09-01", "weightKg": 78.4, "bodyFatPercent": 18.2, "waistCm": 84, "chestCm": null, "armCm": null, "thighCm": null}], "projection": {"metric": "estimated_1rm", "current": 55.25, "target": 60, "weeklyChange": 1.2, "weeksRemaining": 4, "confidence": "medium"}, "onboardingCompleted": true}
"""#
