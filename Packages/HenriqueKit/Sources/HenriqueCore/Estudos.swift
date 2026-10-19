import Foundation

// MARK: - JSON solto

/// Um valor JSON qualquer. O corpo da página de caderno é escrito pelo BlockNote
/// no web e o app não entende o formato dos blocos, então guarda o conteúdo
/// inteiro e devolve intacto no próximo save. Sem isto, salvar o título pelo
/// telefone apagaria a formatação do texto.
public enum JSONValue: Codable, Hashable, Sendable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: container.codingPath,
          debugDescription: "valor JSON fora dos tipos conhecidos"))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }

  public subscript(key: String) -> JSONValue? {
    guard case .object(let fields) = self else { return nil }
    return fields[key]
  }

  public var stringValue: String? {
    guard case .string(let value) = self else { return nil }
    return value
  }

  public var numberValue: Double? {
    guard case .number(let value) = self else { return nil }
    return value
  }

  public var intValue: Int? {
    guard case .number(let value) = self else { return nil }
    return Int(exactly: value.rounded())
  }

  public var boolValue: Bool? {
    guard case .bool(let value) = self else { return nil }
    return value
  }

  public var arrayValue: [JSONValue]? {
    guard case .array(let value) = self else { return nil }
    return value
  }

  public var objectValue: [String: JSONValue]? {
    guard case .object(let value) = self else { return nil }
    return value
  }
}

/// A leitura de um bloco do BlockNote. Só serve para desenhar o corpo da página
/// na tela; quem edita o texto continua sendo o web, e o app reenvia o
/// `JSONValue` original.
public struct NotebookBlock: Identifiable, Hashable, Sendable {
  public enum Kind: String, Hashable, Sendable, CaseIterable {
    case paragraph
    case heading
    case bulletListItem
    case numberedListItem
    case checkListItem
    case codeBlock
    case quote
    case other
  }

  public let id: String
  public let type: Kind
  public let level: Int?
  public let checked: Bool?
  public let text: String
  public let children: [NotebookBlock]

  public init(
    id: String, type: Kind, level: Int?, checked: Bool?, text: String, children: [NotebookBlock]
  ) {
    self.id = id
    self.type = type
    self.level = level
    self.checked = checked
    self.text = text
    self.children = children
  }

  /// `fallbackID` cobre o bloco sem `id`. A posição serve porque a lista só é
  /// redesenhada quando a página inteira troca.
  public init?(_ value: JSONValue, fallbackID: String) {
    guard case .object = value else { return nil }
    let props = value["props"]
    self.init(
      id: value["id"]?.stringValue ?? fallbackID,
      type: Kind(rawValue: value["type"]?.stringValue ?? "") ?? .other,
      level: props?["level"]?.intValue,
      checked: props?["checked"]?.boolValue,
      text: Self.plainText(value["content"]),
      children: Self.blocks(from: value["children"]?.arrayValue ?? [], prefix: fallbackID))
  }

  public static func blocks(from content: [JSONValue], prefix: String = "bloco") -> [NotebookBlock] {
    content.enumerated().compactMap { NotebookBlock($1, fallbackID: "\(prefix).\($0)") }
  }

  private static func plainText(_ content: JSONValue?) -> String {
    guard let items = content?.arrayValue else { return content?.stringValue ?? "" }
    return items.compactMap { $0["text"]?.stringValue }.joined()
  }
}

// MARK: - Matérias e materiais

public struct StudySubject: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var name: String
  public var color: String
  public var code: String?
  public var semester: Int?

  public init(id: String, name: String, color: String, code: String? = nil, semester: Int? = nil) {
    self.id = id
    self.name = name
    self.color = color
    self.code = code
    self.semester = semester
  }
}

public enum MaterialKind: String, Codable, Hashable, Sendable, CaseIterable {
  case slide, pdf, link
}

public struct StudyMaterial: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var subjectId: String
  public var kind: MaterialKind
  public var lessonNumber: Int?
  public var title: String
  public var source: String
  public var storageKey: String?
  public var url: String?
  public var page: Int

  public init(
    id: String, subjectId: String, kind: MaterialKind, lessonNumber: Int? = nil, title: String,
    source: String, storageKey: String? = nil, url: String? = nil, page: Int
  ) {
    self.id = id
    self.subjectId = subjectId
    self.kind = kind
    self.lessonNumber = lessonNumber
    self.title = title
    self.source = source
    self.storageKey = storageKey
    self.url = url
    self.page = page
  }
}

// MARK: - Entregas

/// Os três estados que o banco aceita. `next` é o que o toque no quadradinho
/// faz, e é por isso que "em andamento" também vai para "feito".
public enum AssignmentStatus: String, Codable, Hashable, Sendable, CaseIterable {
  case open
  case in_progress
  case done

  public var next: AssignmentStatus {
    switch self {
    case .open, .in_progress: .done
    case .done: .open
    }
  }
}

public struct StudyAssignment: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var subjectId: String?
  public var subjectName: String?
  public var subjectColor: String?
  public var title: String
  public var dueAt: Date
  public var status: AssignmentStatus
  public var source: String
  public var url: String?

  public init(
    id: String, subjectId: String? = nil, subjectName: String? = nil, subjectColor: String? = nil,
    title: String, dueAt: Date, status: AssignmentStatus, source: String, url: String? = nil
  ) {
    self.id = id
    self.subjectId = subjectId
    self.subjectName = subjectName
    self.subjectColor = subjectColor
    self.title = title
    self.dueAt = dueAt
    self.status = status
    self.source = source
    self.url = url
  }
}

public struct AssignmentGroup: Codable, Hashable, Sendable, Identifiable {
  public var date: CalendarDate
  public var items: [StudyAssignment]

  public var id: CalendarDate { date }

  public init(date: CalendarDate, items: [StudyAssignment]) {
    self.date = date
    self.items = items
  }
}

// MARK: - Notas

public struct NoteSummary: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var path: String
  public var title: String
  public var subjectId: String?
  public var tags: [String]
  public var updatedAt: Date

  public init(
    id: String, path: String, title: String, subjectId: String? = nil, tags: [String],
    updatedAt: Date
  ) {
    self.id = id
    self.path = path
    self.title = title
    self.subjectId = subjectId
    self.tags = tags
    self.updatedAt = updatedAt
  }
}

public struct StudyNote: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var path: String
  public var title: String
  public var subjectId: String?
  public var tags: [String]
  public var updatedAt: Date
  public var body: String
  public var materialId: String?
  public var links: [String]

  public init(
    id: String, path: String, title: String, subjectId: String? = nil, tags: [String],
    updatedAt: Date, body: String, materialId: String? = nil, links: [String]
  ) {
    self.id = id
    self.path = path
    self.title = title
    self.subjectId = subjectId
    self.tags = tags
    self.updatedAt = updatedAt
    self.body = body
    self.materialId = materialId
    self.links = links
  }
}

// MARK: - Cartões, sessões e sincronização

public struct Flashcard: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var noteId: String
  public var front: String
  public var back: String
  public var dueAt: Date
  public var subjectId: String?
  public var subjectName: String?
  public var subjectColor: String?

  public init(
    id: String, noteId: String, front: String, back: String, dueAt: Date, subjectId: String? = nil,
    subjectName: String? = nil, subjectColor: String? = nil
  ) {
    self.id = id
    self.noteId = noteId
    self.front = front
    self.back = back
    self.dueAt = dueAt
    self.subjectId = subjectId
    self.subjectName = subjectName
    self.subjectColor = subjectColor
  }
}

public struct StudySession: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var subjectId: String?
  public var materialId: String?
  public var startedAt: Date
  public var endedAt: Date?
  public var completedMinutes: Int

  public init(
    id: String, subjectId: String? = nil, materialId: String? = nil, startedAt: Date,
    endedAt: Date? = nil, completedMinutes: Int
  ) {
    self.id = id
    self.subjectId = subjectId
    self.materialId = materialId
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.completedMinutes = completedMinutes
  }
}

public struct SyncLog: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var source: String
  public var status: String
  public var createdCount: Int
  public var existingCount: Int
  public var completedAt: Date

  public init(
    id: String, source: String, status: String, createdCount: Int, existingCount: Int,
    completedAt: Date
  ) {
    self.id = id
    self.source = source
    self.status = status
    self.createdCount = createdCount
    self.existingCount = existingCount
    self.completedAt = completedAt
  }
}

// MARK: - Respostas compostas

public struct StudyOverview: Codable, Hashable, Sendable {
  public var date: CalendarDate
  public var subjects: [StudySubject]
  public var dueSoon: [StudyAssignment]
  public var reviewCount: Int
  public var weekMinutes: Int
  public var lastSession: StudySession?
  public var lastSync: SyncLog?

  public init(
    date: CalendarDate, subjects: [StudySubject], dueSoon: [StudyAssignment], reviewCount: Int,
    weekMinutes: Int, lastSession: StudySession? = nil, lastSync: SyncLog? = nil
  ) {
    self.date = date
    self.subjects = subjects
    self.dueSoon = dueSoon
    self.reviewCount = reviewCount
    self.weekMinutes = weekMinutes
    self.lastSession = lastSession
    self.lastSync = lastSync
  }
}

public struct SubjectDetail: Codable, Hashable, Sendable, Identifiable {
  public var subject: StudySubject
  public var materials: [StudyMaterial]
  public var assignments: [StudyAssignment]
  public var notes: [NoteSummary]

  public var id: String { subject.id }

  public init(
    subject: StudySubject, materials: [StudyMaterial], assignments: [StudyAssignment],
    notes: [NoteSummary]
  ) {
    self.subject = subject
    self.materials = materials
    self.assignments = assignments
    self.notes = notes
  }
}

public struct SubjectCount: Codable, Hashable, Sendable, Identifiable {
  public var subjectId: String
  public var name: String
  public var color: String
  public var count: Int

  public var id: String { subjectId }

  public init(subjectId: String, name: String, color: String, count: Int) {
    self.subjectId = subjectId
    self.name = name
    self.color = color
    self.count = count
  }
}

public struct ReviewQueue: Codable, Hashable, Sendable {
  public var cards: [Flashcard]
  public var bySubject: [SubjectCount]

  public init(cards: [Flashcard], bySubject: [SubjectCount]) {
    self.cards = cards
    self.bySubject = bySubject
  }
}

// MARK: - Caderno

public struct NotebookPageSummary: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var subjectId: String
  public var title: String
  public var position: Int
  public var updatedAt: Date

  /// A página nasce sem título, como no web. O rótulo entra só na hora de
  /// desenhar para o campo de edição continuar vazio.
  public var displayTitle: String {
    let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.isEmpty ? "sem título" : clean
  }

  public init(id: String, subjectId: String, title: String, position: Int, updatedAt: Date) {
    self.id = id
    self.subjectId = subjectId
    self.title = title
    self.position = position
    self.updatedAt = updatedAt
  }
}

public struct NotebookPage: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var subjectId: String
  public var title: String
  public var position: Int
  public var updatedAt: Date
  public var content: [JSONValue]
  public var createdAt: Date

  public var summary: NotebookPageSummary {
    NotebookPageSummary(
      id: id, subjectId: subjectId, title: title, position: position, updatedAt: updatedAt)
  }

  public var blocks: [NotebookBlock] { NotebookBlock.blocks(from: content) }

  public var displayTitle: String { summary.displayTitle }

  public init(
    id: String, subjectId: String, title: String, position: Int, updatedAt: Date,
    content: [JSONValue], createdAt: Date
  ) {
    self.id = id
    self.subjectId = subjectId
    self.title = title
    self.position = position
    self.updatedAt = updatedAt
    self.content = content
    self.createdAt = createdAt
  }
}

public struct Notebook: Codable, Hashable, Sendable, Identifiable {
  public var subject: StudySubject
  public var pages: [NotebookPageSummary]

  public var id: String { subject.id }

  public init(subject: StudySubject, pages: [NotebookPageSummary]) {
    self.subject = subject
    self.pages = pages
  }
}

public struct GradeResult: Codable, Hashable, Sendable, Identifiable {
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

/// O zod do servidor aceita nulo em alguns campos e só a ausência em outros
/// (`optional` contra `nullish`). Omitir passa nos dois, então toda entrada
/// daqui usa `encodeIfPresent` em vez do encode sintetizado, que mandaria nulo.
public struct SetAssignmentStatusInput: Hashable, Sendable, Encodable {
  public var id: String
  public var status: AssignmentStatus

  public init(id: String, status: AssignmentStatus) {
    self.id = id
    self.status = status
  }
}

public struct SaveNoteInput: Hashable, Sendable, Encodable {
  public var path: String
  public var title: String
  public var subjectId: String?
  public var materialId: String?
  public var tags: [String]
  public var body: String

  public init(
    path: String, title: String, subjectId: String? = nil, materialId: String? = nil,
    tags: [String] = [], body: String = ""
  ) {
    self.path = path
    self.title = title
    self.subjectId = subjectId
    self.materialId = materialId
    self.tags = tags
    self.body = body
  }

  private enum CodingKeys: String, CodingKey {
    case path, title, subjectId, materialId, tags, body
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(path, forKey: .path)
    try container.encode(title, forKey: .title)
    try container.encodeIfPresent(subjectId, forKey: .subjectId)
    try container.encodeIfPresent(materialId, forKey: .materialId)
    try container.encode(tags, forKey: .tags)
    try container.encode(body, forKey: .body)
  }
}

public struct StartSessionInput: Hashable, Sendable, Encodable {
  public var id: String?
  public var subjectId: String?
  public var materialId: String?

  public init(id: String? = nil, subjectId: String? = nil, materialId: String? = nil) {
    self.id = id
    self.subjectId = subjectId
    self.materialId = materialId
  }

  private enum CodingKeys: String, CodingKey {
    case id, subjectId, materialId
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(id, forKey: .id)
    try container.encodeIfPresent(subjectId, forKey: .subjectId)
    try container.encodeIfPresent(materialId, forKey: .materialId)
  }
}

public struct FinishSessionInput: Hashable, Sendable, Encodable {
  public var id: String
  public var completedMinutes: Int

  public init(id: String, completedMinutes: Int) {
    self.id = id
    self.completedMinutes = completedMinutes
  }
}

public enum FlashcardRating: String, Codable, Hashable, Sendable, CaseIterable {
  case errei, dificil, facil

  public var label: String {
    switch self {
    case .errei: "errei"
    case .dificil: "difícil"
    case .facil: "fácil"
    }
  }
}

public struct GradeFlashcardInput: Hashable, Sendable, Encodable {
  public var id: String
  public var rating: FlashcardRating
  public var expectedDueAt: Date?

  public init(id: String, rating: FlashcardRating, expectedDueAt: Date? = nil) {
    self.id = id
    self.rating = rating
    self.expectedDueAt = expectedDueAt
  }

  private enum CodingKeys: String, CodingKey {
    case id, rating, expectedDueAt
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(rating, forKey: .rating)
    try container.encodeIfPresent(expectedDueAt, forKey: .expectedDueAt)
  }
}

public struct SaveNotebookPageInput: Hashable, Sendable, Encodable {
  public var id: String?
  public var subjectId: String
  public var title: String
  public var content: [JSONValue]

  public init(id: String? = nil, subjectId: String, title: String, content: [JSONValue]) {
    self.id = id
    self.subjectId = subjectId
    self.title = title
    self.content = content
  }

  private enum CodingKeys: String, CodingKey {
    case id, subjectId, title, content
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(id, forKey: .id)
    try container.encode(subjectId, forKey: .subjectId)
    try container.encode(title, forKey: .title)
    try container.encode(content, forKey: .content)
  }
}

public struct IdInput: Hashable, Sendable, Encodable {
  public var id: String
  public init(id: String) { self.id = id }
}

public struct NoteListInput: Hashable, Sendable, Encodable {
  public var subjectId: String?

  public init(subjectId: String? = nil) { self.subjectId = subjectId }

  private enum CodingKeys: String, CodingKey { case subjectId }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(subjectId, forKey: .subjectId)
  }
}

public struct NotePathInput: Hashable, Sendable, Encodable {
  public var path: String
  public init(path: String) { self.path = path }
}

public struct AssignmentListInput: Hashable, Sendable, Encodable {
  public var status: AssignmentStatus?

  public init(status: AssignmentStatus? = nil) { self.status = status }

  private enum CodingKeys: String, CodingKey { case status }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(status, forKey: .status)
  }
}
