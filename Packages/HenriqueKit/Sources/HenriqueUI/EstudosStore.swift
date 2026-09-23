import Foundation
import HenriqueCore
import Observation

/// O estado de uma aba. A tela lê os quatro casos direto, sem um booleano de
/// carregamento em paralelo que pudesse discordar do valor.
public enum Loadable<Value: Sendable>: Sendable {
  case idle
  case loading
  case ready(Value)
  case failed(String)

  public var value: Value? {
    guard case .ready(let value) = self else { return nil }
    return value
  }

  public var isLoading: Bool {
    if case .loading = self { return true }
    return false
  }

  public var failure: String? {
    guard case .failed(let message) = self else { return nil }
    return message
  }

}

extension Loadable: Equatable where Value: Equatable {}
extension Loadable: Hashable where Value: Hashable {}

@MainActor
@Observable
public final class EstudosStore {
  public enum Phase: Equatable, Sendable {
    case idle
    case loading
    case ready
    case failed(String)
  }

  public private(set) var overview: Loadable<StudyOverview> = .idle
  public private(set) var subjects: Loadable<[StudySubject]> = .idle
  public private(set) var assignments: Loadable<[AssignmentGroup]> = .idle
  public private(set) var notebooks: Loadable<[Notebook]> = .idle
  public private(set) var queue: Loadable<ReviewQueue> = .idle
  public private(set) var notes: Loadable<[NoteSummary]> = .idle
  public var banner: String?

  /// O RootView liga isto ao `signOut()` da Academia. Os dois stores dividem a
  /// mesma sessão, então quem descobre que ela caiu avisa o outro.
  public var onUnauthorized: (@MainActor () async -> Void)?

  /// O foco divide o mesmo cliente para a sessão ser uma só.
  public let client: APIClient
  @ObservationIgnored private var subjectCache: [String: SubjectDetail] = [:]
  @ObservationIgnored private var pageCache: [String: NotebookPage] = [:]
  @ObservationIgnored private var loadedNotesSubject: String?

  /// Muda a cada `reset()`. As cinco abas carregam juntas, então o resultado de
  /// uma chamada que saiu antes da sessão cair não pode voltar a entrar no
  /// estado depois, nem derrubar a sessão uma segunda vez.
  @ObservationIgnored private var sessionID = UUID()

  /// Quando cada aba chegou do servidor. A aba que veio do disco não tem
  /// entrada aqui, então a primeira tela que a pede ainda vai à rede.
  @ObservationIgnored private var fetchedAt: [PartialKeyPath<EstudosStore>: Date] = [:]
  static let staleAfter: TimeInterval = 5 * 60

  private let snapshotURL: URL?

  public init(client: APIClient, snapshotURL: URL? = EstudosStore.defaultSnapshotURL) {
    self.client = client
    self.snapshotURL = snapshotURL
    restoreSnapshot()
  }

  /// Em `caches`, como o retrato do painel da academia: se o sistema apagar,
  /// o app só volta a precisar da rede para a primeira tela.
  public static var defaultSnapshotURL: URL? {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
      .appending(path: "henrique-estudos.json")
  }

  #if DEBUG
    /// Companheiro do `openCaptureShell()` da Academia. Segura as cinco abas no
    /// lugar para `--casca` capturar a casca sem servidor.
    @ObservationIgnored private var isCaptureShell = false

    public func openCaptureShell() {
      isCaptureShell = true
      overview = .idle
      subjects = .idle
      assignments = .idle
      notebooks = .idle
      queue = .idle
    }
  #endif

  /// Um resumo das abas para a casca do app. Fica derivado das abas para não
  /// haver uma segunda verdade capaz de discordar delas.
  public var phase: Phase {
    let lanes = [overview.phase, subjects.phase, assignments.phase, notebooks.phase, queue.phase]
    if lanes.contains(.ready) { return .ready }
    if lanes.contains(.loading) { return .loading }
    if let failure = lanes.first(where: { $0.failureMessage != nil }) { return failure }
    return .idle
  }

  // MARK: Leituras

  public func loadOverview(force: Bool = false) async {
    await fetch(into: \.overview, force: force) {
      try await self.client.studyOverview(on: .today)
    }
  }

  public func loadSubjects(force: Bool = false) async {
    await fetch(into: \.subjects, force: force) { try await self.client.studySubjects() }
  }

  public func loadAssignments(force: Bool = false) async {
    await fetch(into: \.assignments, force: force) { try await self.client.studyAssignments() }
  }

  public func loadNotebooks(force: Bool = false) async {
    await fetch(into: \.notebooks, force: force) { try await self.client.notebooks() }
  }

  public func loadQueue(force: Bool = false) async {
    await fetch(into: \.queue, force: force) { try await self.client.reviewQueue() }
  }

  public func loadNotes(subjectId: String? = nil, force: Bool = false) async {
    let changedSubject = subjectId != loadedNotesSubject
    loadedNotesSubject = subjectId
    await fetch(into: \.notes, force: force || changedSubject) {
      try await self.client.studyNotes(subjectId: subjectId)
    }
  }

  /// A casca do app pede as cinco abas de uma vez, como o web faz ao montar.
  public func prefetchAll() async {
    await loadAll(force: false)
  }

  public func refresh() async {
    await loadAll(force: true)
  }

  private func loadAll(force: Bool) async {
    banner = nil
    if force {
      // O refresh precisa alcançar o detalhe da matéria e a página do caderno.
      // Sem isto, puxar para baixo nessas telas não traria nada novo.
      subjectCache.removeAll()
      pageCache.removeAll()
    }
    async let overview: Void = loadOverview(force: force)
    async let subjects: Void = loadSubjects(force: force)
    async let assignments: Void = loadAssignments(force: force)
    async let notebooks: Void = loadNotebooks(force: force)
    async let queue: Void = loadQueue(force: force)
    _ = await (overview, subjects, assignments, notebooks, queue)
  }

  public func subjectDetail(id: String, force: Bool = false) async -> SubjectDetail? {
    if !force, let cached = subjectCache[id] { return cached }
    let generation = sessionID
    do {
      guard let detail = try await client.studySubject(id: id) else { return nil }
      guard generation == sessionID else { return nil }
      subjectCache[id] = detail
      return detail
    } catch {
      guard generation == sessionID, !(error is CancellationError) else { return nil }
      await handle(error)
      return nil
    }
  }

  public func notebookPage(id: String, force: Bool = false) async -> NotebookPage? {
    if !force, let cached = pageCache[id] { return cached }
    let generation = sessionID
    do {
      guard let page = try await client.notebookPage(id: id) else { return nil }
      guard generation == sessionID else { return nil }
      pageCache[id] = page
      return page
    } catch {
      guard generation == sessionID, !(error is CancellationError) else { return nil }
      await handle(error)
      return nil
    }
  }

  // MARK: Mutações

  /// Troca o estado na tela antes da resposta e desfaz se o servidor recusar.
  /// O toque no quadradinho precisa parecer instantâneo.
  public func setStatus(of assignment: StudyAssignment, to status: AssignmentStatus) async {
    var optimistic = assignment
    optimistic.status = status
    apply(optimistic)
    let generation = sessionID
    do {
      let saved = try await client.setAssignmentStatus(
        SetAssignmentStatusInput(id: assignment.id, status: status))
      guard generation == sessionID else { return }
      apply(saved)
      banner = nil
    } catch {
      guard generation == sessionID else { return }
      apply(assignment)
      if !(error is CancellationError) { await handle(error) }
    }
  }

  public func createNotebookPage(subjectId: String) async -> NotebookPage? {
    let generation = sessionID
    do {
      let page = try await client.saveNotebookPage(
        SaveNotebookPageInput(subjectId: subjectId, title: "", content: []))
      guard generation == sessionID else { return nil }
      remember(page)
      banner = nil
      return page
    } catch {
      guard generation == sessionID, !(error is CancellationError) else { return nil }
      await handle(error)
      return nil
    }
  }

  @discardableResult
  public func saveNotebookPage(_ input: SaveNotebookPageInput) async throws -> NotebookPage {
    let page = try await mutate { try await self.client.saveNotebookPage(input) }
    remember(page)
    return page
  }

  public func removeNotebookPage(id: String) async -> Bool {
    let generation = sessionID
    do {
      try await client.removeNotebookPage(id: id)
      guard generation == sessionID else { return false }
      pageCache.removeValue(forKey: id)
      if var list = notebooks.value {
        for index in list.indices {
          list[index].pages.removeAll { $0.id == id }
        }
        notebooks = .ready(list)
      }
      banner = nil
      return true
    } catch {
      guard generation == sessionID, !(error is CancellationError) else { return false }
      await handle(error)
      return false
    }
  }

  public func startSession(id: String? = nil, subjectId: String?) async throws -> StudySession {
    try await mutate {
      try await self.client.startStudySession(StartSessionInput(id: id, subjectId: subjectId))
    }
  }

  public func finishSession(id: String, minutes: Int) async throws -> StudySession {
    try await mutate {
      try await self.client.finishStudySession(
        FinishSessionInput(id: id, completedMinutes: minutes))
    }
  }

  @discardableResult
  public func saveNote(_ input: SaveNoteInput) async throws -> StudyNote {
    try await mutate { try await self.client.saveStudyNote(input) }
  }

  /// `expectedDueAt` leva o vencimento que a tela mostrou. Se o cartão já mudou
  /// em outro aparelho, o servidor responde 409 em vez de reagendar duas vezes.
  public func grade(card: Flashcard, rating: FlashcardRating) async throws -> GradeResult {
    let result = try await mutate {
      try await self.client.gradeFlashcard(
        GradeFlashcardInput(id: card.id, rating: rating, expectedDueAt: card.dueAt))
    }
    if var value = overview.value, value.reviewCount > 0 {
      value.reviewCount -= 1
      overview = .ready(value)
    }
    // O cartão sai da fila com qualquer nota. Mesmo "errei" empurra o
    // vencimento dez minutos para a frente, e a fila só traz o que já venceu.
    if var pending = queue.value {
      pending.cards.removeAll { $0.id == card.id }
      for index in pending.bySubject.indices
      where pending.bySubject[index].subjectId == card.subjectId
        && pending.bySubject[index].count > 0
      {
        pending.bySubject[index].count -= 1
      }
      pending.bySubject.removeAll { $0.count == 0 }
      queue = .ready(pending)
    }
    return result
  }

  /// Volta ao estado de quem acabou de abrir o app. Sem isto, entrar de novo
  /// depois de um 401 mostraria os dados da sessão anterior, porque as abas
  /// continuariam `ready` e nenhum load refaria a chamada.
  public func reset() {
    sessionID = UUID()
    overview = .idle
    subjects = .idle
    assignments = .idle
    notebooks = .idle
    queue = .idle
    notes = .idle
    subjectCache.removeAll()
    pageCache.removeAll()
    loadedNotesSubject = nil
    fetchedAt.removeAll()
    if let snapshotURL {
      Task.detached(priority: .background) { try? FileManager.default.removeItem(at: snapshotURL) }
    }
  }

  // MARK: Retrato no disco

  /// O resumo do dia só volta se for de hoje. Os pendentes de ontem com o dia
  /// da semana de ontem no título enganam mais do que ajudam.
  private func restoreSnapshot() {
    guard let snapshotURL, let saved = EstudosSnapshot.read(from: snapshotURL) else { return }
    if let value = saved.overview, value.date == .today { overview = .ready(value) }
    if let value = saved.subjects { subjects = .ready(value) }
    if let value = saved.assignments { assignments = .ready(value) }
    if let value = saved.notebooks { notebooks = .ready(value) }
    if let value = saved.queue { queue = .ready(value) }
  }

  private func persistSnapshot() {
    guard let snapshotURL else { return }
    let snapshot = EstudosSnapshot(
      overview: overview.value, subjects: subjects.value, assignments: assignments.value,
      notebooks: notebooks.value, queue: queue.value)
    Task.detached(priority: .background) { try? snapshot.write(to: snapshotURL) }
  }

  // MARK: Mecânica

  private func fetch<Value: Sendable>(
    into keyPath: ReferenceWritableKeyPath<EstudosStore, Loadable<Value>>,
    force: Bool,
    work: () async throws -> Value
  ) async {
    #if DEBUG
      if isCaptureShell { return }
    #endif
    let current = self[keyPath: keyPath]
    if current.isLoading { return }
    if current.value != nil, !force, let at = fetchedAt[keyPath],
      Date.now.timeIntervalSince(at) < Self.staleAfter
    {
      return
    }
    // Um refresh com dados na tela mantém o que já está lá. Quem vê o giro é o
    // `.refreshable`, não a aba inteira piscando.
    if current.value == nil { self[keyPath: keyPath] = .loading }
    let generation = sessionID
    do {
      let value = try await work()
      // Uma aba que só respondeu depois de a sessão cair não pode ressuscitar
      // os dados que o `reset()` acabou de tirar.
      guard generation == sessionID else { return }
      // O sucesso não limpa o aviso. As cinco abas carregam em paralelo, e uma
      // que desse certo apagaria o erro da que falhou.
      self[keyPath: keyPath] = .ready(value)
      fetchedAt[keyPath] = .now
      persistSnapshot()
    } catch {
      guard generation == sessionID else { return }
      guard !(error is CancellationError) else {
        self[keyPath: keyPath] = current
        return
      }
      await handle(error)
      // Um 401 já zerou tudo em `reset()`. Marcar a aba como falha por cima
      // deixaria um erro na tela no lugar da entrada de novo.
      if case APIError.unauthorized = error { return }
      if self[keyPath: keyPath].value == nil {
        self[keyPath: keyPath] = .failed(Self.message(for: error))
      }
    }
  }

  private func mutate<Value: Sendable>(_ work: () async throws -> Value) async throws -> Value {
    let generation = sessionID
    do {
      let value = try await work()
      if generation == sessionID { banner = nil }
      return value
    } catch {
      if generation == sessionID, !(error is CancellationError) { await handle(error) }
      throw error
    }
  }

  /// Troca a entrega inteira, não só o estado. O servidor pode normalizar o
  /// título ou o prazo junto, e a tela precisa ver isso.
  private func apply(_ updated: StudyAssignment) {
    if var groups = assignments.value {
      for group in groups.indices {
        for item in groups[group].items.indices where groups[group].items[item].id == updated.id {
          groups[group].items[item] = updated
        }
      }
      assignments = .ready(groups)
    }
    if var value = overview.value {
      for index in value.dueSoon.indices where value.dueSoon[index].id == updated.id {
        value.dueSoon[index] = updated
      }
      overview = .ready(value)
    }
    // A tela da matéria mostra a mesma entrega e lê do cache, então ela também
    // precisa do quadradinho marcado.
    if let subjectId = updated.subjectId, var detail = subjectCache[subjectId] {
      for index in detail.assignments.indices where detail.assignments[index].id == updated.id {
        detail.assignments[index] = updated
      }
      subjectCache[subjectId] = detail
    }
  }

  private func remember(_ page: NotebookPage) {
    pageCache[page.id] = page
    guard var list = notebooks.value else { return }
    for index in list.indices where list[index].subject.id == page.subjectId {
      if let existing = list[index].pages.firstIndex(where: { $0.id == page.id }) {
        list[index].pages[existing] = page.summary
      } else {
        list[index].pages.append(page.summary)
      }
      list[index].pages.sort {
        $0.position == $1.position ? $0.updatedAt > $1.updatedAt : $0.position < $1.position
      }
    }
    notebooks = .ready(list)
  }

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

extension Loadable {
  /// Em que pé está, sem o valor. É o que a tela observa para trocar de
  /// carregando para conteúdo sem exigir Equatable de quem carrega.
  var phase: EstudosStore.Phase {
    switch self {
    case .idle: .idle
    case .loading: .loading
    case .ready: .ready
    case .failed(let message): .failed(message)
    }
  }
}

extension EstudosStore.Phase {
  fileprivate var failureMessage: String? {
    guard case .failed(let message) = self else { return nil }
    return message
  }
}
