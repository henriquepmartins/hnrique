import Foundation

/// A cauda longa do catálogo. A wger tem mais de 800 exercícios com imagem e
/// não pede chave, então quando a busca local devolve pouco, o seletor bate
/// aqui. Baixa a lista uma vez por sessão, guarda só quem tem imagem e
/// filtra no aparelho.
public actor WgerClient {
  private static let base = URL(string: "https://wger.de/api/v2/exerciseinfo/")!
  private let session: URLSession
  private var items: [ExerciseCatalogItem]?
  private var flight: Task<[ExerciseCatalogItem], Error>?

  public init(session: URLSession = .shared) {
    self.session = session
  }

  /// Baixa a lista enquanto o seletor abre, para a primeira busca não esperar
  /// a rede. Falhar aqui não diz nada; a busca tenta de novo.
  public func prefetch() async {
    _ = try? await catalog()
  }

  /// Devolve os exercícios da base pública que casam com o termo, já sem os
  /// que o catálogo local cobre. Lista vazia é resposta válida, não erro.
  public func search(_ term: String, excluding local: [ExerciseCatalogItem]) async throws
    -> [ExerciseCatalogItem]
  {
    let folded = ExerciseLibrary.fold(term)
    guard folded.count >= 2 else { return [] }
    let all = try await catalog()
    let localNames = Set(local.map { ExerciseLibrary.fold($0.name) })
    let localImages = Set(local.compactMap(\.imageUrl))
    return Array(
      all.filter { item in
        guard !localNames.contains(ExerciseLibrary.fold(item.name)) else { return false }
        if let image = item.imageUrl, localImages.contains(image) { return false }
        return ExerciseLibrary.fold(item.name).contains(folded)
          || ExerciseLibrary.fold(item.muscleGroup).contains(folded)
          || ExerciseLibrary.fold(item.equipment).contains(folded)
      }.prefix(30))
  }

  private func catalog() async throws -> [ExerciseCatalogItem] {
    if let items { return items }
    if let flight { return try await flight.value }
    let session = self.session
    let task = Task { () throws -> [ExerciseCatalogItem] in
      var components = URLComponents(url: Self.base, resolvingAgainstBaseURL: false)!
      components.queryItems = [
        URLQueryItem(name: "language", value: "2"),
        URLQueryItem(name: "limit", value: "1000"),
      ]
      // O padrão de 60 s deixava a rodinha girando um minuto sem rede.
      var request = URLRequest(url: components.url!, timeoutInterval: 15)
      request.setValue("henrique-ios/1.0", forHTTPHeaderField: "User-Agent")
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      let (data, _) = try await session.data(for: request)
      try Task.checkCancellation()
      let page = try JSONDecoder().decode(Page.self, from: data)
      return page.results.compactMap(Self.map)
    }
    flight = task
    do {
      let items = try await task.value
      self.items = items
      self.flight = nil
      return items
    } catch {
      self.flight = nil
      throw error
    }
  }

  // MARK: - Mapeamento

  static func map(_ info: Info) -> ExerciseCatalogItem? {
    guard let image = info.images.first(where: { $0.isMain }) ?? info.images.first else { return nil }
    guard let name = info.translations.first(where: { $0.language == 7 })?.name
      ?? info.translations.first(where: { $0.language == 2 })?.name,
      !name.isEmpty
    else { return nil }
    let muscle = info.muscles.first.map { muscleName($0.nameEn.isEmpty ? $0.name : $0.nameEn) }
      ?? categoryName(info.category.name)
    let equipment = info.equipment.first.map { equipmentName($0.name) } ?? "Livre"
    return ExerciseCatalogItem(
      id: "wger-\(info.id)", name: name, muscleGroup: muscle, equipment: equipment,
      imageUrl: image.thumbnails?.medium ?? image.image)
  }

  static func muscleName(_ english: String) -> String {
    let value = english.lowercased()
    if value.contains("femoris") || value.contains("hamstring") { return "Posterior" }
    if value.contains("chest") || value.contains("pectoralis") || value.contains("serratus") {
      return "Peito"
    }
    if value.contains("shoulder") || value.contains("deltoid") { return "Ombros" }
    if value.contains("biceps") { return "Bíceps" }
    if value.contains("triceps") { return "Tríceps" }
    if value.contains("quad") { return "Quadríceps" }
    if value.contains("glut") { return "Glúteos" }
    if value.contains("ab") || value.contains("obliqu") { return "Abdômen" }
    if value.contains("calv") || value.contains("soleus") || value.contains("gastrocnemius") {
      return "Panturrilha"
    }
    if value.contains("lat") || value.contains("back") || value.contains("dorsi") { return "Costas" }
    if value.contains("trapezius") { return "Trapézio" }
    if value.contains("brachial") || value.contains("forearm") { return "Antebraço" }
    if value.contains("erector") || value.contains("spinae") { return "Lombar" }
    return "Geral"
  }

  static func categoryName(_ category: String) -> String {
    switch category.lowercased() {
    case "chest": return "Peito"
    case "back": return "Costas"
    case "legs": return "Quadríceps"
    case "shoulders": return "Ombros"
    case "arms": return "Bíceps"
    case "abs": return "Abdômen"
    case "calves": return "Panturrilha"
    default: return "Geral"
    }
  }

  static func equipmentName(_ english: String) -> String {
    let value = english.lowercased()
    if value.contains("barbell") { return "Barra" }
    if value.contains("dumbbell") { return "Halteres" }
    if value.contains("cable") { return "Cabo" }
    if value.contains("kettlebell") { return "Kettlebell" }
    if value.contains("bodyweight") { return "Peso corporal" }
    if value.contains("band") { return "Elástico" }
    if value.contains("pull-up") { return "Barra fixa" }
    if value.contains("bench") { return "Banco" }
    if value.contains("sz") { return "Barra W" }
    if value.contains("ball") { return "Bola" }
    if value.contains("mat") { return "Colchonete" }
    if value.contains("machine") { return "Máquina" }
    return "Livre"
  }

  // MARK: - Resposta da wger

  struct Page: Decodable {
    var results: [Info]
  }

  struct Info: Decodable {
    var id: Int
    var category: Category
    var muscles: [Muscle]
    var equipment: [Equipment]
    var images: [Image]
    var translations: [Translation]
  }

  struct Category: Decodable { var name: String }
  struct Muscle: Decodable {
    var name: String; var nameEn: String
    enum CodingKeys: String, CodingKey { case name; case nameEn = "name_en" }
  }
  struct Equipment: Decodable { var name: String }

  struct Image: Decodable {
    var image: String
    var isMain: Bool
    var thumbnails: Thumbnails?
    enum CodingKeys: String, CodingKey { case image; case isMain = "is_main"; case thumbnails }
  }

  struct Thumbnails: Decodable { var small: String?; var medium: String? }
  struct Translation: Decodable { var name: String; var language: Int }
}
