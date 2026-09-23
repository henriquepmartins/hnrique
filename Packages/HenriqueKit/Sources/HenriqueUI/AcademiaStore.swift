import Foundation
import HenriqueCore
import Observation

public struct SetKey: Hashable, Sendable, Codable {
  public enum Kind: String, Hashable, Sendable, Codable { case prep, work }

  public let date: CalendarDate
  public let templateId: String
  public let exerciseId: String
  public let kind: Kind
  public let index: Int

  public init(date: CalendarDate, templateId: String, exerciseId: String, kind: Kind, index: Int) {
    self.date = date
    self.templateId = templateId
    self.exerciseId = exerciseId
    self.kind = kind
    self.index = index
  }
}

struct SetDraft: Equatable, Sendable, Codable {
  let weightKg: Double
  let reps: Int
  let completed: Bool
  let toFailure: Bool
  var completedAt: Date? = nil
}

@MainActor
@Observable
public final class AcademiaStore {
  public enum Phase: Equatable, Sendable {
    case idle
    case loading
    case ready
    case failed(String)
  }

  public private(set) var phase: Phase = .idle
  /// Falso até a primeira leitura do chaveiro responder. Sem isto, todo arranque
  /// a frio mostra a entrada por uma fração de segundo mesmo com sessão válida.
  public private(set) var sessionChecked = false
  private var acceptedDashboard: Dashboard?
  /// Uma marcação que ainda não chegou ao servidor. Marcar série é o único
  /// gesto do app que acontece longe do wi-fi, então ela vive em disco até o
  /// servidor aceitar. `failed` liga quando já houve uma tentativa perdida, que
  /// é quando a tela precisa dizer que aquilo ainda está a caminho.
  private struct PendingSet: Codable {
    let key: SetKey
    let draft: SetDraft
    let revision: Int
    var failed: Bool
  }
  private var pendingSets: [SetKey: PendingSet] = [:]
  @ObservationIgnored private var mutationTail: Task<Bool, Never>?
  @ObservationIgnored private var resendTask: Task<Void, Never>?
  @ObservationIgnored private var revision = 0

  /// A série está marcada na tela mas ainda não no servidor. A tela mostra isso
  /// para o visto não prometer o que não aconteceu.
  public func isWaiting(_ key: SetKey) -> Bool { pendingSets[key]?.failed == true }

  public var dashboard: Dashboard? {
    guard var value = acceptedDashboard else { return nil }
    for pending in pendingSets.values.sorted(by: { $0.revision < $1.revision }) {
      let key = pending.key
      let draft = pending.draft
      if key.kind == .work {
        value = value.applyingSharedExerciseWeight(draft.weightKg, exerciseId: key.exerciseId)
      }
      guard value.date == key.date, value.workout?.id == key.templateId,
        var workout = value.workout,
        let exercise = workout.exercises.firstIndex(where: { $0.id == key.exerciseId }) else { continue }
      if key.kind == .prep,
        let row = workout.exercises[exercise].sets.prep.firstIndex(where: { $0.index == key.index }) {
        workout.exercises[exercise].sets.prep[row].weightKg = draft.weightKg
        workout.exercises[exercise].sets.prep[row].reps = draft.reps
        workout.exercises[exercise].sets.prep[row].completedAt = draft.completedAt
      } else if key.kind == .work,
        let row = workout.exercises[exercise].sets.work.firstIndex(where: { $0.index == key.index }) {
        workout.exercises[exercise].prescription.startingWeightKg = draft.weightKg
        workout.exercises[exercise].sets.work[row].weightKg = draft.weightKg
        workout.exercises[exercise].sets.work[row].reps = draft.reps
        workout.exercises[exercise].sets.work[row].toFailure = draft.toFailure
        workout.exercises[exercise].sets.work[row].completedAt = draft.completedAt
      }
      workout.completedWorkSetCount = workout.exercises.reduce(0) { $0 + $1.sets.completedWorkCount }
      workout.completionPercent = workout.workSetCount == 0 ? 0
        : Int((Double(workout.completedWorkSetCount) / Double(workout.workSetCount) * 100).rounded())
      value.workout = workout
    }
    return value
  }
  private var deletingWorkoutIds: Set<String> = []
  public private(set) var isSignedIn: Bool = false
  public var selectedDate: CalendarDate = .today
  public var banner: String?

  private let client: APIClient
  private struct CachedDay {
    let dashboard: Dashboard
    let storedAt: Date
  }
  @ObservationIgnored private var dayCache: [CalendarDate: CachedDay] = [:]
  public private(set) var attendance: [CalendarDate: AttendanceDay] = [:]
  @ObservationIgnored private var attendanceRanges: [ClosedRange<CalendarDate>] = []
  @ObservationIgnored private var readTask: Task<Void, Never>?
  @ObservationIgnored private var readID = UUID()
  @ObservationIgnored private var sessionID = UUID()

  private func cancelRead() {
    readID = UUID()
    readTask?.cancel()
    readTask = nil
  }

  private func invalidateDays() {
    dayCache.removeAll()
    cancelRead()
  }

  private func remember(_ value: Dashboard) {
    dayCache[value.date] = CachedDay(dashboard: value, storedAt: Date())
    if dayCache.count > 14, let oldest = dayCache.min(by: { $0.value.storedAt < $1.value.storedAt })?.key {
      dayCache.removeValue(forKey: oldest)
    }
    persist(value)
  }

  private static var snapshotURL: URL? {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
      .appending(path: "henrique-dashboard.json")
  }

  /// Pinta a última tela salva antes da rede responder. Só vale para hoje: dia
  /// antigo entra apagado e desabilitado, pior que o esqueleto.
  private func loadSnapshot() {
    guard let url = Self.snapshotURL,
      let data = try? Data(contentsOf: url),
      let saved = try? JSONDecoder.henrique().decode(Dashboard.self, from: data),
      saved.date == .today
    else { return }
    acceptedDashboard = saved
    phase = .ready
  }

  private func persist(_ value: Dashboard) {
    guard let url = Self.snapshotURL,
      let data = try? JSONEncoder.henrique().encode(value)
    else { return }
    Task.detached(priority: .background) {
      try? data.write(to: url, options: .atomic)
    }
  }

  private func clearSnapshot() {
    guard let url = Self.snapshotURL else { return }
    Task.detached(priority: .background) {
      try? FileManager.default.removeItem(at: url)
    }
  }

  /// Fora de `caches`, ao contrário do retrato do painel. O sistema apaga
  /// `caches` quando o disco aperta, e uma série marcada na academia é a única
  /// coisa aqui que não dá para buscar de novo no servidor.
  private static var queueURL: URL? {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
      .appending(path: "henrique-series-pendentes.json")
  }

  private func saveQueue() {
    guard let url = Self.queueURL else { return }
    let queued = pendingSets.values.sorted { $0.revision < $1.revision }
    Task.detached(priority: .background) {
      guard !queued.isEmpty else {
        try? FileManager.default.removeItem(at: url)
        return
      }
      guard let data = try? JSONEncoder.henrique().encode(queued) else { return }
      try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? data.write(to: url, options: .atomic)
    }
  }

  /// Tudo o que voltou do disco já falhou uma vez, por definição: só chega ali
  /// o que não foi aceito antes do app fechar.
  private func loadQueue() {
    guard let url = Self.queueURL, let data = try? Data(contentsOf: url),
      let saved = try? JSONDecoder.henrique().decode([PendingSet].self, from: data)
    else { return }
    for var pending in saved {
      pending.failed = true
      pendingSets[pending.key] = pending
      revision = max(revision, pending.revision)
    }
  }

  private func clearQueue() {
    pendingSets.removeAll()
    resendTask?.cancel()
    resendTask = nil
    guard let url = Self.queueURL else { return }
    Task.detached(priority: .background) {
      try? FileManager.default.removeItem(at: url)
    }
  }

  public init(client: APIClient) {
    self.client = client
    loadSnapshot()
    loadQueue()
  }

  #if DEBUG
    /// A casca do app sem servidor nem conta, só para capturar as telas com
    /// `--casca`. Nada carrega, então as abas aparecem vazias.
    @ObservationIgnored private var isCaptureShell = false

    public func openCaptureShell() {
      isCaptureShell = true
      isSignedIn = true
      sessionChecked = true
      phase = .ready
    }
  #endif

  public func start() async {
    #if DEBUG
      if isCaptureShell { return }
    #endif
    isSignedIn = await client.isSignedIn
    sessionChecked = true
    guard isSignedIn else {
      phase = .idle
      return
    }
    await load()
  }

  public func signIn(username: String, password: String) async {
    phase = .loading
    do {
      try await client.signIn(username: username, password: password)
      isSignedIn = true
      await load()
    } catch let error as APIError {
      phase = .failed(error.message)
    } catch {
      phase = .failed("não entrou")
    }
  }

  public func signOut() async {
    sessionID = UUID()
    invalidateDays()
    isSignedIn = false
    acceptedDashboard = nil
    clearSnapshot()
    attendance.removeAll()
    attendanceRanges.removeAll()
    clearQueue()
    mutationTail?.cancel()
    mutationTail = nil
    banner = nil
    phase = .idle
    await client.signOut()
  }

  public func load() async {
    await fetchDay(selectedDate)
  }

  public func select(date: CalendarDate) async {
    guard date != selectedDate else { return }
    selectedDate = date
    banner = nil
    if let cached = dayCache[date], Date().timeIntervalSince(cached.storedAt) < 30 {
      acceptedDashboard = cached.dashboard
      phase = .ready
    }
    await fetchDay(date)
  }

  private func fetchDay(_ date: CalendarDate) async {
    cancelRead()
    let requestID = readID
    if dashboard == nil { phase = .loading }
    let task = Task { [weak self, client] in
      _ = await self?.mutationTail?.value
      guard !Task.isCancelled else { return }
      do {
        let received = try await client.dashboard(on: date)
        guard let self, self.readID == requestID, self.selectedDate == date,
          received.date == date, !Task.isCancelled else { return }
        self.remember(received)
        self.acceptedDashboard = received
        self.phase = .ready
        self.banner = nil
        // A leitura que deu certo prova que a rede voltou. É o gatilho mais
        // barato que existe para esvaziar a fila.
        self.scheduleResend()
      } catch {
        guard let self, self.readID == requestID, self.selectedDate == date,
          !Task.isCancelled, !(error is CancellationError) else { return }
        self.handle(error)
      }
    }
    readTask = task
    await task.value
    if readID == requestID { readTask = nil }
  }

  /// Frequência não é dado crítico: falhou, o mapa fica como está, sem banner.
  /// Um intervalo já carregado não volta ao servidor; os dias antigos ficam e
  /// os novos entram por cima.
  public func loadAttendance(from: CalendarDate, to: CalendarDate) async {
    #if DEBUG
      if isCaptureShell { return }
    #endif
    guard from <= to, isSignedIn else { return }
    let range = from...to
    if attendanceRanges.contains(where: { $0.lowerBound <= from && to <= $0.upperBound }) { return }
    let session = sessionID
    guard let days = try? await client.attendance(.init(from: from, to: to)),
      session == sessionID else { return }
    for day in days { attendance[day.date] = day }
    attendanceRanges.append(range)
  }

  @discardableResult
  public func record(
    key: SetKey, weightKg: Double, reps: Int,
    completed: Bool, toFailure: Bool
  ) -> Task<Bool, Never>? {
    guard key.date == selectedDate, let dashboard, dashboard.date == key.date,
      let workout = dashboard.workout, workout.id == key.templateId,
      weightKg.isFinite, weightKg >= 0, reps > 0 else { return nil }
    let exercise = workout.exercises.first { $0.id == key.exerciseId }
    let existingDate = key.kind == .prep
      ? exercise?.sets.prep.first { $0.index == key.index }?.completedAt
      : exercise?.sets.work.first { $0.index == key.index }?.completedAt
    let draft = SetDraft(
      weightKg: weightKg, reps: reps, completed: completed, toFailure: toFailure,
      completedAt: completed ? (existingDate ?? .now) : nil)
    if pendingSets[key]?.draft == draft { return mutationTail }
    revision += 1
    let pending = PendingSet(key: key, draft: draft, revision: revision, failed: false)
    pendingSets[key] = pending
    saveQueue()
    return send(pending)
  }

  private func send(_ pending: PendingSet) -> Task<Bool, Never> {
    let key = pending.key
    let draft = pending.draft
    let fields = RecordSetInput.Fields(
      date: key.date, workoutTemplateId: key.templateId, exerciseId: key.exerciseId,
      setIndex: key.index, weightKg: draft.weightKg, reps: draft.reps, completed: draft.completed)
    let input: RecordSetInput = key.kind == .prep
      ? .prep(fields) : .work(fields, toFailure: draft.toFailure)
    return enqueue(pending: pending) {
      let received = try await self.client.recordSet(input)
      guard key.kind == .work else { return received }
      return received.applyingSharedExerciseWeight(draft.weightKg, exerciseId: key.exerciseId)
    }
  }

  /// Gravar série é idempotente no servidor, que casa por sessão, exercício,
  /// tipo e índice, então reenviar a mesma marcação não duplica nada.
  private func resend() async -> Bool {
    for pending in pendingSets.values.sorted(by: { $0.revision < $1.revision }) {
      guard let current = pendingSets[pending.key], current.revision == pending.revision else {
        continue
      }
      // Uma falha basta para saber que a rede continua fora. Insistir no resto
      // da fila só gasta bateria e enche a tela de banner.
      if await send(current).value == false { return false }
    }
    return true
  }

  private func scheduleResend() {
    guard resendTask == nil, !pendingSets.isEmpty else { return }
    resendTask = Task { @MainActor [weak self] in
      await self?.resendLoop()
      self?.resendTask = nil
    }
  }

  /// Dobra a espera até um minuto e fica lá. Sem `NWPathMonitor` de propósito:
  /// um minuto de atraso no pior caso não muda nada para quem está entre séries,
  /// e observar a rede seria mais peça para manter.
  private func resendLoop() async {
    var wait = 2.0
    while isSignedIn, !pendingSets.isEmpty, !Task.isCancelled {
      wait = await resend() ? 2 : min(wait * 2, 60)
      guard !pendingSets.isEmpty, !Task.isCancelled else { return }
      try? await Task.sleep(for: .seconds(wait))
    }
  }

  @discardableResult
  public func addMeasurement(_ input: AddMeasurementInput) async -> Bool {
    await apply { try await self.client.addMeasurement(input) }
  }

  @discardableResult
  public func saveWorkout(_ input: SaveWorkoutInput) async -> Bool {
    await apply { try await self.client.saveWorkout(input) }
  }

  @discardableResult
  public func setCount(_ input: SetCountInput) async -> Bool {
    await apply { try await self.client.setCount(input) }
  }

  @discardableResult
  public func addExercise(_ input: AddSessionExerciseInput) async -> Bool {
    await apply { try await self.client.addExercise(input) }
  }

  @discardableResult
  public func removeExercise(_ input: RemoveSessionExerciseInput) async -> Bool {
    await apply { try await self.client.removeExercise(input) }
  }

  @discardableResult
  public func setNote(_ input: SetExerciseNoteInput) async -> Bool {
    await apply { try await self.client.setNote(input) }
  }

  /// O plano sem os treinos que estão sendo apagados. O card some no toque, sem
  /// esperar o servidor apagar as sessões e recalcular o painel.
  public var weekPlan: [WeekPlanItem] {
    (dashboard?.weekPlan ?? []).filter { !deletingWorkoutIds.contains($0.id) }
  }

  /// Volta a mostrar o treino se o servidor recusar. No sucesso o painel novo
  /// chega na mesma volta do laço, já sem ele, e o card não pisca.
  public func deleteWorkout(workoutTemplateId: String) {
    guard deletingWorkoutIds.insert(workoutTemplateId).inserted else { return }
    let date = selectedDate
    Task {
      defer { deletingWorkoutIds.remove(workoutTemplateId) }
      await apply {
        try await self.client.deleteWorkout(.init(date: date, workoutTemplateId: workoutTemplateId))
      }
    }
  }

  /// Troca o treino do dia aberto. Nulo volta o dia para o plano.
  @discardableResult
  public func swapDay(workoutTemplateId: String?) async -> Bool {
    let input = SwapDayInput(date: selectedDate, workoutTemplateId: workoutTemplateId)
    return await apply { try await self.client.swapDay(input) }
  }

  @discardableResult
  public func setStrengthGoal(_ input: SetStrengthGoalInput) async -> Bool {
    await apply { try await self.client.setStrengthGoal(input) }
  }

  @discardableResult
  public func setStreakGoal(_ input: SetStreakGoalInput) async -> Bool {
    await apply { try await self.client.setStreakGoal(input) }
  }

  @discardableResult
  public func completeSetup() async -> Bool {
    await apply {
      try await self.client.completeOnboarding()
      return try await self.client.dashboard(on: self.selectedDate)
    }
  }

  @discardableResult
  private func apply(_ work: @escaping @Sendable () async throws -> Dashboard) async -> Bool {
    await enqueue(work).value
  }

  private func enqueue(
    pending: PendingSet? = nil, _ work: @escaping @Sendable () async throws -> Dashboard
  ) -> Task<Bool, Never> {
    invalidateDays()
    let mutationSession = sessionID
    let previous = mutationTail
    let task = Task { @MainActor in
      _ = await previous?.value
      guard sessionID == mutationSession, !Task.isCancelled else { return false }
      do {
        let received = try await work()
        guard sessionID == mutationSession, !Task.isCancelled else { return false }
        forget(pending)
        dayCache.removeAll()
        // a série gravada muda a frequência; o mapa fica na tela e o próximo
        // mês visitado busca de novo.
        attendanceRanges.removeAll()
        remember(received)
        if received.date == selectedDate {
          acceptedDashboard = received
          phase = .ready
        }
        return true
      } catch {
        guard sessionID == mutationSession, !Task.isCancelled else { return false }
        dayCache.removeAll()
        guard !(error is CancellationError) else { return false }
        var kept = false
        if let pending {
          kept = Self.keeps(error)
          if kept { hold(pending) } else { forget(pending) }
        }
        // A sessão caída tira o usuário da conta mesmo com a série guardada, e
        // o aviso dela vale mais do que a contagem da fila.
        if !kept || (error as? APIError) == .unauthorized { handle(error) }
        return false
      }
    }
    mutationTail = task
    return task
  }

  /// Rede fora e servidor doente voltam a ser tentados. Recusa do servidor não:
  /// o mesmo corpo nunca vai passar, e insistir entope a fila atrás dele.
  private static func keeps(_ error: any Error) -> Bool {
    switch error {
    case APIError.http(let status, _): status >= 500
    default: true
    }
  }

  /// A marcação some da rede, não da tela. O banner conta quantas esperam,
  /// porque "sem conexão" sozinho parece série perdida, e não é mais.
  private func hold(_ pending: PendingSet) {
    guard pendingSets[pending.key]?.revision == pending.revision else { return }
    pendingSets[pending.key]?.failed = true
    saveQueue()
    banner = pendingSets.count == 1
      ? "1 série guardada, envio quando a rede voltar"
      : "\(pendingSets.count) séries guardadas, envio quando a rede voltar"
    scheduleResend()
  }

  private func forget(_ pending: PendingSet?) {
    guard let pending, pendingSets[pending.key]?.revision == pending.revision else { return }
    pendingSets.removeValue(forKey: pending.key)
    saveQueue()
  }

  private func handle(_ error: any Error) {
    switch error {
    case APIError.unauthorized:
      sessionID = UUID()
      invalidateDays()
      isSignedIn = false
      acceptedDashboard = nil
      attendance.removeAll()
      attendanceRanges.removeAll()
      mutationTail?.cancel()
      mutationTail = nil
      phase = .idle
      banner = "sessão expirou"
    case let error as APIError:
      if dashboard == nil {
        phase = .failed(error.message)
      } else {
        banner = error.message
      }
    default:
      banner = "erro"
    }
  }
}
