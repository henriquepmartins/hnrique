import Foundation

public enum APIError: Error, Equatable, Sendable {
  case unauthorized
  case http(status: Int, message: String)
  case transport(host: String, detail: String)
  case decoding(String)

  public var message: String {
    switch self {
    case .unauthorized: "sessão expirou"
    case .http(_, let message): message
    case .transport(let host, _): "sem conexão com \(host)"
    case .decoding: "resposta inválida"
    }
  }
}

/// As rotas ficam nomeadas em um só lugar. O servidor declara exatamente estes
/// caminhos, então uma divergência aparece aqui e não espalhada pelas telas.
public enum Route: String, Sendable {
  case completeOnboarding = "/api/v1/onboarding/complete"
  case dashboard = "/api/v1/dashboard/get"
  case recordSet = "/api/v1/workout/record-set"
  case setCount = "/api/v1/workout/set-count"
  case addExercise = "/api/v1/workout/add-exercise"
  case removeExercise = "/api/v1/workout/remove-exercise"
  case setNote = "/api/v1/workout/set-note"
  case saveWorkout = "/api/v1/plan/save-workout"
  case deleteWorkout = "/api/v1/plan/delete-workout"
  case swapDay = "/api/v1/plan/swap-day"
  case setStrengthGoal = "/api/v1/goal/set-strength"
  case setStreakGoal = "/api/v1/goal/set-streak"
  case addMeasurement = "/api/v1/measurement/add"
  case attendance = "/api/v1/training/attendance"
  case signIn = "/api/auth/sign-in/username"
  case signOut = "/api/auth/sign-out"
  case studyOverview = "/api/v1/estudos/overview/get"
  case studySubjectList = "/api/v1/estudos/subject/list"
  case studySubjectGet = "/api/v1/estudos/subject/get"
  case studyAssignmentList = "/api/v1/estudos/assignment/list"
  case studyAssignmentSetStatus = "/api/v1/estudos/assignment/set-status"
  case studyNoteList = "/api/v1/estudos/note/list"
  case studyNoteGet = "/api/v1/estudos/note/get"
  case studyNoteSave = "/api/v1/estudos/note/save"
  case studySessionStart = "/api/v1/estudos/session/start"
  case studySessionFinish = "/api/v1/estudos/session/finish"
  case studyReviewQueue = "/api/v1/estudos/review/queue"
  case studyReviewGrade = "/api/v1/estudos/review/grade"
  case studyNotebookList = "/api/v1/estudos/notebook/list"
  case studyNotebookGet = "/api/v1/estudos/notebook/get"
  case studyNotebookSave = "/api/v1/estudos/notebook/save"
  case studyNotebookRemove = "/api/v1/estudos/notebook/remove"
  case idiomasRoutineGet = "/api/v1/idiomas/routine/get"
  case idiomasDrillComplete = "/api/v1/idiomas/drill/complete"
  case idiomasCorrectionGrade = "/api/v1/idiomas/correction/grade"
  case idiomasSessionFinish = "/api/v1/idiomas/session/finish"
  case focoList = "/api/v1/foco/list"
  case focoSave = "/api/v1/foco/save"
  case focoRemove = "/api/v1/foco/remove"
  case focoGoal = "/api/v1/foco/goal"
}

public actor APIClient {
  private let baseURL: URL
  private let session: URLSession
  private let tokenStore: any TokenStore
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(
    baseURL: URL, tokenStore: any TokenStore, session: URLSession? = nil
  ) {
    self.baseURL = baseURL
    self.tokenStore = tokenStore
    self.session = session ?? Self.makeSession()
    self.encoder = .henrique()
    self.decoder = .henrique()
  }

  /// O pote de cookies compartilhado guardaria a sessão por fora do chaveiro, e
  /// aí sair da conta não sairia de verdade: o cookie continuaria sendo enviado.
  /// Desligando o pote, o token guardado é a única fonte da sessão.
  private static func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    configuration.httpCookieStorage = nil
    return URLSession(configuration: configuration)
  }

  public var isSignedIn: Bool { tokenStore.read() != nil }

  public func signIn(username: String, password: String) async throws {
    struct Body: Encodable {
      let username: String
      let password: String
    }
    let (_, response) = try await send(.signIn, body: Body(username: username, password: password))
    guard let cookie = Self.sessionCookie(from: response, url: baseURL) else {
      throw APIError.http(status: response.statusCode, message: "login falhou")
    }
    tokenStore.write(cookie)
  }

  public func signOut() async {
    _ = try? await send(.signOut, body: EmptyBody())
    tokenStore.write(nil)
  }

  public func dashboard(on date: CalendarDate) async throws -> Dashboard {
    try await call(.dashboard, body: DateInput(date: date))
  }

  public func recordSet(_ input: RecordSetInput) async throws -> Dashboard {
    try await call(.recordSet, body: input)
  }

  public func setCount(_ input: SetCountInput) async throws -> Dashboard {
    try await call(.setCount, body: input)
  }

  public func addExercise(_ input: AddSessionExerciseInput) async throws -> Dashboard {
    try await call(.addExercise, body: input)
  }

  public func removeExercise(_ input: RemoveSessionExerciseInput) async throws -> Dashboard {
    try await call(.removeExercise, body: input)
  }

  public func setNote(_ input: SetExerciseNoteInput) async throws -> Dashboard {
    try await call(.setNote, body: input)
  }

  public func saveWorkout(_ input: SaveWorkoutInput) async throws -> Dashboard {
    try await call(.saveWorkout, body: input)
  }

  public func deleteWorkout(_ input: DeleteWorkoutInput) async throws -> Dashboard {
    try await call(.deleteWorkout, body: input)
  }

  public func swapDay(_ input: SwapDayInput) async throws -> Dashboard {
    try await call(.swapDay, body: input)
  }

  public func setStrengthGoal(_ input: SetStrengthGoalInput) async throws -> Dashboard {
    try await call(.setStrengthGoal, body: input)
  }

  public func setStreakGoal(_ input: SetStreakGoalInput) async throws -> Dashboard {
    try await call(.setStreakGoal, body: input)
  }

  public func addMeasurement(_ input: AddMeasurementInput) async throws -> Dashboard {
    try await call(.addMeasurement, body: input)
  }

  /// Só os dias com ao menos uma série valendo feita, em ordem crescente. O
  /// servidor aceita no máximo 400 dias por chamada.
  public func attendance(_ input: AttendanceRangeInput) async throws -> [AttendanceDay] {
    struct Response: Decodable {
      let days: [AttendanceDay]
    }
    let response: Response = try await call(.attendance, body: input)
    return response.days
  }

  public func completeOnboarding() async throws {
    _ = try await send(.completeOnboarding, body: EmptyBody())
  }

  // MARK: Estudos

  public func studyOverview(on date: CalendarDate) async throws -> StudyOverview {
    try await call(.studyOverview, body: DateInput(date: date))
  }

  public func studySubjects() async throws -> [StudySubject] {
    try await call(.studySubjectList, body: EmptyBody())
  }

  /// O servidor devolve `null` quando a matéria não existe, e `Optional`
  /// decodifica esse nulo direto.
  public func studySubject(id: String) async throws -> SubjectDetail? {
    try await call(.studySubjectGet, body: IdInput(id: id))
  }

  public func studyAssignments() async throws -> [AssignmentGroup] {
    try await call(.studyAssignmentList, body: AssignmentListInput())
  }

  public func setAssignmentStatus(_ input: SetAssignmentStatusInput) async throws
    -> StudyAssignment
  {
    try await call(.studyAssignmentSetStatus, body: input)
  }

  public func studyNotes(subjectId: String? = nil) async throws -> [NoteSummary] {
    try await call(.studyNoteList, body: NoteListInput(subjectId: subjectId))
  }

  public func studyNote(path: String) async throws -> StudyNote? {
    try await call(.studyNoteGet, body: NotePathInput(path: path))
  }

  public func saveStudyNote(_ input: SaveNoteInput) async throws -> StudyNote {
    try await call(.studyNoteSave, body: input)
  }

  public func startStudySession(_ input: StartSessionInput) async throws -> StudySession {
    try await call(.studySessionStart, body: input)
  }

  public func finishStudySession(_ input: FinishSessionInput) async throws -> StudySession {
    try await call(.studySessionFinish, body: input)
  }

  public func reviewQueue() async throws -> ReviewQueue {
    try await call(.studyReviewQueue, body: EmptyBody())
  }

  public func gradeFlashcard(_ input: GradeFlashcardInput) async throws -> GradeResult {
    try await call(.studyReviewGrade, body: input)
  }

  public func notebooks() async throws -> [Notebook] {
    try await call(.studyNotebookList, body: EmptyBody())
  }

  public func notebookPage(id: String) async throws -> NotebookPage? {
    try await call(.studyNotebookGet, body: IdInput(id: id))
  }

  public func saveNotebookPage(_ input: SaveNotebookPageInput) async throws -> NotebookPage {
    try await call(.studyNotebookSave, body: input)
  }

  public func removeNotebookPage(id: String) async throws {
    _ = try await send(.studyNotebookRemove, body: IdInput(id: id))
  }

  // MARK: Idiomas

  public func idiomasRoutine() async throws -> LanguageRoutineBundle {
    try await call(.idiomasRoutineGet, body: EmptyBody())
  }

  public func completeLanguageDrill(_ input: LanguageCompleteInput) async throws
    -> LanguageCompleteResult
  {
    try await call(.idiomasDrillComplete, body: input)
  }

  public func gradeLanguageCorrection(_ input: LanguageCorrectionInput) async throws
    -> LanguageCorrection
  {
    try await call(.idiomasCorrectionGrade, body: input)
  }

  public func finishLanguageSession(_ input: LanguageFinishInput) async throws
    -> LanguageProgressPayload
  {
    try await call(.idiomasSessionFinish, body: input)
  }

  // MARK: Foco

  public func focoList() async throws -> FocoListResponse {
    try await call(.focoList, body: EmptyBody())
  }

  /// Devolve só os ids que agora existem para este usuário. Um id que já era de
  /// outro usuário é ignorado pelo servidor e não volta na lista.
  public func focoSave(_ entries: [FocoEntry]) async throws -> [UUID] {
    let response: FocoSaveResponse = try await call(.focoSave, body: FocoSaveInput(entries: entries))
    return response.saved
  }

  public func focoRemove(ids: [UUID]) async throws -> Int {
    let response: FocoRemoveResponse = try await call(.focoRemove, body: FocoRemoveInput(ids: ids))
    return response.removed
  }

  public func focoSetGoal(minutes: Int) async throws -> Int {
    let response: FocoGoalResponse = try await call(.focoGoal, body: FocoGoalInput(minutes: minutes))
    return response.dailyGoalMinutes
  }

  private struct EmptyBody: Encodable {}

  private func call<Body: Encodable, Value: Decodable>(_ route: Route, body: Body) async throws
    -> Value
  {
    let (data, _) = try await send(route, body: body)
    do {
      return try decoder.decode(Value.self, from: data)
    } catch {
      throw APIError.decoding(String(describing: error))
    }
  }

  private func send<Body: Encodable>(_ route: Route, body: Body) async throws -> (
    Data, HTTPURLResponse
  ) {
    var request = URLRequest(url: baseURL.appending(path: route.rawValue))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let token = tokenStore.read() {
      request.setValue(token, forHTTPHeaderField: "Cookie")
    }
    request.httpBody = try encoder.encode(body)

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
        throw CancellationError()
      }
      throw APIError.transport(host: Self.host(of: baseURL), detail: error.localizedDescription)
    }
    try Task.checkCancellation()
    guard let http = response as? HTTPURLResponse else {
      throw APIError.transport(host: Self.host(of: baseURL), detail: "resposta sem status")
    }
    if http.statusCode == 401 {
      tokenStore.write(nil)
      throw APIError.unauthorized
    }
    guard (200..<300).contains(http.statusCode) else {
      throw APIError.http(status: http.statusCode, message: Self.serverMessage(from: data))
    }
    return (data, http)
  }

  /// O endereço aparece no erro porque o modo de falha mais comum é o app
  /// apontar para um servidor que não está rodando. Sem o endereço, "não
  /// consegui falar com o servidor" não diz com qual.
  static func host(of url: URL) -> String {
    guard let host = url.host() else { return url.absoluteString }
    guard let port = url.port else { return host }
    return "\(host):\(port)"
  }

  /// O corpo do 400 traz `data.issues`, a lista do zod com o campo e o motivo.
  /// A frase nomeia o primeiro campo pelo nome que a tela usa, porque
  /// "input validation failed" não diz o que corrigir.
  static func serverMessage(from data: Data) -> String {
    struct Failure: Decodable {
      let message: String?
      let error: String?
      let data: Payload?
      struct Payload: Decodable { let issues: [ValidationIssue]? }
    }
    guard let failure = try? JSONDecoder().decode(Failure.self, from: data) else {
      return "servidor recusou"
    }
    if let issue = failure.data?.issues?.first { return issue.sentence }
    return failure.message ?? failure.error ?? "servidor recusou"
  }

  static func sessionCookie(from response: HTTPURLResponse, url: URL) -> String? {
    let headers = response.allHeaderFields as? [String: String] ?? [:]
    let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
    let session = cookies.filter { $0.name.contains("session_token") }
    guard !session.isEmpty else { return nil }
    return session.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
  }
}

/// Um item de `data.issues` no formato do zod 4: `path` mistura nomes de campo
/// e índices de array, `code` diz o tipo de falha e `minimum`/`maximum` trazem
/// o limite quando a falha é de faixa.
struct ValidationIssue: Decodable {
  enum PathElement: Decodable {
    case key(String)
    case index(Int)

    init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let index = try? container.decode(Int.self) {
        self = .index(index)
      } else {
        self = .key(try container.decode(String.self))
      }
    }
  }

  var path: [PathElement]
  var message: String
  var code: String?
  var origin: String?
  var minimum: Double?
  var maximum: Double?

  /// O nome técnico do campo e a palavra que a tela mostra para ele.
  static let fieldLabels: [String: String] = [
    "date": "data",
    "workoutTemplateId": "treino",
    "exerciseId": "exercício",
    "setIndex": "série",
    "weightKg": "peso",
    "reps": "repetições",
    "completed": "concluída",
    "toFailure": "falha",
    "bodyFatPercent": "gordura corporal",
    "waistCm": "cintura",
    "chestCm": "peito",
    "armCm": "braço",
    "thighCm": "coxa",
    "weekdays": "dias",
    "name": "nome",
    "focus": "foco",
    "estimatedMinutes": "minutos",
    "exercises": "exercícios",
    "prepSets": "aquecimento",
    "workSets": "séries valendo",
    "repsMin": "reps mín.",
    "repsMax": "reps máx.",
    "workToFailure": "até a falha",
    "startingWeightKg": "carga",
    "muscleGroup": "grupo muscular",
    "equipment": "equipamento",
    "imageUrl": "imagem",
    "targetValue": "meta",
    "target": "alvo",
    "kind": "tipo",
  ]

  var field: String? {
    for element in path.reversed() {
      if case .key(let key) = element { return Self.fieldLabels[key] ?? key }
    }
    return nil
  }

  var reason: String {
    let unit = origin == "string" ? " caracteres" : origin == "array" ? " itens" : ""
    switch (code, minimum, maximum) {
    case ("too_small", let bound?, _): return "no mínimo \(Self.number(bound))\(unit)"
    case ("too_big", _, let bound?): return "no máximo \(Self.number(bound))\(unit)"
    default: return message.lowercased()
    }
  }

  var sentence: String {
    guard let field else { return reason }
    return "\(field): \(reason)"
  }

  private static func number(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "pt_BR")))
  }
}
