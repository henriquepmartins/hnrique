import Foundation
import HenriqueCore
import Testing

@testable import HenriqueUI

@Suite("O rodapé do hero")
struct HeroModelTests {
  private static func workout() throws -> WorkoutSummary {
    let data = Data(dashboardDeHoje().utf8)
    return try #require(try JSONDecoder.henrique().decode(Dashboard.self, from: data).workout)
  }

  private func meta(_ model: HeroModel) -> String? {
    if case .session(let session) = model { session.meta } else { nil }
  }

  @Test("encerrado mostra o tempo real no lugar da estimativa")
  func finishedShowsDuration() throws {
    let workout = try Self.workout()
    let count = "\(workout.exerciseCount) exercícios"
    #expect(meta(HeroModel(workout: workout, finished: true, duration: 283)) == "\(count) · 4:43")
    #expect(meta(HeroModel(workout: workout, finished: true, duration: 3730)) == "\(count) · 1:02:10")
    let estimate = "\(count) · \(workout.estimatedMinutesComputed) min"
    #expect(meta(HeroModel(workout: workout, finished: true, duration: 20)) == estimate)
    #expect(meta(HeroModel(workout: workout, finished: true)) == estimate)
  }

  @Test("sem treino é descanso")
  func restDay() {
    guard case .rest = HeroModel(workout: nil) else {
      Issue.record("esperava descanso")
      return
    }
  }
}
