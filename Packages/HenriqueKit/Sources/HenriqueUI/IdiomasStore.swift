import Foundation
import HenriqueCore
import Observation

/// O estado de uma aba de idiomas. Igual ao das outras áreas: a tela lê os
/// casos direto, sem booleano paralelo.
@MainActor
@Observable
public final class IdiomasStore {
  public private(set) var routine: Loadable<LanguageRoutine> = .idle
  public private(set) var queue: Loadable<LanguageReviewQueue> = .idle
  public private(set) var progress: Loadable<LanguageProgressPayload> = .idle
  public private(set) var completedDrillIds: Set<String> = []
  public private(set) var pendingCorrectionIds: Set<String> = []
  public private(set) var conflictDrillIds: Set<String> = []
  public var banner: String?

  /// O RootView liga isto ao `signOut()` da Academia. Mesma sessão, mesma regra:
  /// quem descobre que ela caiu avisa o outro.
  public var onUnauthorized: (@MainActor () async -> Void)?

  private let client: APIClient
  @ObservationIgnored private var finishedDrillIds: [String] = []
  @ObservationIgnored private var pendingCorrections: [String: LanguageCorrectionInput] = [:]
  @ObservationIgnored private var serialTail: Task<Bool, Never>?
  @ObservationIgnored private var tailsByAttempt: [UUID: Task<Bool, Never>] = [:]

  /// Muda a cada `reset()`. O resultado de uma chamada que saiu antes da sessão
  /// cair não pode voltar ao estado depois.
  @ObservationIgnored private var sessionID = UUID()

  public init(client: APIClient) {
    self.client = client
  }

  #if DEBUG
    /// Companheiro dos outros `openCaptureShell()`. Segura as abas no lugar
    /// para `--casca` capturar a casca sem servidor.
    @ObservationIgnored private var isCaptureShell = false

    public func openCaptureShell() { isCaptureShell = true }
  #endif

  // MARK: Leituras

  public func loadRoutine(force: Bool = false) async {
    if routine.isLoading { return }
    if routine.value != nil, !force { return }
    await loadBundles(force: force)
  }

  public func loadQueue(force: Bool = false) async {
    if queue.isLoading { return }
    if queue.value != nil, !force { return }
    await loadBundles(force: force)
  }

  public func loadProgress(force: Bool = false) async {
    if progress.isLoading { return }
    if progress.value != nil, !force { return }
    await loadBundles(force: force)
  }

  public func prefetchAll() async {
    await loadBundles(force: false)
  }

  public func refresh() async {
    await loadBundles(force: true)
  }

  /// O servidor ainda não tem rota de fila nem de progresso para idiomas, então
  /// `routine/get` devolve o pacote com os três recortes. Cada aba guarda o seu
  /// e o refresh explícito de uma preenche as outras de carona, sem apagar erro
  /// alheio no sucesso.
  private func loadBundles(force: Bool) async {
    #if DEBUG
      if isCaptureShell { return }
    #endif
    if !force, routine.value != nil, queue.value != nil, progress.value != nil {
      return
    }
    if routine.isLoading || queue.isLoading || progress.isLoading { return }
    if routine.value == nil { routine = .loading }
    if queue.value == nil { queue = .loading }
    if progress.value == nil { progress = .loading }
    let generation = sessionID
    do {
      let bundle = try await client.idiomasRoutine()
      guard generation == sessionID else { return }
      routine = .ready(bundle.routine)
      queue = .ready(bundle.queue)
      progress = .ready(bundle.progress)
      // A correção que caiu volta em silêncio no próximo pacote, sem banner e
      // sem pedir nada de quem está treinando.
      backfillSilently()
    } catch {
      guard generation == sessionID else { return }
      guard !(error is CancellationError) else {
        restoreIdleLanes()
        return
      }
      await handle(error)
      if case APIError.unauthorized = error { return }
      let message = Self.message(for: error)
      if routine.value == nil { routine = .failed(message) }
      if queue.value == nil { queue = .failed(message) }
      if progress.value == nil { progress = .failed(message) }
    }
  }

  private func restoreIdleLanes() {
    if case .loading = routine { routine = .idle }
    if case .loading = queue { queue = .idle }
    if case .loading = progress { progress = .idle }
  }

  // MARK: Mutações

  /// Marca o treino como feito na hora e desfaz só ele se o servidor recusar.
  /// A mesma `attemptId` em voo devolve a mesma espera, então o toque duplo não
  /// grava duas vezes. Sem repetição do lado do aparelho: falhou, quem tenta de
  /// novo é quem está treinando, no botão da tela.
  @discardableResult
  public func complete(
    drill: LanguageDrill, text: String, micUsed: Bool, rating: FlashcardRating? = nil,
    attemptId: UUID = UUID()
  ) async -> Bool {
    if let running = tailsByAttempt[attemptId] { return await running.value }
    completedDrillIds.insert(drill.id)
    conflictDrillIds.remove(drill.id)
    let previous = serialTail
    let generation = sessionID
    let task = Task { @MainActor in
      _ = await previous?.value
      guard self.sessionID == generation, !Task.isCancelled else { return false }
      do {
        _ = try await self.client.completeLanguageDrill(
          LanguageCompleteInput(
            attemptId: attemptId, drillId: drill.id, text: text, micUsed: micUsed, rating: rating))
        guard self.sessionID == generation, !Task.isCancelled else { return false }
        self.finishedDrillIds.append(drill.id)
        self.banner = nil
        return true
      } catch {
        guard self.sessionID == generation, !Task.isCancelled else { return false }
        if case APIError.http(status: 409, _) = error {
          // O treino mudou em outro lugar: o aviso entra na linha e a sessão
          // fica nele, sem avançar.
          self.completedDrillIds.remove(drill.id)
          self.conflictDrillIds.insert(drill.id)
          return false
        }
        self.completedDrillIds.remove(drill.id)
        if !(error is CancellationError) { await self.handle(error) }
        return false
      }
    }
    serialTail = task
    tailsByAttempt[attemptId] = task
    let saved = await task.value
    tailsByAttempt.removeValue(forKey: attemptId)
    return saved
  }

  /// A nota da revisão sai da fila na hora e volta se o servidor recusar. O
  /// intervalo que volta alimenta a dica do botão, como nos estudos.
  @discardableResult
  public func gradeReview(drill: LanguageDrill, rating: FlashcardRating, attemptId: UUID = UUID())
    async -> LanguageCompleteResult?
  {
    guard var pending = queue.value else { return nil }
    guard pending.drills.contains(where: { $0.id == drill.id }) else { return nil }
    pending.drills.removeAll { $0.id == drill.id }
    queue = .ready(pending)
    conflictDrillIds.remove(drill.id)
    do {
      let result = try await client.completeLanguageDrill(
        LanguageCompleteInput(
          attemptId: attemptId, drillId: drill.id, text: "", micUsed: false, rating: rating))
      banner = nil
      return result
    } catch {
      if case APIError.http(status: 409, _) = error {
        conflictDrillIds.insert(drill.id)
      } else {
        if var back = queue.value {
          back.drills.insert(drill, at: 0)
          queue = .ready(back)
        }
        if !(error is CancellationError) { await handle(error) }
      }
      return nil
    }
  }

  /// A correção da IA. Transporte ou 5xx marca o treino como pendente e devolve
  /// nulo para a tela avançar com a autoavaliação local; o dia continua valendo
  /// e a correção real entra em silêncio depois.
  public func gradeCorrection(drill: LanguageDrill, text: String, attemptId: UUID? = nil)
    async -> LanguageCorrection?
  {
    let generation = sessionID
    do {
      let correction = try await client.gradeLanguageCorrection(
        LanguageCorrectionInput(attemptId: attemptId, drillId: drill.id, text: text))
      guard generation == sessionID else { return nil }
      pendingCorrectionIds.remove(drill.id)
      pendingCorrections.removeValue(forKey: drill.id)
      banner = nil
      return correction
    } catch {
      guard generation == sessionID, !(error is CancellationError) else { return nil }
      switch error {
      case APIError.unauthorized:
        await handle(error)
        return nil
      case APIError.http(status: 409, _):
        conflictDrillIds.insert(drill.id)
        return nil
      case APIError.transport:
        pendingCorrectionIds.insert(drill.id)
        pendingCorrections[drill.id] = LanguageCorrectionInput(
          attemptId: attemptId, drillId: drill.id, text: text)
        return nil
      case APIError.http(let status, _) where status >= 500:
        pendingCorrectionIds.insert(drill.id)
        pendingCorrections[drill.id] = LanguageCorrectionInput(
          attemptId: attemptId, drillId: drill.id, text: text)
        return nil
      default:
        await handle(error)
        return nil
      }
    }
  }

  @discardableResult
  public func finishSession() async -> Bool {
    let generation = sessionID
    do {
      let payload = try await client.finishLanguageSession(
        LanguageFinishInput(drillIds: finishedDrillIds))
      guard generation == sessionID else { return false }
      progress = .ready(payload)
      finishedDrillIds.removeAll()
      banner = nil
      backfillSilently()
      return true
    } catch {
      guard generation == sessionID, !(error is CancellationError) else { return false }
      await handle(error)
      return false
    }
  }

  private func backfillSilently() {
    let pending = pendingCorrections
    guard !pending.isEmpty else { return }
    let generation = sessionID
    Task {
      for (drillId, input) in pending {
        guard generation == self.sessionID else { return }
        guard let correction = try? await self.client.gradeLanguageCorrection(input) else {
          continue
        }
        guard generation == self.sessionID else { return }
        _ = correction
        self.pendingCorrectionIds.remove(drillId)
        self.pendingCorrections.removeValue(forKey: drillId)
      }
    }
  }

  /// Volta ao estado de quem acabou de abrir o app. Sem isto, entrar de novo
  /// depois de um 401 mostraria os dados da sessão anterior.
  public func reset() {
    sessionID = UUID()
    routine = .idle
    queue = .idle
    progress = .idle
    completedDrillIds.removeAll()
    pendingCorrectionIds.removeAll()
    conflictDrillIds.removeAll()
    finishedDrillIds.removeAll()
    pendingCorrections.removeAll()
    serialTail?.cancel()
    serialTail = nil
    tailsByAttempt.removeAll()
  }

  // MARK: Mecânica

  private func handle(_ error: any Error) async {
    if case APIError.unauthorized = error {
      reset()
      banner = "sessão expirou"
      await onUnauthorized?()
      return
    }
    banner = Self.message(for: error)
  }

  private static func message(for error: any Error) -> String {
    (error as? APIError)?.message ?? "erro"
  }
}
