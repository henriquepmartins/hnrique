import Foundation

// MARK: - Treino

public enum LanguageDrillKind: String, Codable, Hashable, Sendable, CaseIterable {
  case listen, shadow, produce, review

  public var title: String {
    switch self {
    case .listen: "ouvir"
    case .shadow: "sombrear"
    case .produce: "produzir"
    case .review: "revisar"
    }
  }

  public var minutes: Int {
    switch self {
    case .listen: 5
    case .shadow: 7
    case .produce: 8
    case .review: 5
    }
  }

  public var needsMic: Bool { self == .shadow }
  public var needsAI: Bool { self == .produce }
}

public struct LanguageDrill: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var kind: LanguageDrillKind
  public var promptDE: String
  public var glossPT: String
  public var expectedDE: String?
  public var dueAt: Date?
  public var clientDrillId: UUID

  public init(
    id: String, kind: LanguageDrillKind, promptDE: String, glossPT: String,
    expectedDE: String? = nil, dueAt: Date? = nil, clientDrillId: UUID = UUID()
  ) {
    self.id = id
    self.kind = kind
    self.promptDE = promptDE
    self.glossPT = glossPT
    self.expectedDE = expectedDE
    self.dueAt = dueAt
    self.clientDrillId = clientDrillId
  }

  private enum CodingKeys: String, CodingKey {
    case id, kind, promptDE, glossPT, expectedDE, dueAt, clientDrillId
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    kind = try container.decode(LanguageDrillKind.self, forKey: .kind)
    promptDE = try container.decode(String.self, forKey: .promptDE)
    glossPT = try container.decode(String.self, forKey: .glossPT)
    expectedDE = try container.decodeIfPresent(String.self, forKey: .expectedDE)
    dueAt = try container.decodeIfPresent(Date.self, forKey: .dueAt)
    clientDrillId = try container.decodeIfPresent(UUID.self, forKey: .clientDrillId) ?? UUID()
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(kind, forKey: .kind)
    try container.encode(promptDE, forKey: .promptDE)
    try container.encode(glossPT, forKey: .glossPT)
    try container.encodeIfPresent(expectedDE, forKey: .expectedDE)
    try container.encodeIfPresent(dueAt, forKey: .dueAt)
    try container.encode(clientDrillId, forKey: .clientDrillId)
  }
}

public struct LanguageAttempt: Hashable, Sendable, Encodable {
  public var attemptId: UUID
  public var drillId: String
  public var text: String
  public var micUsed: Bool

  public init(attemptId: UUID = UUID(), drillId: String, text: String, micUsed: Bool) {
    self.attemptId = attemptId
    self.drillId = drillId
    self.text = text
    self.micUsed = micUsed
  }
}

// MARK: - Sessão

public enum LanguageStep: String, Codable, Hashable, Sendable {
  case listen, respond
}

public enum LanguageSessionAction: Hashable, Sendable {
  case play
  case armMic(Bool)
  case submit
  case advance(total: Int)
  case failed
}

public enum LanguageSessionState: Hashable, Sendable {
  case empty
  case drill(index: Int, step: LanguageStep, micArmed: Bool, played: Bool, failed: Bool)
  case done

  public func reduce(
    _ action: LanguageSessionAction, kind: LanguageDrillKind, total: Int
  ) -> LanguageSessionState {
    guard case .drill(let index, let step, let micArmed, let played, let failed) = self else {
      return self
    }
    switch action {
    case .play:
      // Tocar e gravar nunca acontecem juntos: o play desarma o microfone e a
      // camada de fala para a síntese antes de armar, então falar não vaza para
      // a gravação.
      return .drill(index: index, step: step, micArmed: false, played: true, failed: failed)
    case .armMic(let on):
      guard on else {
        return .drill(index: index, step: step, micArmed: false, played: played, failed: failed)
      }
      guard kind.needsMic else { return .drill(index: index, step: step, micArmed: false, played: played, failed: failed) }
      return .drill(index: index, step: step, micArmed: true, played: played, failed: failed)
    case .submit:
      guard step == .listen else { return self }
      return .drill(index: index, step: .respond, micArmed: micArmed, played: played, failed: failed)
    case .advance:
      let next = index + 1
      guard next < total else { return .done }
      return .drill(index: next, step: .listen, micArmed: false, played: false, failed: false)
    case .failed:
      return .drill(index: index, step: step, micArmed: micArmed, played: played, failed: true)
    }
  }
}

// MARK: - Progresso

public struct LanguageProgress: Hashable, Sendable {
  public var figure: StreakFigure
  public var days: [StreakDay]
  public var isTodayDone: Bool

  public init(doneDates: [CalendarDate], streakCount: Int, target: Int?, today: CalendarDate = .today) {
    // Dia do aparelho, como a academia, e não o de Fortaleza dos estudos: a
    // sequência de idiomas conta o dia em que o treino saiu no telefone. A
    // divergência com StudyFormat é proposital e está anotada aqui para ninguém
    // "corrigir" para Fortaleza sem mudar os testes.
    let done = Set(doneDates)
    let days = (0..<7).map { offset -> StreakDay in
      let date = today.adding(days: offset - 6)
      let state: StreakDayState =
        if done.contains(date) {
          .done
        } else if date < today {
          .missed
        } else {
          .planned
        }
      return StreakDay(date: date, state: state)
    }
    self.days = days
    self.figure = StreakFigure(count: streakCount, target: target)
    self.isTodayDone = days[6].state == .done
  }
}

// MARK: - Respostas

/// O pacote da rotina. O servidor ainda não tem rota de fila nem de progresso
/// para idiomas, então `routine/get` devolve os treinos, a fila de revisão e o
/// progresso juntos, como o overview dos estudos. As três abas do store são
/// recortes deste pacote.
public struct LanguageRoutineBundle: Codable, Hashable, Sendable {
  public var routine: LanguageRoutine
  public var queue: LanguageReviewQueue
  public var progress: LanguageProgressPayload

  public init(routine: LanguageRoutine, queue: LanguageReviewQueue, progress: LanguageProgressPayload) {
    self.routine = routine
    self.queue = queue
    self.progress = progress
  }
}

public struct LanguageRoutine: Codable, Hashable, Sendable {
  public var drills: [LanguageDrill]

  public init(drills: [LanguageDrill]) {
    self.drills = drills
  }
}

public struct LanguageReviewQueue: Codable, Hashable, Sendable {
  public var drills: [LanguageDrill]

  public init(drills: [LanguageDrill]) {
    self.drills = drills
  }
}

public struct LanguageProgressPayload: Codable, Hashable, Sendable {
  public var doneDates: [CalendarDate]
  public var streakCount: Int
  public var target: Int?

  public init(doneDates: [CalendarDate], streakCount: Int, target: Int? = nil) {
    self.doneDates = doneDates
    self.streakCount = streakCount
    self.target = target
  }
}

public struct LanguageCorrection: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var correctionPT: String
  public var fixedDE: String
  public var score: Int
  public var dueAt: Date
  public var interval: Int

  public init(
    id: String, correctionPT: String, fixedDE: String, score: Int, dueAt: Date, interval: Int
  ) {
    self.id = id
    self.correctionPT = correctionPT
    self.fixedDE = fixedDE
    self.score = score
    self.dueAt = dueAt
    self.interval = interval
  }
}

public struct LanguageCompleteResult: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var dueAt: Date
  public var interval: Int

  public init(id: String, dueAt: Date, interval: Int) {
    self.id = id
    self.dueAt = dueAt
    self.interval = interval
  }
}

// MARK: - Entradas

public struct LanguageCompleteInput: Hashable, Sendable, Encodable {
  public var attemptId: UUID
  public var drillId: String
  public var text: String
  public var micUsed: Bool
  /// Só a revisão manda nota; a rotina manda texto e microfone. Ausente sai do
  /// corpo em vez de ir nulo, como o resto das entradas do app.
  public var rating: FlashcardRating?
  /// O dia do aparelho. O servidor contava pelo dia em UTC, e o treino feito
  /// às 22 h de Fortaleza caía no dia seguinte.
  public var date: CalendarDate

  public init(
    attemptId: UUID = UUID(), drillId: String, text: String, micUsed: Bool,
    rating: FlashcardRating? = nil, date: CalendarDate = .today
  ) {
    self.attemptId = attemptId
    self.drillId = drillId
    self.text = text
    self.micUsed = micUsed
    self.rating = rating
    self.date = date
  }

  private enum CodingKeys: String, CodingKey {
    case attemptId, drillId, text, micUsed, rating, date
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(attemptId, forKey: .attemptId)
    try container.encode(drillId, forKey: .drillId)
    try container.encode(text, forKey: .text)
    try container.encode(micUsed, forKey: .micUsed)
    try container.encodeIfPresent(rating, forKey: .rating)
    try container.encode(date, forKey: .date)
  }
}

public struct LanguageCorrectionInput: Hashable, Sendable, Encodable {
  public var attemptId: UUID?
  public var drillId: String
  public var text: String

  public init(attemptId: UUID? = nil, drillId: String, text: String) {
    self.attemptId = attemptId
    self.drillId = drillId
    self.text = text
  }

  private enum CodingKeys: String, CodingKey {
    case attemptId, drillId, text
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(attemptId, forKey: .attemptId)
    try container.encode(drillId, forKey: .drillId)
    try container.encode(text, forKey: .text)
  }
}

public struct LanguageFinishInput: Hashable, Sendable, Encodable {
  public var drillIds: [String]
  /// O dia do aparelho, pelo mesmo motivo do treino concluído.
  public var date: CalendarDate

  public init(drillIds: [String], date: CalendarDate = .today) {
    self.drillIds = drillIds
    self.date = date
  }
}

// MARK: - Degradação sem IA

extension FlashcardRating {
  /// O intervalo local quando a correção da IA cai. A sessão avança com a
  /// autoavaliação e o dia continua valendo; a correção real entra em silêncio
  /// depois, sem pedir nada de quem está treinando.
  public var localInterval: Int {
    switch self {
    case .errei: 0
    case .dificil: 1
    case .facil: 3
    }
  }

  public var localHint: String {
    let interval = localInterval
    if interval <= 0 { return "hoje" }
    return interval == 1 ? "amanhã" : "\(interval) dias"
  }
}
