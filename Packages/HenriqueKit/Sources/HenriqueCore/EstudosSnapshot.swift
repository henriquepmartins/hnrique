import Foundation

/// A última resposta de cada aba de estudos, gravada para o app abrir sem
/// rede. Cada campo é opcional porque as abas carregam separadas e uma pode
/// ter falhado.
public struct EstudosSnapshot: Codable, Hashable, Sendable {
  public var overview: StudyOverview?
  public var subjects: [StudySubject]?
  public var assignments: [AssignmentGroup]?
  public var notebooks: [Notebook]?
  public var queue: ReviewQueue?

  public init(
    overview: StudyOverview? = nil, subjects: [StudySubject]? = nil,
    assignments: [AssignmentGroup]? = nil, notebooks: [Notebook]? = nil,
    queue: ReviewQueue? = nil
  ) {
    self.overview = overview
    self.subjects = subjects
    self.assignments = assignments
    self.notebooks = notebooks
    self.queue = queue
  }

  public static func read(from url: URL) -> EstudosSnapshot? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder.henrique().decode(EstudosSnapshot.self, from: data)
  }

  public func write(to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder.henrique().encode(self).write(to: url, options: .atomic)
  }
}
