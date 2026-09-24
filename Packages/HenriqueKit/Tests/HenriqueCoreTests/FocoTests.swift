import Foundation
import Testing

@testable import HenriqueCore

/// Fuso fixo em Fortaleza, o mesmo de `StudyFormat.calendar`, para a meia-noite
/// dos testes não depender do aparelho que os roda.
@Suite("O registro de foco")
struct FocoTests {
  static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Fortaleza")!
    return calendar
  }()

  static let fisica = FocoTrack.subject(id: "fis", name: "física", color: "#0075de")

  /// "2026-09-08 14:05" no fuso de Fortaleza.
  static func at(_ day: String, _ time: String) -> Date {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.date(from: "\(day) \(time)")!
  }

  static func day(_ iso: String) -> CalendarDate { CalendarDate(iso: iso)! }

  static func entry(_ track: FocoTrack, _ day: String, _ from: String, _ to: String) -> FocoEntry {
    FocoEntry(track: track, startedAt: at(day, from), endedAt: at(day, to))
  }

  /// Um dia inteiro que conta para o streak: 30 min de física.
  static func counted(_ day: String) -> FocoEntry {
    entry(fisica, day, "09:00", "09:30")
  }

  @Test("o total do dia soma duas sessões e a corrida em andamento")
  func todayTotalIncludesTheRun() {
    var ledger = FocoLedger(entries: [
      Self.entry(Self.fisica, "2026-09-08", "14:05", "14:52"),
      Self.entry(.alemao, "2026-09-08", "16:00", "16:10"),
    ])
    ledger.start(Self.fisica, at: Self.at("2026-09-08", "20:00"), calendar: Self.calendar)
    let now = Self.at("2026-09-08", "20:03")
    #expect(
      ledger.seconds(on: Self.day("2026-09-08"), now: now, calendar: Self.calendar)
        == (47 + 10 + 3) * 60)
    #expect(
      ledger.seconds(
        on: Self.day("2026-09-08"), track: Self.fisica.id, now: now, calendar: Self.calendar)
        == (47 + 3) * 60)
  }

  @Test("sessão com menos de 10 segundos não grava")
  func shortSessionIsDropped() {
    var ledger = FocoLedger()
    ledger.start(.alemao, at: Self.at("2026-09-08", "10:00"), calendar: Self.calendar)
    let entries = ledger.stop(
      at: Self.at("2026-09-08", "10:00").addingTimeInterval(9), calendar: Self.calendar)
    #expect(entries.isEmpty)
    #expect(ledger.entries.isEmpty)
    #expect(ledger.running == nil)
  }

  @Test("começar outra trilha fecha a que rodava")
  func startClosesThePreviousRun() {
    var ledger = FocoLedger()
    ledger.start(.alemao, at: Self.at("2026-09-08", "10:00"), calendar: Self.calendar)
    ledger.start(Self.fisica, at: Self.at("2026-09-08", "10:20"), calendar: Self.calendar)
    #expect(ledger.entries.map(\.track.id) == [FocoTrack.alemao.id])
    #expect(ledger.entries.first?.seconds == 1200.0)
    #expect(ledger.running?.track == Self.fisica)
  }

  @Test("streak de 3 com hoje feito")
  func streakEndingToday() {
    let ledger = FocoLedger(entries: ["2026-09-06", "2026-09-07", "2026-09-08"].map(Self.counted))
    let streak = ledger.streak(now: Self.at("2026-09-08", "18:00"), calendar: Self.calendar)
    #expect(streak == FocoStreak(current: 3, best: 3, isTodayDone: true))
  }

  @Test("hoje em aberto não quebra o streak, que termina ontem")
  func streakEndingYesterdayWhileTodayIsOpen() {
    let ledger = FocoLedger(entries: ["2026-09-05", "2026-09-06", "2026-09-07"].map(Self.counted))
    let streak = ledger.streak(now: Self.at("2026-09-08", "18:00"), calendar: Self.calendar)
    #expect(streak == FocoStreak(current: 3, best: 3, isTodayDone: false))
  }

  @Test("buraco ontem zera o streak e o recorde fica")
  func gapYesterdayResetsTheStreak() {
    let ledger = FocoLedger(entries: ["2026-09-04", "2026-09-05", "2026-09-06"].map(Self.counted))
    let streak = ledger.streak(now: Self.at("2026-09-08", "18:00"), calendar: Self.calendar)
    #expect(streak == FocoStreak(current: 0, best: 3, isTodayDone: false))
  }

  @Test("o recorde é a maior sequência do registro inteiro")
  func bestIsTheLongestRun() {
    let ledger = FocoLedger(
      entries: ["2026-08-01", "2026-08-02", "2026-08-03", "2026-08-04", "2026-09-08"].map(
        Self.counted))
    let streak = ledger.streak(now: Self.at("2026-09-08", "18:00"), calendar: Self.calendar)
    #expect(streak == FocoStreak(current: 1, best: 4, isTodayDone: true))
  }

  @Test("sessão das 23:30 às 00:30 conta para o dia em que começou")
  func sessionAcrossMidnightBelongsToItsStartDay() {
    let ledger = FocoLedger(entries: [
      FocoEntry(
        track: Self.fisica, startedAt: Self.at("2026-09-07", "23:30"),
        endedAt: Self.at("2026-09-08", "00:30"))
    ])
    let now = Self.at("2026-09-08", "08:00")
    #expect(ledger.seconds(on: Self.day("2026-09-07"), now: now, calendar: Self.calendar) == 3600)
    #expect(ledger.seconds(on: Self.day("2026-09-08"), now: now, calendar: Self.calendar) == 0)
  }

  @Test("os níveis da grade vão de 0 a 4 contra a meta de 120 min")
  func gridLevelsAgainstTheGoal() {
    let ledger = FocoLedger(
      entries: [
        Self.entry(Self.fisica, "2026-09-04", "09:00", "09:20"),
        Self.entry(Self.fisica, "2026-09-05", "09:00", "09:40"),
        Self.entry(Self.fisica, "2026-09-06", "09:00", "10:30"),
        Self.entry(Self.fisica, "2026-09-07", "09:00", "11:00"),
      ], dailyGoalMinutes: 120)
    let days = ledger.days(
      endingOn: Self.day("2026-09-07"), count: 5, now: Self.at("2026-09-08", "08:00"),
      calendar: Self.calendar)
    #expect(days.map(\.date.iso) == [
      "2026-09-03", "2026-09-04", "2026-09-05", "2026-09-06", "2026-09-07",
    ])
    #expect(days.map(\.level) == [0, 1, 2, 3, 4])
  }

  @Test("o registro faz ida e volta em JSON com a corrida")
  func ledgerRoundTripsThroughJSON() throws {
    var ledger = FocoLedger(entries: [Self.counted("2026-09-07")], dailyGoalMinutes: 180)
    ledger.start(Self.fisica, at: Self.at("2026-09-08", "10:00"), calendar: Self.calendar)
    ledger.running?.serverSessionId = "srv-1"
    let data = try JSONEncoder().encode(ledger)
    let decoded = try JSONDecoder().decode(FocoLedger.self, from: data)
    #expect(decoded == ledger)
    #expect(decoded.running?.serverSessionId == "srv-1")
  }

  // MARK: Fila de sincronização

  @Test("JSON gravado antes da fila decodifica com todo o histórico pendente")
  func legacyJSONMarksEverythingPending() throws {
    let old = Self.counted("2026-09-07")
    let json = """
      {"entries":[{"id":"\(old.id.uuidString)","track":{"id":"estudos:fis","name":"física","color":"#0075de","source":"estudos","subjectId":"fis"},"startedAt":"2026-09-07T12:00:00Z","endedAt":"2026-09-07T12:30:00Z"}],"dailyGoalMinutes":90}
      """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let ledger = try decoder.decode(FocoLedger.self, from: Data(json.utf8))
    #expect(ledger.entries.map(\.id) == [old.id])
    #expect(ledger.pendingUploads == [old.id])
    #expect(ledger.pendingRemovals == [])
    #expect(ledger.goalDirty == false)
    #expect(ledger.dailyGoalMinutes == 90)
  }

  @Test("parar enfileira a sessão gravada; a curta demais não")
  func stopQueuesTheEntry() {
    var ledger = FocoLedger()
    ledger.start(.alemao, at: Self.at("2026-09-08", "10:00"), calendar: Self.calendar)
    let entry = ledger.stop(at: Self.at("2026-09-08", "10:20"), calendar: Self.calendar)[0]
    #expect(ledger.pendingUploads == [entry.id])
    ledger.start(.alemao, at: Self.at("2026-09-08", "11:00"), calendar: Self.calendar)
    ledger.stop(at: Self.at("2026-09-08", "11:00").addingTimeInterval(5), calendar: Self.calendar)
    #expect(ledger.pendingUploads == [entry.id])
  }

  @Test("começar outra trilha enfileira a que fechou")
  func startQueuesTheClosedRun() {
    var ledger = FocoLedger()
    ledger.start(.alemao, at: Self.at("2026-09-08", "10:00"), calendar: Self.calendar)
    ledger.start(Self.fisica, at: Self.at("2026-09-08", "10:20"), calendar: Self.calendar)
    #expect(ledger.pendingUploads == [ledger.entries[0].id])
  }

  @Test("apagar uma pendente só tira da fila de subida")
  func removingPendingDoesNotQueueRemoval() {
    let entry = Self.counted("2026-09-07")
    var ledger = FocoLedger(entries: [entry], pendingUploads: [entry.id])
    ledger.remove(id: entry.id)
    #expect(ledger.entries == [])
    #expect(ledger.pendingUploads == [])
    #expect(ledger.pendingRemovals == [])
  }

  @Test("apagar uma sincronizada enfileira a remoção")
  func removingSyncedQueuesRemoval() {
    let entry = Self.counted("2026-09-07")
    var ledger = FocoLedger(entries: [entry])
    ledger.remove(id: entry.id)
    #expect(ledger.entries == [])
    #expect(ledger.pendingRemovals == [entry.id])
  }

  @Test("merge traz a nova do servidor, mantém a pendente, esconde a removida e não duplica")
  func mergeCombinesServerAndQueue() {
    let synced = Self.entry(Self.fisica, "2026-09-05", "09:00", "09:30")
    let removed = Self.entry(Self.fisica, "2026-09-06", "09:00", "09:30")
    let pending = Self.entry(.alemao, "2026-09-08", "09:00", "09:30")
    let fromServer = Self.entry(Self.fisica, "2026-09-07", "09:00", "09:30")
    var ledger = FocoLedger(
      entries: [synced, pending], pendingUploads: [pending.id], pendingRemovals: [removed.id])
    ledger.start(.alemao, at: Self.at("2026-09-08", "12:00"), calendar: Self.calendar)
    let run = ledger.running
    ledger.merge(server: [fromServer, removed, synced], serverGoal: nil)
    #expect(ledger.entries.map(\.id) == [synced.id, fromServer.id, pending.id])
    #expect(ledger.pendingUploads == [pending.id])
    #expect(ledger.pendingRemovals == [removed.id])
    #expect(ledger.running == run)
  }

  @Test("meta suja vence o servidor; limpa adota a do servidor; sem meta lá fica a local")
  func mergeGoal() {
    var dirty = FocoLedger(dailyGoalMinutes: 180)
    dirty.setGoal(minutes: 60)
    dirty.merge(server: [], serverGoal: 240)
    #expect(dirty.dailyGoalMinutes == 60)
    #expect(dirty.goalDirty)

    var clean = FocoLedger(dailyGoalMinutes: 180)
    clean.merge(server: [], serverGoal: 240)
    #expect(clean.dailyGoalMinutes == 240)

    var alone = FocoLedger(dailyGoalMinutes: 180)
    alone.merge(server: [], serverGoal: nil)
    #expect(alone.dailyGoalMinutes == 180)
  }

  @Test("marcar subida, remoção e meta esvazia a fila")
  func marksDrainTheQueue() {
    let a = Self.counted("2026-09-06")
    let b = Self.counted("2026-09-07")
    var ledger = FocoLedger(
      entries: [a], pendingUploads: [a.id], pendingRemovals: [b.id], goalDirty: true)
    ledger.markUploaded([a.id])
    ledger.markRemoved([b.id])
    ledger.markGoalSynced()
    #expect(ledger.pendingUploads == [])
    #expect(ledger.pendingRemovals == [])
    #expect(ledger.goalDirty == false)
  }

  @Test("o contrato HTTP faz ida e volta pelo codificador do app")
  func entryRoundTripsThroughTheAppCoders() throws {
    let entry = Self.entry(.alemao, "2026-09-08", "10:00", "10:47")
    let data = try JSONEncoder.henrique().encode(FocoSaveInput(entries: [entry]))
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let sent = try #require((json["entries"] as? [[String: Any]])?.first)
    #expect(sent["startedAt"] as? String == "2026-09-08T13:00:00.000Z")
    #expect((sent["track"] as? [String: Any])?["subjectId"] == nil)
    let back = """
      {"entries":[{"id":"\(entry.id.uuidString.lowercased())","track":{"id":"idiomas:alemao","name":"alemão","color":"#0b6e4f","source":"idiomas","subjectId":null},"startedAt":"2026-09-08T13:00:00.000Z","endedAt":"2026-09-08T13:47:00Z"}],"dailyGoalMinutes":null}
      """
    let list = try JSONDecoder.henrique().decode(FocoListResponse.self, from: Data(back.utf8))
    #expect(list.entries == [entry])
    #expect(list.dailyGoalMinutes == nil)
  }
  // MARK: Pausa, meia-noite e presença

  @Test("a pausa não conta e cada trecho vira uma sessão com a hora real")
  func pauseSplitsTheRun() {
    var ledger = FocoLedger()
    ledger.start(Self.fisica, at: Self.at("2026-09-08", "10:00"), calendar: Self.calendar)
    ledger.pause(at: Self.at("2026-09-08", "10:25"))
    #expect(ledger.running?.seconds(at: Self.at("2026-09-08", "11:00")) == TimeInterval(25 * 60))
    ledger.resume(at: Self.at("2026-09-08", "11:00"))
    #expect(ledger.running?.seconds(at: Self.at("2026-09-08", "11:10")) == TimeInterval(35 * 60))
    #expect(
      ledger.seconds(
        on: Self.day("2026-09-08"), now: Self.at("2026-09-08", "11:10"), calendar: Self.calendar)
        == 35 * 60)
    let entries = ledger.stop(at: Self.at("2026-09-08", "11:20"), calendar: Self.calendar)
    #expect(entries.map(\.seconds) == [25 * 60, 20 * 60])
    #expect(entries.map(\.startedAt) == [Self.at("2026-09-08", "10:00"), Self.at("2026-09-08", "11:00")])
    #expect(ledger.pendingUploads == Set(entries.map(\.id)))
  }

  @Test("trecho de menos de um minuto entra no vizinho do mesmo dia")
  func shortStretchJoinsNeighbor() {
    var ledger = FocoLedger()
    ledger.start(Self.fisica, at: Self.at("2026-09-08", "10:00"), calendar: Self.calendar)
    ledger.pause(at: Self.at("2026-09-08", "10:25"))
    ledger.resume(at: Self.at("2026-09-08", "10:40"))
    var entries = ledger.stop(at: Self.at("2026-09-08", "10:40") + 45, calendar: Self.calendar)
    #expect(entries.map(\.startedAt) == [Self.at("2026-09-08", "10:00")])
    #expect(entries.map(\.endedAt) == [Self.at("2026-09-08", "10:25") + 45])
    #expect(ledger.entries.count == 1)

    ledger.start(Self.fisica, at: Self.at("2026-09-08", "14:00"), calendar: Self.calendar)
    ledger.pause(at: Self.at("2026-09-08", "14:00") + 30)
    ledger.resume(at: Self.at("2026-09-08", "14:10"))
    entries = ledger.stop(at: Self.at("2026-09-08", "14:30"), calendar: Self.calendar)
    #expect(entries.map(\.startedAt) == [Self.at("2026-09-08", "14:10") - 30])
    #expect(entries.map(\.seconds) == [1230])
  }

  @Test("sobra curta antes da meia-noite some; corrida toda curta vira uma sessão")
  func shortPiecesAtMidnightAndShortRuns() {
    var ledger = FocoLedger()
    ledger.start(Self.fisica, at: Self.at("2026-09-08", "00:00") - 30, calendar: Self.calendar)
    var entries = ledger.stop(at: Self.at("2026-09-08", "00:20"), calendar: Self.calendar)
    #expect(entries.map(\.startedAt) == [Self.at("2026-09-08", "00:00")])
    #expect(entries.map(\.seconds) == [1200])

    ledger.start(.alemao, at: Self.at("2026-09-08", "09:00"), calendar: Self.calendar)
    ledger.pause(at: Self.at("2026-09-08", "09:00") + 20)
    ledger.resume(at: Self.at("2026-09-08", "09:05"))
    entries = ledger.stop(at: Self.at("2026-09-08", "09:05") + 25, calendar: Self.calendar)
    #expect(entries.map(\.startedAt) == [Self.at("2026-09-08", "09:00")])
    #expect(entries.map(\.seconds) == [45])
  }

  @Test("pausar duas vezes não cria trecho vazio")
  func pauseIsIdempotent() {
    var ledger = FocoLedger()
    ledger.start(.alemao, at: Self.at("2026-09-08", "10:00"), calendar: Self.calendar)
    ledger.pause(at: Self.at("2026-09-08", "10:10"))
    ledger.pause(at: Self.at("2026-09-08", "10:30"))
    #expect(ledger.running?.stretches.count == 1)
    #expect(ledger.running?.seconds(at: Self.at("2026-09-08", "12:00")) == TimeInterval(600))
  }

  @Test("a corrida das 23:30 à 00:30 grava meia hora em cada dia")
  func runAcrossMidnightSplits() {
    var ledger = FocoLedger()
    ledger.start(Self.fisica, at: Self.at("2026-09-07", "23:30"), calendar: Self.calendar)
    let now = Self.at("2026-09-08", "00:30")
    #expect(ledger.seconds(on: Self.day("2026-09-07"), now: now, calendar: Self.calendar) == 1800)
    #expect(ledger.seconds(on: Self.day("2026-09-08"), now: now, calendar: Self.calendar) == 1800)
    let entries = ledger.stop(at: now, calendar: Self.calendar)
    #expect(entries.map(\.startedAt) == [Self.at("2026-09-07", "23:30"), Self.at("2026-09-08", "00:00")])
    #expect(entries.map(\.endedAt) == [Self.at("2026-09-08", "00:00"), now])
  }

  @Test("mais de 4 h sem resposta pergunta e corta no último uso do app")
  func presenceCheckCutsAtLastSeen() throws {
    var ledger = FocoLedger()
    ledger.start(Self.fisica, at: Self.at("2026-09-08", "09:00"), calendar: Self.calendar)
    ledger.markSeen(at: Self.at("2026-09-08", "09:40"))
    let later = Self.at("2026-09-08", "13:05")
    let run = try #require(ledger.running)
    #expect(run.needsPresenceCheck(at: Self.at("2026-09-08", "12:59")) == false)
    #expect(run.needsPresenceCheck(at: later))
    let cut = run.lastPresence(fallback: later)
    #expect(cut == Self.at("2026-09-08", "09:40"))
    let entries = ledger.stop(at: cut, calendar: Self.calendar)
    #expect(entries.map(\.seconds) == [40 * 60])
  }

  @Test("responder que está ali adia a próxima pergunta por mais 4 h")
  func confirmingPresencePostponesTheCheck() throws {
    var ledger = FocoLedger()
    ledger.start(Self.fisica, at: Self.at("2026-09-08", "09:00"), calendar: Self.calendar)
    ledger.confirmPresence(at: Self.at("2026-09-08", "13:30"))
    let run = try #require(ledger.running)
    #expect(run.needsPresenceCheck(at: Self.at("2026-09-08", "17:00")) == false)
    #expect(run.needsPresenceCheck(at: Self.at("2026-09-08", "17:31")))
    #expect(run.lastPresence(fallback: Self.at("2026-09-08", "18:00")) == Self.at("2026-09-08", "13:30"))
  }

  @Test("pausada não pergunta, porque não está contando")
  func pausedRunSkipsTheCheck() {
    var ledger = FocoLedger()
    ledger.start(Self.fisica, at: Self.at("2026-09-08", "09:00"), calendar: Self.calendar)
    ledger.pause(at: Self.at("2026-09-08", "09:30"))
    #expect(ledger.running?.needsPresenceCheck(at: Self.at("2026-09-08", "20:00")) == false)
  }

  @Test("a corrida gravada antes da pausa volta rodando desde o começo")
  func legacyRunDecodesAsRunning() throws {
    let json = """
      {"entries":[],"pendingUploads":[],"running":{"track":{"id":"idiomas:alemao","name":"alemão","color":"#0b6e4f","source":"idiomas"},"startedAt":"2026-09-08T13:00:00Z","serverSessionId":"srv-9"}}
      """
    let ledger = try JSONDecoder.henrique().decode(FocoLedger.self, from: Data(json.utf8))
    let run = try #require(ledger.running)
    #expect(run.isPaused == false)
    #expect(run.serverSessionId == "srv-9")
    #expect(run.seconds(at: Self.at("2026-09-08", "10:30")) == 1800)
  }

  @Test("desfazer devolve a sessão e tira a remoção da fila")
  func restoreUndoesRemove() {
    let synced = Self.counted("2026-09-07")
    let pending = Self.counted("2026-09-08")
    var ledger = FocoLedger(entries: [synced, pending], pendingUploads: [pending.id])
    ledger.remove(id: synced.id)
    ledger.remove(id: pending.id)
    #expect(ledger.pendingRemovals == [synced.id])
    ledger.restore(synced)
    ledger.restore(pending)
    ledger.restore(pending)
    #expect(ledger.entries.map(\.id) == [synced.id, pending.id])
    #expect(ledger.pendingRemovals == [])
    #expect(ledger.pendingUploads == [pending.id])
  }
}
