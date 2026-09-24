import Foundation
import HenriqueCore
import Observation

/// O que a tela escura mostra depois de parar: quanto contou (nada, se foi
/// curta demais), de qual matéria, quanto o dia soma agora e o que mudou no
/// streak e na meta por causa dela.
public struct FocoResult: Hashable, Sendable {
  public var track: FocoTrack
  public var entries: [FocoEntry]
  public var todaySeconds: TimeInterval
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
  /// Verdadeiro só entre abrir o app com uma corrida gravada e a primeira tela
  /// de foco reabrir o cronômetro. Minimizar depois disso não reabre.
  private var resumePending: Bool
  private let fileURL: URL
  private let estudos: EstudosStore?
  private let calendar = StudyFormat.calendar
  @ObservationIgnored private var syncing = false
  @ObservationIgnored private var syncRequested = false
  @ObservationIgnored private var lastSyncedAt: Date?

  static let batchSize = 500

  public init(fileURL: URL = FocoStore.defaultFileURL, estudos: EstudosStore?) {
    self.fileURL = fileURL
    self.estudos = estudos
    let loaded = Self.load(from: fileURL)
    ledger = loaded
    resumePending = loaded.running != nil
  }

  public func takeResume() -> Bool {
    defer { resumePending = false }
    return resumePending
  }

  public static var defaultFileURL: URL {
    URL.applicationSupportDirectory.appending(path: "foco.json")
  }

  public var isRunning: Bool { ledger.running != nil }

  public func start(_ track: FocoTrack) {
    let now = Date.now
    let previous = ledger.running
    ledger.start(track, at: now, calendar: calendar)
    save()
    if let previous, let id = previous.serverSessionId {
      finishOnServer(id: id, seconds: previous.seconds(at: now))
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
  }

  public func resume() {
    ledger.resume(at: .now)
    save()
  }

  /// Para e deixa o resumo em `result` para a tela escura mostrar.
  public func stop() {
    stop(at: .now)
  }

  private func stop(at end: Date) {
    guard let run = ledger.running else { return }
    let today = CalendarDate(end, in: calendar)
    let before = ledger.streak(now: end, calendar: calendar)
    var withoutRun = ledger
    withoutRun.running = nil
    let goalBefore = withoutRun.seconds(on: today, now: end, calendar: calendar) >= goalSeconds
    let entries = ledger.stop(at: end, calendar: calendar)
    presenceCut = nil
    save()
    let todaySeconds = ledger.seconds(on: today, now: end, calendar: calendar)
    if let id = run.serverSessionId {
      finishOnServer(id: id, seconds: run.seconds(at: end))
    }
    result = FocoResult(
      track: run.track, entries: entries, todaySeconds: todaySeconds,
      streakBefore: before, streakAfter: ledger.streak(now: end, calendar: calendar),
      goalJustReached: todaySeconds >= goalSeconds && !goalBefore)
    isShowingRun = true
    Task { await sync() }
  }

  public func closeResult() {
    result = nil
    isShowingRun = false
  }

  // MARK: Presença

  /// O app voltou para a frente. Uma corrida de mais de 4 h sem resposta vira
  /// a pergunta; senão, este é o novo último momento em que alguém estava ali.
  public func appBecameActive() {
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

  public func remove(_ entry: FocoEntry) {
    undoTask?.cancel()
    ledger.remove(id: entry.id)
    undoable = entry
    save()
    undoTask = Task {
      try? await Task.sleep(for: .seconds(4))
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
