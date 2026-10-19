import Foundation
import Testing

@testable import HenriqueCore

/// A base offline que alimenta o seletor e o mapeamento da wger. Se o JSON
/// embutido quebrar, é aqui que aparece, e não com o seletor vazio no treino.
@Suite("Biblioteca de exercícios")
struct ExerciseLibraryTests {
  @Test("o JSON embutido carrega com imagem em tudo")
  func bundledLoads() {
    let items = ExerciseLibrary.all()
    #expect(items.count >= 90)
    #expect(items.allSatisfy { ($0.imageUrl ?? "").hasPrefix("https://") })
    #expect(Set(items.map(\.id)).count == items.count)
  }

  @Test("o servidor ganha quando o id repete")
  func serverWinsMerge() {
    let server = [
      ExerciseCatalogItem(
        id: "supino-reto-barra", name: "Supino reto renomeado", muscleGroup: "Peito",
        equipment: "Barra", imageUrl: nil)
    ]
    let merged = ExerciseLibrary.merged(with: server)
    #expect(merged.first(where: { $0.id == "supino-reto-barra" })?.name == "Supino reto renomeado")
    #expect(merged.count == ExerciseLibrary.all().count)
  }

  @Test("a busca ignora acento e filtra por músculo")
  func searchFoldsAndFilters() {
    let items = ExerciseLibrary.all()
    #expect(!ExerciseLibrary.search("rosca", muscle: nil, in: items).isEmpty)
    #expect(ExerciseLibrary.search("biceps", muscle: nil, in: items).count >= 5)
    let peito = ExerciseLibrary.search("", muscle: "Peito", in: items)
    #expect(!peito.isEmpty)
    #expect(peito.allSatisfy { $0.muscleGroup == "Peito" })
    #expect(ExerciseLibrary.search("zzz-nao-existe", muscle: nil, in: items).isEmpty)
  }

  @Test("a foto embutida sobrevive ao servidor sem imagem")
  func keepsBundledImageWhenServerHasNone() throws {
    let server = [
      ExerciseCatalogItem(
        id: "supino-reto-barra", name: "Supino reto com barra", muscleGroup: "Peito",
        equipment: "Barra", imageUrl: nil)
    ]
    let merged = ExerciseLibrary.merged(with: server)
    let item = try #require(merged.first(where: { $0.id == "supino-reto-barra" }))
    #expect(item.name == "Supino reto com barra")
    #expect(item.imageUrl?.hasPrefix("https://") == true)
  }

  @Test("o apelido sai limpo para virar id no servidor")
  func slugifies() {
    #expect(ExerciseLibrary.slug("Crucifixo Inverso no Cabo") == "crucifixo-inverso-no-cabo")
    #expect(ExerciseLibrary.slug("Elevação Lateral") == "elevacao-lateral")
    #expect(ExerciseLibrary.slug("  ") == "exercicio")
  }

  @Test("o painel antigo sem imagem continua decodificando")
  func oldDashboardStillDecodes() throws {
    let url = try #require(
      Bundle.module.url(forResource: "Fixtures/dashboard", withExtension: "json"))
    let dashboard = try JSONDecoder.henrique().decode(
      Dashboard.self, from: Data(contentsOf: url))
    #expect(dashboard.exerciseCatalog.first?.imageUrl == nil)
    #expect(dashboard.workout?.exercises.first?.imageUrl == nil)
  }

  @Test("o exercício novo leva os dados para o servidor criar")
  func planExerciseCarriesMetadata() throws {
    let exercise = PlanExercise(
      exerciseId: "wger-73", prepSets: 2, workSets: 2, repsMin: 8, repsMax: 12,
      workToFailure: true, startingWeightKg: 20, name: "Bench Press",
      muscleGroup: "Peito", equipment: "Barra", imageUrl: "https://x/y.png")
    let json = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(exercise)) as? [String: Any])
    #expect(json["exerciseId"] as? String == "wger-73")
    #expect(json["name"] as? String == "Bench Press")
    #expect(json["imageUrl"] as? String == "https://x/y.png")
  }
}

/// O mapeamento da resposta da wger para o catálogo. Nome em PT quando tem,
/// inglês quando não tem, sempre com a imagem principal.
@Suite("Mapeamento da wger")
struct WgerMappingTests {
  private static func info(
    id: Int = 73, muscles: [WgerClient.Muscle] = [.init(name: "Pectoralis major", nameEn: "Chest")],
    equipment: [WgerClient.Equipment] = [.init(name: "Barbell")],
    images: [WgerClient.Image] = [
      .init(
        image: "https://wger.de/media/full.png",
        isMain: true,
        thumbnails: .init(
          small: "https://wger.de/media/small.png", medium: "https://wger.de/media/medium.png"))
    ],
    translations: [WgerClient.Translation] = [.init(name: "Bench Press", language: 2)]
  ) -> WgerClient.Info {
    .init(
      id: id, category: .init(name: "Chest"), muscles: muscles, equipment: equipment,
      images: images, translations: translations)
  }

  @Test("mapeia nome, músculo, aparelho e a miniatura")
  func mapsAllFields() throws {
    let item = try #require(WgerClient.map(Self.info()))
    #expect(item.id == "wger-73")
    #expect(item.name == "Bench Press")
    #expect(item.muscleGroup == "Peito")
    #expect(item.equipment == "Barra")
    #expect(item.imageUrl == "https://wger.de/media/medium.png")
    #expect(item.isRemote == true)
  }

  @Test("prefere o nome em português e a imagem principal")
  func prefersPortugueseAndMainImage() throws {
    let item = try #require(
      WgerClient.map(
        Self.info(
          images: [
            .init(image: "https://wger.de/media/other.png", isMain: false, thumbnails: nil),
            .init(
              image: "https://wger.de/media/main.png", isMain: true,
              thumbnails: .init(small: nil, medium: nil)),
          ],
          translations: [
            .init(name: "Bench Press", language: 2),
            .init(name: "Supino reto", language: 7),
          ])))
    #expect(item.name == "Supino reto")
    #expect(item.imageUrl == "https://wger.de/media/main.png")
  }

  @Test("sem imagem ou sem nome não entra no catálogo")
  func dropsImageless() {
    #expect(WgerClient.map(Self.info(images: [])) == nil)
    #expect(WgerClient.map(Self.info(translations: [])) == nil)
  }

  @Test("posterior não vira bíceps e ombro não vira peito")
  func muscleMapping() {
    #expect(WgerClient.muscleName("Biceps femoris") == "Posterior")
    #expect(WgerClient.muscleName("Biceps brachii") == "Bíceps")
    #expect(WgerClient.muscleName("Anterior deltoid") == "Ombros")
    #expect(WgerClient.muscleName("Latissimus dorsi") == "Costas")
    #expect(WgerClient.muscleName("Rectus abdominis") == "Abdômen")
    #expect(WgerClient.muscleName("Gluteus maximus") == "Glúteos")
    #expect(WgerClient.equipmentName("SZ-Bar") == "Barra W")
    #expect(WgerClient.equipmentName("none (bodyweight exercise)") == "Peso corporal")
  }

  @Test("toda categoria da wger cai num chip de grupo muscular")
  func wgerCategoriesHaveChips() {
    for category in ["chest", "back", "legs", "shoulders", "arms", "abs", "calves", "cardio", "outra"] {
      #expect(ExerciseLibrary.muscleGroups.contains(WgerClient.categoryName(category)))
    }
  }
}
