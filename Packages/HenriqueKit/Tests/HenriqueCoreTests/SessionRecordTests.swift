import Foundation
import Testing

@testable import HenriqueCore

@Suite("O recorde durante a sessão")
struct SessionRecordTests {
  private static let today = CalendarDate(year: 2026, month: 10, day: 19)!

  /// Séries valendo de hoje como (kg, reps, segundos desde o começo), ou nil se em aberto.
  private static func exercise(
    _ work: [(Double, Int, Double)?], previous: PreviousWorkSets? = nil
  ) -> DashboardExercise {
    DashboardExercise(
      id: "agachamento", name: "agachamento livre", muscleGroup: "pernas", equipment: "barra",
      order: 1,
      prescription: ExercisePrescription(
        prepSets: 0, workSets: work.count, repsMin: 6, repsMax: 10, workToFailure: false,
        startingWeightKg: 70),
      previous: previous,
      sets: ExerciseSets(
        prep: [],
        work: work.enumerated().map { offset, set in
          WorkSet(
            index: offset + 1, weightKg: set?.0 ?? 70, reps: set?.1 ?? 6, toFailure: false,
            completedAt: set.map { Date(timeIntervalSince1970: 1_000 + $0.2) })
        }))
  }

  private static func record(_ kg: Double, _ reps: Int, daysAgo: Int) -> PersonalRecord {
    PersonalRecord(
      exerciseId: "agachamento", exerciseName: "agachamento livre", kind: .carga, weightKg: kg,
      reps: reps, date: today.adding(days: -daysAgo), delta: 2.5)
  }

  @Test("passa a marca de antes: o recorde velho do painel vale mais que a última vez")
  func beatsTheBestBefore() {
    let last = PreviousWorkSets(date: Self.today.adding(days: -3), weightKg: 70, reps: [8], volumeKg: 560)
    let records = [Self.record(72, 6, daysAgo: 20), Self.record(72, 6, daysAgo: 0)]
    // 72 × 6 empata, 72 × 7 passa, 75 × 5 passa a 72 × 7, 74 × 9 fica abaixo de 75.
    let exercise = Self.exercise(
      [(72, 6, 0), (72, 7, 60), (75, 5, 120), (74, 9, 180), nil], previous: last)
    #expect(exercise.recordSets(records: records, on: Self.today) == [2, 3])
  }

  @Test("a ordem é a da marcação, não a do índice")
  func followsCompletionOrder() {
    let last = PreviousWorkSets(date: Self.today.adding(days: -3), weightKg: 70, reps: [8], volumeKg: 560)
    let exercise = Self.exercise([(75, 6, 120), (72, 6, 0)], previous: last)
    #expect(exercise.recordSets(records: [], on: Self.today) == [1, 2])
  }

  @Test("sem marca anterior é estreia, e estreia não vira recorde na sessão")
  func debutIsNotARecord() {
    let exercise = Self.exercise([(40, 10, 0), (45, 10, 60)])
    #expect(exercise.recordSets(records: [Self.record(45, 10, daysAgo: 0)], on: Self.today).isEmpty)
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
