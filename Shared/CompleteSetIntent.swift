import AppIntents
import HenriqueCore

/// O "feito" da Live Activity. Como `LiveActivityIntent`, roda no processo do
/// app mesmo quando o toque vem da tela bloqueada, e o app pode estar fechado.
struct CompleteSetIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "marcar série"
  static let isDiscoverable = false

  @Parameter(title: "dia") var date: String
  @Parameter(title: "treino") var templateId: String
  @Parameter(title: "exercício") var exerciseId: String
  @Parameter(title: "tipo") var kind: String
  @Parameter(title: "série") var index: Int

  init() {}

  init(_ key: SetKey) {
    date = key.date.iso
    templateId = key.templateId
    exerciseId = key.exerciseId
    kind = key.kind.rawValue
    index = key.index
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    guard let day = CalendarDate(iso: date), let kind = SetKind(rawValue: kind) else {
      return .result()
    }
    await SetActivityBridge.complete?(
      SetKey(date: day, templateId: templateId, exerciseId: exerciseId, kind: kind, index: index))
    return .result()
  }
}
