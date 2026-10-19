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

  @Test("encerrado mostra o tempo real no lugar da estimativa, em minutos")
  func finishedShowsDuration() throws {
    let workout = try Self.workout()
    let count = "\(workout.exerciseCount) exercícios"
    #expect(meta(HeroModel(workout: workout, finished: true, duration: 283)) == "\(count) · 5 min")
    #expect(meta(HeroModel(workout: workout, finished: true, duration: 3730)) == "\(count) · 1 h 2 min")
    let estimate = "\(count) · \(Formatting.duration(minutes: workout.estimatedMinutes))"
    #expect(meta(HeroModel(workout: workout, finished: true, duration: 20)) == estimate)
    #expect(meta(HeroModel(workout: workout, finished: true)) == estimate)
  }

  @Test("em andamento conta as séries, sem estimativa nem porcentagem")
  func inProgressCountsSets() throws {
    var workout = try Self.workout()
    workout.workSetCount = 6
    workout.completedWorkSetCount = 2
    workout.completionPercent = 33
    let model = HeroModel(workout: workout)
    #expect(meta(model) == "2 de 6 séries")
    guard case .session(let session) = model else {
      Issue.record("esperava sessão")
      return
    }
    #expect(session.compactMeta == "2/6")
  }

  @Test("sem treino é descanso")
  func restDay() {
    guard case .rest = HeroModel(workout: nil) else {
      Issue.record("esperava descanso")
      return
    }
  }
}
