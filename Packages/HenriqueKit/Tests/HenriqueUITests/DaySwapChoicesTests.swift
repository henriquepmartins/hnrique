import Foundation
import HenriqueCore
import Testing

@testable import HenriqueUI

@Suite("O menu de troca do card de hoje")
struct DaySwapChoicesTests {
  // 16 de setembro de 2026 é quarta. Peito na segunda, costas na terça, pernas na
  // quarta, ombro sem dia.
  private static let plan: [(id: String, weekdays: [Int])] = [
    ("peito", [1]), ("costas", [2]), ("pernas", [3]), ("ombro", []),
  ]

  private static func dashboard(
    date: String, workout: String?, swaps: [(String, String)]?
  ) throws -> Dashboard {
    let planItems = plan.map { item in
      [
        "id": item.id, "weekdays": item.weekdays, "name": item.id.capitalized, "focus": "",
        "exerciseCount": 0, "exercises": [] as [Any], "estimatedMinutes": 45,
      ] as [String: Any]
    }
    var json: [String: Any] = [
      "date": date, "consistencyPercent": 0, "currentStreak": 0, "weeklyCompleted": 0,
      "weeklyPlanned": 3, "weekPlan": planItems, "exerciseCatalog": [] as [Any],
      "progress": [] as [Any], "measurements": [] as [Any], "onboardingCompleted": true,
    ]
    if let workout {
      json["workout"] = [
        "id": workout, "name": workout.capitalized, "focus": "", "estimatedMinutes": 45,
        "exerciseCount": 0, "workSetCount": 0, "completedWorkSetCount": 0,
        "completionPercent": 0, "exercises": [] as [Any],
      ] as [String: Any]
    }
    if let swaps {
      json["daySwaps"] = swaps.map { ["date": $0.0, "workoutTemplateId": $0.1] }
    }
    return try JSONDecoder.henrique().decode(
      Dashboard.self, from: JSONSerialization.data(withJSONObject: json))
  }

  private func titles(_ options: [DaySwapChoices.Option]) -> [String] { options.map(\.title) }

  @Test("servidor sem troca de dia não ganha menu")
  func oldServerHasNoMenu() throws {
    #expect(DaySwapChoices(try Self.dashboard(date: "2026-09-16", workout: "pernas", swaps: nil)) == nil)
  }

  @Test("dia do plano: atrasados primeiro, o resto sem o treino de hoje, sem voltar ao plano")
  func plannedDay() throws {
    let choices = try #require(
      DaySwapChoices(try Self.dashboard(date: "2026-09-16", workout: "pernas", swaps: [])))
    #expect(titles(choices.missed) == ["costas · faltou terça", "peito · faltou segunda"])
    #expect(choices.missed.map(\.workoutId) == ["costas", "peito"])
    #expect(titles(choices.others) == ["ombro"])
    #expect(choices.revert == nil)
    #expect(choices.replaced == nil)
  }

  @Test("dia trocado: diz o que saiu, oferece o treino do plano e voltar ao plano")
  func swappedDay() throws {
    let choices = try #require(
      DaySwapChoices(
        try Self.dashboard(
          date: "2026-09-16", workout: "costas", swaps: [("2026-09-16", "costas")])))
    #expect(titles(choices.missed) == ["peito · faltou segunda"])
    #expect(titles(choices.others) == ["pernas", "ombro"])
    #expect(choices.revert == .init(title: "voltar ao plano", workoutId: nil))
    #expect(choices.replaced == "no lugar de pernas")
    #expect(choices.all.last?.workoutId == nil)
  }

  @Test("descanso trocado fala em descanso")
  func swappedRestDay() throws {
    let choices = try #require(
      DaySwapChoices(
        try Self.dashboard(
          date: "2026-09-20", workout: "ombro", swaps: [("2026-09-20", "ombro")])))
    #expect(choices.replaced == "no lugar do descanso")
  }
}
