import Foundation
import Testing

@testable import HenriqueCore

@Suite("O recorde durante a sessão")
struct SessionRecordTests {
  private static let today = CalendarDate(year: 2026, month: 10, day: 19)!

  /// Séries valendo de hoje como (kg, reps, segundos desde o começo), ou nil se em aberto.
  private static func exercise(
    _ work: [(Double, Int, Double)?], last: (Double, Int)? = nil, best: (Double, Int)? = nil
  ) -> DashboardExercise {
    DashboardExercise(
      id: "agachamento", name: "agachamento livre", muscleGroup: "pernas", equipment: "barra",
      order: 1,
      prescription: ExercisePrescription(
        prepSets: 0, workSets: work.count, repsMin: 6, repsMax: 10, workToFailure: false,
        startingWeightKg: 70),
      previous: last.map {
        PreviousWorkSets(
          date: today.adding(days: -3), weightKg: $0.0, reps: [$0.1], volumeKg: $0.0 * Double($0.1))
      },
      sets: ExerciseSets(
        prep: [],
        work: work.enumerated().map { offset, set in
          WorkSet(
            index: offset + 1, weightKg: set?.0 ?? 70, reps: set?.1 ?? 6, toFailure: false,
            completedAt: set.map { Date(timeIntervalSince1970: 1_000 + $0.2) })
        }),
      best: best.map {
        BestSet(
          weightKg: $0.0, reps: $0.1, estimatedOneRepMax: $0.0 * (1 + Double($0.1) / 30),
          date: today.adding(days: -56))
      })
  }

  @Test("bater a última vez não basta: 95 × 5 depois de 90 × 8 fica abaixo do melhor 100 × 5")
  func comparesWithTheAllTimeBest() {
    let exercise = Self.exercise([(95, 5, 0)], last: (90, 8), best: (100, 5))
    #expect(exercise.recordSets().isEmpty)
  }

  @Test("passa o melhor de sempre, e cada série de hoje sobe a marca na ordem da marcação")
  func raisesTheBarInCompletionOrder() {
    // 100 × 6 passa 100 × 5; a 1, marcada depois, empata com ela; 102,5 × 3 passa.
    let exercise = Self.exercise([(100, 6, 60), (100, 6, 0), (102.5, 3, 120)], best: (100, 5))
    #expect(exercise.recordSets() == [2, 3])
  }

  @Test("peso corporal nunca comemora: 0 × 13 depois de 0 × 12")
  func bodyweightNeverCelebrates() {
    #expect(Self.exercise([(0, 13, 0)], last: (0, 12)).recordSets().isEmpty)
    #expect(Self.exercise([(0, 13, 0)], last: (0, 12), best: (20, 5)).recordSets().isEmpty)
  }

  @Test("sem o melhor de sempre, que é o servidor antigo ou a estreia, não comemora")
  func noBestNoCelebration() {
    #expect(Self.exercise([(80, 10, 0)], last: (70, 8)).recordSets().isEmpty)
  }

  @Test("o melhor de sempre decodifica, e um formato inesperado vira nulo sem derrubar o exercício")
  func decodesTheBest() throws {
    let base = #"{"id": "agachamento", "name": "agachamento", "muscleGroup": "pernas", "equipment": "barra", "order": 1, "prescription": {"prepSets": 0, "workSets": 1, "repsMin": 6, "repsMax": 10, "workToFailure": false, "startingWeightKg": 70}, "sets": {"prep": [], "work": []}"#
    let good = base + #", "best": {"weightKg": 100, "reps": 5, "estimatedOneRepMax": 116.7, "date": "2026-08-24"}}"#
    let odd = base + #", "best": {"weightKg": "cem"}}"#
    let decoded = try JSONDecoder.henrique().decode(DashboardExercise.self, from: Data(good.utf8))
    #expect(decoded.best == BestSet(
      weightKg: 100, reps: 5, estimatedOneRepMax: 116.7, date: CalendarDate(year: 2026, month: 8, day: 24)!))
    #expect(try JSONDecoder.henrique().decode(DashboardExercise.self, from: Data(odd.utf8)).best == nil)
  }
}

@Suite("A tinta sobre a cor do treino")
struct ToneContrastTests {
  @Test("o vermelho leva tinta branca e o verde-limão leva tinta escura")
  func picksTheReadableInk() throws {
    #expect(ToneContrast.ink(on: try #require(ToneRGB(hex: "#ef4444"))) == .white)
    #expect(ToneContrast.ink(on: try #require(ToneRGB(hex: "#a3e635"))) != .white)
  }

  @Test("uma cor clara escurece no próprio matiz até ler sobre o papel")
  func darkensUntilLegible() throws {
    let paper = try #require(ToneRGB(hex: "#faf9f7"))
    let yellow = try #require(ToneRGB(hex: "#eab308"))
    let legible = ToneContrast.legible(yellow, on: paper, minimum: 3)
    #expect(ToneContrast.wcag(legible, paper) >= 3)
    #expect(abs(legible.hsb.hue - yellow.hsb.hue) < 0.01)
    let blue = try #require(ToneRGB(hex: "#1f5fbf"))
    #expect(ToneContrast.legible(blue, on: paper, minimum: 3) == blue)
  }
}
