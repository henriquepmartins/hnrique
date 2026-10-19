import Foundation

/// O catálogo que viaja com o app. São os 95 exercícios mais feitos na
/// musculação, com nome em PT-BR e imagem, para a busca responder na hora
/// mesmo sem rede. O servidor manda o dele no painel e o seletor junta os
/// dois sem duplicar o id.
public enum ExerciseLibrary {
  public static let muscleGroups = [
    "Peito", "Costas", "Quadríceps", "Posterior", "Glúteos", "Ombros",
    "Bíceps", "Tríceps", "Abdômen", "Panturrilha", "Trapézio", "Antebraço",
    "Lombar", "Geral",
  ]

  private static let bundled: [ExerciseCatalogItem] = BundledExercises.items

  public static func all() -> [ExerciseCatalogItem] { bundled }

  /// Junta o catálogo do servidor com o embutido. O servidor ganha quando o
  /// id repete, porque ele pode ter renomeado ou trocado a imagem. A única
  /// exceção é a foto: quando o servidor ainda não tem imagem, a embutida
  /// continua valendo em vez de apagar.
  public static func merged(with server: [ExerciseCatalogItem]) -> [ExerciseCatalogItem] {
    var byId: [String: ExerciseCatalogItem] = [:]
    for item in bundled { byId[item.id] = item }
    for item in server {
      if item.imageUrl == nil, let current = byId[item.id], current.imageUrl != nil {
        var patched = item
        patched.imageUrl = current.imageUrl
        byId[item.id] = patched
      } else {
        byId[item.id] = item
      }
    }
    return byId.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  public static func search(
    _ query: String, muscle: String?, in items: [ExerciseCatalogItem]
  ) -> [ExerciseCatalogItem] {
    let folded = fold(query)
    return items.filter { item in
      if let muscle, !muscle.isEmpty, item.muscleGroup != muscle { return false }
      guard !folded.isEmpty else { return true }
      return fold(item.name).contains(folded)
        || fold(item.muscleGroup).contains(folded)
        || fold(item.equipment).contains(folded)
    }
  }

  public static func fold(_ value: String) -> String {
    value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
      .lowercased()
  }

  /// O id que o servidor aceita para um exercício criado na hora. Sai do nome
  /// em minúsculas sem acento, só com letras, números e traço.
  public static func slug(_ name: String) -> String {
    let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
      .lowercased()
    let dashed = folded.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return String(dashed.prefix(80)).isEmpty ? "exercicio" : String(dashed.prefix(80))
  }
}
