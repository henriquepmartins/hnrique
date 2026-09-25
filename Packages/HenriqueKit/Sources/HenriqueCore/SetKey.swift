import Foundation

/// Uma série do dia: a data, o treino, o exercício, o tipo e o índice.
public struct SetKey: Hashable, Sendable, Codable {
  public let date: CalendarDate
  public let templateId: String
  public let exerciseId: String
  public let kind: SetKind
  public let index: Int

  public init(date: CalendarDate, templateId: String, exerciseId: String, kind: SetKind, index: Int) {
    self.date = date
    self.templateId = templateId
    self.exerciseId = exerciseId
    self.kind = kind
    self.index = index
  }
}
