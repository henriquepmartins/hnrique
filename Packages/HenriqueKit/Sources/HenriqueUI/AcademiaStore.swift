import Foundation
import HenriqueCore
import Observation
#if canImport(UIKit)
  import UIKit
#endif

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
  @ObservationIgnored private var acceptedDashboard: Dashboard? {
    didSet { dashboard = projected() }
  }
  /// Uma marcação que ainda não chegou ao servidor. Marcar série é o único
  /// gesto do app que acontece longe do wi-fi, então ela vive em disco até o
  /// servidor aceitar. `failed` liga quando já houve uma tentativa perdida, que
  /// é quando a tela precisa dizer que aquilo ainda está a caminho.
  struct PendingSet: Codable {
    let key: SetKey
    let draft: SetDraft
    let revision: Int
    var failed: Bool
    /// Respostas 5xx seguidas. No limite a série sai da fila, senão um corpo
    /// que derruba o servidor segura todas as outras atrás dele.
    var serverFailures = 0

    init(key: SetKey, draft: SetDraft, revision: Int, failed: Bool) {
      self.key = key
      self.draft = draft
      self.revision = revision
      self.failed = failed
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      key = try container.decode(SetKey.self, forKey: .key)
      draft = try container.decode(SetDraft.self, forKey: .draft)
      revision = try container.decode(Int.self, forKey: .revision)
      failed = try container.decode(Bool.self, forKey: .failed)
      serverFailures = try container.decodeIfPresent(Int.self, forKey: .serverFailures) ?? 0
    }
  }
  static let serverFailureLimit = 5
  private var pendingSets: [SetKey: PendingSet] = [:] {
    didSet { dashboard = projected() }
  }
  @ObservationIgnored private var mutationTail: Task<MutationOutcome, Never>?
  @ObservationIgnored private var resendTask: Task<Void, Never>?
  @ObservationIgnored private var revision = 0

  /// Como terminou uma escrita. A fila de séries precisa separar a rede fora,
  /// que para o reenvio, do servidor recusando uma série só, que não para.
  public enum MutationOutcome: Equatable, Sendable {
    case applied
    case offline
    case refused
  }

  /// A série está marcada na tela mas ainda não no servidor. A tela mostra isso
  /// para o visto não prometer o que não aconteceu.
  public func isWaiting(_ key: SetKey) -> Bool { pendingSets[key]?.failed == true }

  /// Quantas séries esperam a rede. A tela diz isso numa linha, sem alerta:
  /// um alerta por cima da sessão de treino fechava a sessão.
  public var waitingCount: Int { pendingSets.values.count(where: \.failed) }

  /// Um aviso que não pede toque: a série que o servidor recusou e saiu da fila.
  public var notice: String?

  /// O painel aceito com as marcações pendentes por cima. Guardado, e não
  /// calculado a cada leitura: cada linha de série lê o painel várias vezes
  /// por pintura.
  public private(set) var dashboard: Dashboard? {
    didSet { noteStart() }
  }

  private func projected() -> Dashboard? {
    guard var value = acceptedDashboard else { return nil }
    for pending in pendingSets.values.sorted(by: { $0.revision < $1.revision }) {
      let key = pending.key
      let draft = pending.draft
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
        workout.exercises[exercise].sets.work[row].weightKg = draft.weightKg
        workout.exercises[exercise].sets.work[row].reps = draft.reps
        workout.exercises[exercise].sets.work[row].toFailure = draft.toFailure
        workout.exercises[exercise].sets.work[row].completedAt = draft.completedAt
      }
      workout.completedWorkSetCount = workout.exercises.reduce(0) { $0 + $1.sets.completedWorkCount }
      workout.completionPercent = workout.workSetCount == 0 ? 0
        : Int((Double(workout.completedWorkSetCount) / Double(workout.workSetCount) * 100).rounded())
      value.workout = workout
      if key.kind == .work, draft.completed {
        value = value.applyingTopWorkWeight(exerciseId: key.exerciseId)
      }
    }
    return value
  }
  private var deletingWorkoutIds: Set<String> = []
  public private(set) var isSignedIn: Bool = false
  public var selectedDate: CalendarDate = .today
  /// O dia que era hoje na última olhada. Quem estava em hoje quando a
  /// meia-noite passou vai junto para o dia novo; quem escolheu outro dia fica.
  @ObservationIgnored private var knownToday: CalendarDate = .today
  public var banner: String?

  /// O descanso em curso. Mora aqui, e não na tela da sessão, porque minimizar
  /// a sessão ou fechar o app não para o relógio da academia.
  public private(set) var rest: RestState?
  @ObservationIgnored private var restExpiry: Task<Void, Never>?
  @ObservationIgnored private let restAlarm: any RestAlarm
  /// Descanso escolhido no aparelho por exercício. Vale por cima do plano e vai
  /// junto no próximo salvar do plano; some quando o servidor devolve o mesmo valor.
  private var restOverrides: [String: Int] = [:]
  /// Quando cada treino foi encerrado, por dia e treino. O servidor não guarda
  /// isso; é o que diz ao card "ver o treino" em vez de "continuar".
  private var finishedAt: [String: Date] = [:]
  /// O começo de cada treino, por dia e treino. Só anda para trás: desmarcar a
  /// primeira série apaga a data dela no servidor, e o relógio não pode
  /// recomeçar por isso.
  @ObservationIgnored private var startedAt: [String: Date] = [:]
  @ObservationIgnored private let defaults: UserDefaults

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

  /// Uma série gravada muda o próprio dia e o "anterior" dos dias seguintes. Os
  /// dias de antes e os meses de frequência sem a data continuam valendo.
  private func invalidate(from date: CalendarDate) {
    dayCache = dayCache.filter { $0.key < date }
    attendanceRanges.removeAll { $0.contains(date) }
  }

  private func invalidateAll() {
    dayCache.removeAll()
    // a escrita muda a frequência; o mapa fica na tela e o próximo mês
    // visitado busca de novo.
    attendanceRanges.removeAll()
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

  /// Escrita síncrona. São poucos bytes, e a escrita em segundo plano podia
  /// não terminar antes do sistema matar o app logo depois da marcação.
  private func saveQueue() {
    guard let url = Self.queueURL else { return }
    let queued = pendingSets.values.sorted { $0.revision < $1.revision }
    guard !queued.isEmpty else {
      try? FileManager.default.removeItem(at: url)
      return
    }
    guard let data = try? JSONEncoder.henrique().encode(queued) else { return }
    try? FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
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
    saveQueue()
  }

  public convenience init(client: APIClient) {
    self.init(client: client, restAlarm: AcademiaRestAlarm(), defaults: .standard)
  }

  init(client: APIClient, restAlarm: any RestAlarm, defaults: UserDefaults) {
    self.client = client
    self.restAlarm = restAlarm
    self.defaults = defaults
    loadLocalState()
    loadSnapshot()
    loadQueue()
    observeDayChanges()
  }

  enum DefaultsKey {
    static let rest = "academia.descanso"
    static let restOverrides = "academia.descanso.por-exercicio"
    static let finished = "academia.treinos-encerrados"
    static let started = "academia.treinos-comecados"
    static let celebratedTier = "academia.insignia-comemorada"
  }

  private func loadLocalState() {
    if let data = defaults.data(forKey: DefaultsKey.rest),
      let saved = try? JSONDecoder().decode(RestState.self, from: data),
      !saved.isExpired(at: .now) {
      rest = saved
      scheduleRestExpiry()
    }
    restOverrides = defaults.dictionary(forKey: DefaultsKey.restOverrides) as? [String: Int] ?? [:]
    if let data = defaults.data(forKey: DefaultsKey.finished),
      let saved = try? JSONDecoder().decode([String: Date].self, from: data) {
      let cutoff = CalendarDate.today.adding(days: -14).iso
      finishedAt = saved.filter { $0.key >= cutoff }
    }
    if let data = defaults.data(forKey: DefaultsKey.started),
      let saved = try? JSONDecoder().decode([String: Date].self, from: data) {
      let cutoff = CalendarDate.today.adding(days: -14).iso
      startedAt = saved.filter { $0.key >= cutoff }
    }
  }

  private func observeDayChanges() {
    #if canImport(UIKit)
      NotificationCenter.default.addObserver(
        forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.followToday() }
      }
    #endif
    NotificationCenter.default.addObserver(
      forName: .NSCalendarDayChanged, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.followToday() }
    }
  }

  /// Chamada quando o app volta ou o dia vira. Só anda se quem usa estava
  /// olhando o dia que era hoje.
  func followToday(now today: CalendarDate = .today) {
    let previous = knownToday
    knownToday = today
    guard previous != today, selectedDate == previous, isSignedIn else { return }
    Task { await select(date: today) }
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
    endRest()
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
  /// Verdadeiro quando o intervalo inteiro está em `attendance`.
  @discardableResult
  public func loadAttendance(from: CalendarDate, to: CalendarDate) async -> Bool {
    #if DEBUG
      if isCaptureShell { return false }
    #endif
    guard from <= to, isSignedIn else { return false }
    let range = from...to
    if attendanceRanges.contains(where: { $0.lowerBound <= from && to <= $0.upperBound }) { return true }
    let session = sessionID
    guard let days = try? await client.attendance(.init(from: from, to: to)),
      session == sessionID else { return false }
    for day in days { attendance[day.date] = day }
    attendanceRanges.append(range)
    return true
  }

  // MARK: - A insígnia

  /// A sequência de presença atual com o começo dela, lida de até 400 dias de
  /// frequência, que é o limite da rota.
  public private(set) var tenure: StreakTenure?
  /// O nível que ainda não foi comemorado. Some quando a camada abre.
  public private(set) var pendingInsignia: CelebratedTier?

  #if DEBUG
    /// `--insignia N`: finge N meses de sequência e ignora o que já foi
    /// comemorado, para tocar qualquer nível no simulador.
    public var insigniaMonthsOverride: Int?
  #endif

  public func refreshInsignia() async {
    #if DEBUG
      if let months = insigniaMonthsOverride {
        guard tenure == nil, dashboard != nil || isCaptureShell else { return }
        let forced = StreakTenure(start: .today, months: months)
        tenure = forced
        pendingInsignia = forced.celebration(after: nil)
        return
      }
    #endif
    let today = CalendarDate.today
    guard dashboard?.date == today,
      await loadAttendance(from: today.adding(days: -399), to: today)
    else { return }
    tenure = StreakTenure(attendance: attendance, today: today)
    pendingInsignia = tenure?.celebration(after: celebratedTier)
  }

  /// Grava quando a camada abre, e não quando fecha: fechar o app no meio da
  /// festa não pode fazer ela tocar de novo na próxima abertura.
  public func insigniaOpened(_ celebrated: CelebratedTier) {
    pendingInsignia = nil
    #if DEBUG
      if insigniaMonthsOverride != nil { return }
    #endif
    guard let data = try? JSONEncoder.henrique().encode(celebrated) else { return }
    defaults.set(data, forKey: DefaultsKey.celebratedTier)
  }

  private var celebratedTier: CelebratedTier? {
    defaults.data(forKey: DefaultsKey.celebratedTier)
      .flatMap { try? JSONDecoder.henrique().decode(CelebratedTier.self, from: $0) }
  }

  @discardableResult
  public func record(
    key: SetKey, weightKg: Double, reps: Int,
    completed: Bool, toFailure: Bool
  ) -> Task<MutationOutcome, Never>? {
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
    if key.kind == .work {
      if completed && existingDate == nil {
        reopen(workout.id, on: key.date)
        startRest(after: key)
      } else if !completed && rest?.key == key {
        endRest()
      }
    }
    return send(pending)
  }

  private func send(_ pending: PendingSet) -> Task<MutationOutcome, Never> {
    let key = pending.key
    let draft = pending.draft
    let fields = RecordSetInput.Fields(
      date: key.date, workoutTemplateId: key.templateId, exerciseId: key.exerciseId,
      setIndex: key.index, weightKg: draft.weightKg, reps: draft.reps, completed: draft.completed,
      completedAt: draft.completedAt)
    let input: RecordSetInput = key.kind == .prep
      ? .prep(fields) : .work(fields, toFailure: draft.toFailure)
    return enqueue(pending: pending, affecting: key.date) {
      let received = try await self.client.recordSet(input)
      guard key.kind == .work, draft.completed else { return received }
      return received.applyingTopWorkWeight(exerciseId: key.exerciseId)
    }
  }

  /// Gravar série é idempotente no servidor, que casa por sessão, exercício,
  /// tipo e índice, então reenviar a mesma marcação não duplica nada.
  func resend() async -> Bool {
    var allApplied = true
    for pending in pendingSets.values.sorted(by: { $0.revision < $1.revision }) {
      guard let current = pendingSets[pending.key], current.revision == pending.revision else {
        continue
      }
      switch await send(current).value {
      case .applied: continue
      // Uma falha de rede basta para saber que ela continua fora. Insistir no
      // resto da fila só gasta bateria.
      case .offline: return false
      // A recusa é de uma série só; as de trás seguem.
      case .refused: allApplied = false
      }
    }
    return allApplied
  }

  /// Desligado só nos testes, que chamam `resend()` na mão para contar tentativas.
  @ObservationIgnored var resendsAutomatically = true

  private func scheduleResend() {
    guard resendsAutomatically, resendTask == nil, !pendingSets.isEmpty else { return }
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
    guard await apply({ try await self.client.saveWorkout(input) }) else { return false }
    // O servidor que devolve o descanso salvo assume o lugar do aparelho. O
    // servidor antigo devolve nulo, e aí o valor local continua valendo.
    let saved = Dictionary(
      (dashboard?.weekPlan ?? []).flatMap(\.exercises).compactMap { exercise in
        exercise.restSeconds.map { (exercise.exerciseId, $0) }
      }, uniquingKeysWith: { first, _ in first })
    let echoed = restOverrides.filter { saved[$0.key] == $0.value }.map(\.key)
    if !echoed.isEmpty {
      for id in echoed { restOverrides.removeValue(forKey: id) }
      defaults.set(restOverrides, forKey: DefaultsKey.restOverrides)
    }
    return true
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
    // Trocar com série marcada deixaria as séries num treino que não é mais o
    // do dia. O menu já some nesse caso; aqui é a mesma regra na borda.
    guard dashboard?.hasMarkedSets != true else { return false }
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
    await enqueue(work).value == .applied
  }

  /// `date` é o dia que a escrita muda. Nulo muda o plano, e aí todo dia
  /// guardado fica velho.
  private func enqueue(
    pending: PendingSet? = nil, affecting date: CalendarDate? = nil,
    _ work: @escaping @Sendable () async throws -> Dashboard
  ) -> Task<MutationOutcome, Never> {
    cancelRead()
    if let date { invalidate(from: date) } else { invalidateAll() }
    let mutationSession = sessionID
    let previous = mutationTail
    let task = Task { @MainActor () -> MutationOutcome in
      _ = await previous?.value
      guard sessionID == mutationSession, !Task.isCancelled else { return .offline }
      do {
        let received = try await work()
        guard sessionID == mutationSession, !Task.isCancelled else { return .offline }
        forget(pending)
        if let date { invalidate(from: date) } else { invalidateAll() }
        remember(received)
        if received.date == selectedDate {
          acceptedDashboard = received
          phase = .ready
        }
        return .applied
      } catch {
        guard sessionID == mutationSession, !Task.isCancelled else { return .offline }
        if let date { invalidate(from: date) } else { invalidateAll() }
        guard !(error is CancellationError) else { return .offline }
        guard let pending else {
          handle(error)
          return Self.isOffline(error) ? .offline : .refused
        }
        return settle(pending, after: error)
      }
    }
    mutationTail = task
    return task
  }

  private static func isOffline(_ error: any Error) -> Bool {
    switch error {
    case APIError.http, APIError.decoding: false
    default: true
    }
  }

  /// O destino da série que não passou. Rede fora e sessão caída guardam sem
  /// limite. 4xx é recusa: o mesmo corpo nunca vai passar, então sai da fila na
  /// hora. 5xx volta a ser tentado até o limite, e aí sai também.
  private func settle(_ pending: PendingSet, after error: any Error) -> MutationOutcome {
    switch error {
    case APIError.http(let status, let message) where status < 500:
      drop(pending, reason: message)
      return .refused
    case APIError.http(_, let message):
      let failures = (pendingSets[pending.key]?.serverFailures ?? 0) + 1
      guard failures < Self.serverFailureLimit else {
        drop(pending, reason: message)
        return .refused
      }
      if pendingSets[pending.key]?.revision == pending.revision {
        pendingSets[pending.key]?.serverFailures = failures
      }
      hold(pending)
      return .refused
    case APIError.decoding:
      drop(pending, reason: "resposta inválida")
      return .refused
    case APIError.unauthorized:
      hold(pending)
      handle(error)
      return .offline
    default:
      hold(pending)
      return .offline
    }
  }

  private func drop(_ pending: PendingSet, reason: String) {
    guard pendingSets[pending.key]?.revision == pending.revision else { return }
    forget(pending)
    notice = "série não salva: \(reason)"
  }

  /// A marcação some da rede, não da tela. `waitingCount` diz quantas esperam,
  /// porque "sem conexão" sozinho parece série perdida, e não é mais.
  private func hold(_ pending: PendingSet) {
    guard pendingSets[pending.key]?.revision == pending.revision else { return }
    pendingSets[pending.key]?.failed = true
    saveQueue()
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
      endRest()
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

// MARK: - Descanso e encerramento

extension AcademiaStore {
  /// O descanso do exercício: o escolhido no aparelho, senão o do plano,
  /// senão o padrão.
  public func restSeconds(for exerciseId: String) -> Int {
    if let chosen = restOverrides[exerciseId] { return chosen }
    let fromSession = dashboard?.workout?.exercises.first { $0.id == exerciseId }?.restSeconds
    let fromPlan = dashboard?.weekPlan.lazy.flatMap(\.exercises)
      .first { $0.exerciseId == exerciseId }?.restSeconds
    return fromSession ?? fromPlan ?? defaultRestSeconds
  }

  /// O valor escolhido no aparelho, que o editor do plano mostra e manda salvar.
  func restOverride(for exerciseId: String) -> Int? { restOverrides[exerciseId] }

  public func setRestSeconds(_ seconds: Int, for exerciseId: String) {
    restOverrides[exerciseId] = seconds.clamped(to: Limits.restSeconds)
    defaults.set(restOverrides, forKey: DefaultsKey.restOverrides)
  }

  /// A última série valendo do treino não abre descanso: depois dela não há o
  /// que esperar.
  private func startRest(after key: SetKey) {
    guard let workout = dashboard?.workout,
      workout.exercises.contains(where: { !$0.sets.work.allSatisfy(\.isDone) })
    else {
      endRest()
      return
    }
    let seconds = TimeInterval(restSeconds(for: key.exerciseId))
    saveRest(RestState(key: key, startedAt: .now, seconds: seconds))
  }

  /// Mexe só na pausa corrente. O descanso do exercício muda pelo seletor do
  /// cartão ou pelo editor do plano.
  public func adjustRest(by delta: TimeInterval) {
    guard let current = rest else { return }
    saveRest(current.adjusted(by: delta))
  }

  public func endRest() {
    guard rest != nil else { return }
    saveRest(nil)
  }

  private func saveRest(_ value: RestState?) {
    rest = value
    if let value, let data = try? JSONEncoder().encode(value) {
      defaults.set(data, forKey: DefaultsKey.rest)
      restAlarm.schedule(at: value.endsAt, next: nextSet(after: value))
    } else {
      defaults.removeObject(forKey: DefaultsKey.rest)
      restAlarm.cancel()
    }
    scheduleRestExpiry()
  }

  /// A série que vem depois, procurada a partir do exercício que abriu o descanso.
  func nextSet(after rest: RestState) -> NextSet? {
    guard let workout = dashboard?.workout else { return nil }
    let index = workout.exercises.firstIndex { $0.id == rest.exerciseId } ?? 0
    return NextSet(from: index, in: workout)
  }

  /// Passado o fim, a barra fica uns segundos dizendo "vai" e sai sozinha.
  private func scheduleRestExpiry() {
    restExpiry?.cancel()
    guard let rest else { return }
    restExpiry = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(max(0, rest.expiresAt.timeIntervalSinceNow)))
      guard !Task.isCancelled, let self, self.rest == rest else { return }
      self.rest = nil
      self.defaults.removeObject(forKey: DefaultsKey.rest)
    }
  }

  private static func finishKey(_ workoutId: String, on date: CalendarDate) -> String {
    "\(date.iso) \(workoutId)"
  }

  /// Quando o treino do dia foi encerrado. Nulo enquanto ele está aberto.
  public func finishedAt(_ workoutId: String, on date: CalendarDate) -> Date? {
    finishedAt[Self.finishKey(workoutId, on: date)]
  }

  /// Quando o treino do dia começou, ou nulo se nenhuma série foi marcada.
  public func startedAt(_ workoutId: String, on date: CalendarDate) -> Date? {
    startedAt[Self.finishKey(workoutId, on: date)]
  }

  private func noteStart() {
    guard let data = dashboard, let workout = data.workout else { return }
    let key = Self.finishKey(workout.id, on: data.date)
    let known = startedAt[key]
    guard let anchor = WorkoutSessionTiming.anchor(workout, known: known), anchor != known
    else { return }
    startedAt[key] = anchor
    guard let encoded = try? JSONEncoder().encode(startedAt) else { return }
    defaults.set(encoded, forKey: DefaultsKey.started)
  }

  /// Encerra o treino aberto no painel. Para o relógio e o descanso.
  public func finishWorkout() {
    guard let data = dashboard, let workout = data.workout else { return }
    finishedAt[Self.finishKey(workout.id, on: data.date)] = .now
    saveFinished()
    endRest()
  }

  /// Uma série nova depois do "encerrar" reabre o treino: ele não tinha acabado.
  private func reopen(_ workoutId: String, on date: CalendarDate) {
    guard finishedAt.removeValue(forKey: Self.finishKey(workoutId, on: date)) != nil else { return }
    saveFinished()
  }

  private func saveFinished() {
    guard let data = try? JSONEncoder().encode(finishedAt) else { return }
    defaults.set(data, forKey: DefaultsKey.finished)
  }
}

extension Dashboard {
  /// O plano guarda a série valendo mais pesada feita no exercício nesta
  /// sessão: numa pirâmide 100/90/80 ele fica com 100. Desmarcar não mexe.
  func applyingTopWorkWeight(exerciseId: String) -> Dashboard {
    guard let top = workout?.topWorkWeight(exerciseId: exerciseId) else { return self }
    return applyingSharedExerciseWeight(top, exerciseId: exerciseId)
  }

  /// O dia já tem alguma série marcada, de aquecimento ou valendo.
  var hasMarkedSets: Bool {
    workout?.exercises.contains { exercise in
      exercise.sets.prep.contains(where: \.isDone) || exercise.sets.work.contains(where: \.isDone)
    } ?? false
  }
}
