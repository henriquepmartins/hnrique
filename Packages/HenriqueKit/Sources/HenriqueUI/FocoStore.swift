import Foundation
import HenriqueCore
import Observation
import UserNotifications

/// O que a tela escura mostra depois de parar: quanto contou (nada, se foi
/// curta demais), de qual matéria, quanto o dia soma agora e o que mudou no
/// streak e na meta por causa dela.
public struct FocoResult: Hashable, Sendable {
  public var track: FocoTrack
  public var entries: [FocoEntry]
  public var todaySeconds: TimeInterval
  public var startedAt: Date
  public var serverSessionId: String?
  public var streakBefore: FocoStreak
  public var streakAfter: FocoStreak
  public var goalJustReached: Bool

  public var seconds: TimeInterval { entries.reduce(0) { $0 + $1.seconds } }
}

/// O registro local é a verdade e a fila offline. O servidor guarda as sessões
/// e a meta; `sync()` sobe o que está pendente e traz o resto. Uma falha de
/// rede não chega ao usuário: a fila fica para a próxima.
@Observable
@MainActor
public final class FocoStore {
  public private(set) var ledger: FocoLedger
  /// A tela escura fica na raiz para abrir de qualquer app: da lista de
  /// matérias, da faixa acima das abas ou da pergunta de presença.
  public var isShowingRun = false
  public private(set) var result: FocoResult?
  /// Preenchido quando a corrida passou de 4 h sem ninguém confirmar. É a hora
  /// em que o app esteve aberto pela última vez, onde o corte cairia.
  public private(set) var presenceCut: Date?
  /// A corrida que fechou sozinha ao trocar de matéria, para a tela escura
  /// dizer quanto ela contou.
  public private(set) var switched: FocoResult?
  /// A tela do bloco mostra o resumo dela mesma. Aberta, parar não chama a
  /// tela escura, que não teria onde aparecer por cima dela.
  @ObservationIgnored public var isBlockOpen = false
  /// Verdadeiro só entre abrir o app com uma corrida gravada e a primeira tela
  /// de foco reabrir o cronômetro. Minimizar depois disso não reabre.
  private var resumePending: Bool
  private let fileURL: URL
  private let estudos: EstudosStore?
  private let calendar = StudyFormat.calendar
  @ObservationIgnored private var syncing = false
  @ObservationIgnored private var syncRequested = false
  @ObservationIgnored private var lastSyncedAt: Date?
  @ObservationIgnored private var targetTask: Task<Void, Never>?
  @ObservationIgnored private var alarmScheduled = false

  static let batchSize = 500

  public init(fileURL: URL = FocoStore.defaultFileURL, estudos: EstudosStore?) {
    self.fileURL = fileURL
    self.estudos = estudos
    let loaded = Self.load(from: fileURL)
    ledger = loaded
    resumePending = loaded.running != nil
    Self.blockIsRunning = loaded.running?.target != nil
    followTarget()
  }

  /// A casca de estudos pergunta ao montar se reabre a tela do bloco, antes de
  /// ter o store na mão.
  static private(set) var blockIsRunning = false

  public func takeResume() -> Bool {
    defer { resumePending = false }
    return resumePending
  }

  public static var defaultFileURL: URL {
    URL.applicationSupportDirectory.appending(path: "foco.json")
  }

  public var isRunning: Bool { ledger.running != nil }

  /// `target` é o bloco de 15, 25 ou 50 min. Ao chegar nele a corrida para
  /// sozinha, com o app aberto ou não.
  public func start(_ track: FocoTrack, target: TimeInterval? = nil) {
    let now = Date.now
    let previous = ledger.running
    let before = previous.map { _ in summaryContext(at: now) }
    let closed = previous.map { _ in ledger.stop(at: now, calendar: calendar) } ?? []
    ledger.start(track, target: target, at: now, calendar: calendar)
    save()
    followTarget()
    if let previous, let before {
      switched = closed.isEmpty ? nil : summary(of: previous, entries: closed, at: now, before: before)
      if let id = previous.serverSessionId {
        finishOnServer(id: id, seconds: previous.seconds(at: now))
      }
    } else {
      switched = nil
    }
    if target != nil {
      Task { await FocoBlockAlarm.requestPermission() }
    }
    guard track.source == .estudos, let subjectId = track.subjectId, let estudos else { return }
    let startedAt = ledger.running?.startedAt
    Task {
      guard let session = try? await estudos.startSession(subjectId: subjectId) else { return }
      if ledger.running?.track.id == track.id, ledger.running?.startedAt == startedAt {
        ledger.running?.serverSessionId = session.id
        save()
      }
    }
  }

  public func pause() {
    ledger.pause(at: .now)
    save()
    followTarget()
  }

  public func resume() {
    ledger.resume(at: .now)
    save()
    followTarget()
  }

  /// Para e deixa o resumo em `result` para a tela escura mostrar.
  public func stop() {
    stop(at: .now)
  }

  private func stop(at end: Date) {
    guard let run = ledger.running else { return }
    let before = summaryContext(at: end)
    let entries = ledger.stop(at: end, calendar: calendar)
    presenceCut = nil
    switched = nil
    save()
    followTarget()
    if let id = run.serverSessionId {
      finishOnServer(id: id, seconds: run.seconds(at: end))
    }
    result = summary(of: run, entries: entries, at: end, before: before)
    if !isBlockOpen { isShowingRun = true }
    Task { await sync() }
  }

  public func closeResult() {
    result = nil
    isShowingRun = false
  }

  public func clearSwitched() {
    switched = nil
  }

  private struct SummaryContext {
    var streak: FocoStreak
    var goalReached: Bool
  }

  /// O streak e a meta antes da corrida entrar, lidos antes de ela fechar.
  private func summaryContext(at end: Date) -> SummaryContext {
    var withoutRun = ledger
    withoutRun.running = nil
    let today = CalendarDate(end, in: calendar)
    return SummaryContext(
      streak: ledger.streak(now: end, calendar: calendar),
      goalReached: withoutRun.seconds(on: today, now: end, calendar: calendar) >= goalSeconds)
  }

  private func summary(
    of run: FocoRun, entries: [FocoEntry], at end: Date, before: SummaryContext
  ) -> FocoResult {
    let todaySeconds = ledger.seconds(on: CalendarDate(end, in: calendar), now: end, calendar: calendar)
    return FocoResult(
      track: run.track, entries: entries, todaySeconds: todaySeconds, startedAt: run.startedAt,
      serverSessionId: run.serverSessionId, streakBefore: before.streak,
      streakAfter: ledger.streak(now: end, calendar: calendar),
      goalJustReached: todaySeconds >= goalSeconds && !before.goalReached)
  }

  // MARK: Bloco

  /// Para o bloco que já chegou ao alvo, no instante em que chegou, e senão
  /// agenda a parada e o aviso para esse instante.
  private func followTarget() {
    targetTask?.cancel()
    updateAlarm()
    guard let end = ledger.running?.targetReachedAt else { return }
    guard end > .now else {
      stop(at: end)
      return
    }
    targetTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow))
      guard !Task.isCancelled else { return }
      self?.followTarget()
    }
  }

  private func updateAlarm() {
    let run = ledger.running
    if let end = run?.targetReachedAt, let run, end > .now {
      FocoBlockAlarm.schedule(at: end, run: run)
      alarmScheduled = true
    } else if alarmScheduled {
      FocoBlockAlarm.cancel()
      alarmScheduled = false
    }
  }

  // MARK: Presença

  /// O app voltou para a frente. Uma corrida de mais de 4 h sem resposta vira
  /// a pergunta; senão, este é o novo último momento em que alguém estava ali.
  public func appBecameActive() {
    followTarget()
    let now = Date.now
    guard let run = ledger.running else { return }
    if run.needsPresenceCheck(at: now) {
      presenceCut = run.lastPresence(fallback: now)
    } else {
      ledger.markSeen(at: now)
      save()
    }
  }

  public func appWentBackground() {
    guard presenceCut == nil else { return }
    ledger.markSeen(at: .now)
    save()
  }

  public func confirmPresence() {
    ledger.confirmPresence(at: .now)
    presenceCut = nil
    save()
  }

  public func stopAtLastPresence() {
    stop(at: presenceCut ?? .now)
  }

  /// A sessão apagada some na hora e o servidor só fica sabendo depois de 4 s,
  /// o tempo do aviso com "desfazer".
  public private(set) var undoable: FocoEntry?
  @ObservationIgnored private var undoTask: Task<Void, Never>?

  /// Com VoiceOver o aviso precisa durar o bastante para ser lido e alcançado.
  public func remove(_ entry: FocoEntry, holdFor hold: Duration = .seconds(4)) {
    undoTask?.cancel()
    ledger.remove(id: entry.id)
    undoable = entry
    save()
    undoTask = Task {
      try? await Task.sleep(for: hold)
      guard !Task.isCancelled else { return }
      undoable = nil
      await sync()
    }
  }

  public func undoRemove() {
    guard let entry = undoable else { return }
    undoTask?.cancel()
    undoable = nil
    ledger.restore(entry)
    save()
  }

  public func setGoal(minutes: Int) {
    ledger.setGoal(minutes: minutes)
    save()
    Task { await sync() }
  }

  // MARK: Sincronização

  /// O que as telas chamam ao aparecer. O cartão de hoje e a tela de foco
  /// aparecem a cada troca de aba, e cada sync baixava a lista inteira.
  public func syncIfStale() async {
    if let lastSyncedAt, Date.now.timeIntervalSince(lastSyncedAt) < 60 { return }
    await sync()
  }

  /// Sobe a fila e depois adota a lista do servidor. Um sync por vez. O pedido
  /// que chega com outro rodando marca uma segunda volta, porque a sessão
  /// parada agora pode ter entrado na fila depois que o primeiro já leu dela.
  public func sync() async {
    guard estudos?.client != nil else { return }
    guard !syncing else {
      syncRequested = true
      return
    }
    syncing = true
    defer { syncing = false }
    repeat {
      syncRequested = false
      await syncOnce()
    } while syncRequested
  }

  private func syncOnce() async {
    guard let client = estudos?.client else { return }
    do {
      try await pushUploads(client)
      try await pushRemovals(client)
      if ledger.goalDirty {
        _ = try await client.focoSetGoal(minutes: ledger.dailyGoalMinutes)
        ledger.markGoalSynced()
        save()
      }
      let list = try await client.focoList()
      ledger.merge(server: list.entries, serverGoal: list.dailyGoalMinutes)
      save()
      lastSyncedAt = .now
    } catch {
      // Sem rede ou sessão caída a fila fica como está. O 401 já derrubou o
      // token no cliente, e a próxima tela que falar com o servidor desloga.
    }
  }

  private func pushUploads(_ client: APIClient) async throws {
    while !ledger.pendingUploads.isEmpty {
      let batch = ledger.entries
        .filter { ledger.pendingUploads.contains($0.id) }
        .prefix(Self.batchSize)
      guard !batch.isEmpty else { return }
      // `saved` volta sem o id que já pertence a outro usuário. Insistir nele
      // não muda nada, então o lote inteiro sai da fila.
      _ = try await client.focoSave(Array(batch))
      ledger.markUploaded(batch.map(\.id))
      save()
    }
  }

  private func pushRemovals(_ client: APIClient) async throws {
    while true {
      let waiting = ledger.pendingRemovals.subtracting([undoable?.id].compactMap { $0 })
      guard !waiting.isEmpty else { return }
      let batch = Array(waiting.prefix(Self.batchSize))
      _ = try await client.focoRemove(ids: batch)
      ledger.markRemoved(batch)
      save()
    }
  }

  private var goalSeconds: TimeInterval { Double(ledger.dailyGoalMinutes) * 60 }

  private func finishOnServer(id: String, seconds: TimeInterval) {
    guard let estudos else { return }
    Task { _ = try? await estudos.finishSession(id: id, minutes: max(1, Int(seconds / 60))) }
  }

  private static func load(from url: URL) -> FocoLedger {
    guard let data = try? Data(contentsOf: url),
      let ledger = try? decoder.decode(FocoLedger.self, from: data)
    else { return FocoLedger() }
    return ledger
  }

  private func save() {
    Self.blockIsRunning = ledger.running?.target != nil
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Self.encoder.encode(ledger).write(to: fileURL, options: .atomic)
    } catch {
      // Sem disco o registro segue em memória até o app fechar. Não há o que
      // dizer ao usuário que ele possa resolver.
    }
  }

  /// O JSON no disco usa o mesmo codificador do cliente HTTP. O antigo gravava
  /// sem fração de segundo, e o `henrique()` lê os dois formatos.
  private static let encoder = JSONEncoder.henrique()
  private static let decoder = JSONDecoder.henrique()
}

/// O aviso de fim do bloco com o app fechado. O prefixo "estudos." separa estes
/// avisos dos da academia, que usam a mesma central. O mesmo identificador
/// substitui o aviso anterior, então agendar de novo não duplica.
private enum FocoBlockAlarm {
  static let identifier = "estudos.bloco"

  static func requestPermission() async {
    _ = try? await UNUserNotificationCenter.current()
      .requestAuthorization(options: [.alert, .sound])
  }

  static func schedule(at end: Date, run: FocoRun) {
    let content = UNMutableNotificationContent()
    content.title = "bloco de \(Int((run.target ?? 0) / 60)) min concluído"
    content.body = "\(run.track.name) já contou no dia."
    content.sound = .default
    let trigger = UNTimeIntervalNotificationTrigger(
      timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
    UNUserNotificationCenter.current()
      .add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
  }

  static func cancel() {
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
  }
}
