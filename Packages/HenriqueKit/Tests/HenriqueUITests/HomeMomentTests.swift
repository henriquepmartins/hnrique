import Foundation
import HenriqueCore
import Testing

@testable import HenriqueUI

@Suite("A home segue o momento do dia")
struct HomeMomentTests {
  private static func workout(percent: Int) throws -> WorkoutSummary {
    let data = Data(dashboardDeHoje().utf8)
    var workout = try #require(try JSONDecoder.henrique().decode(Dashboard.self, from: data).workout)
    workout.completionPercent = percent
    return workout
  }

  @Test("o encerrar conta como depois, mesmo com série em aberto")
  func closedEarlyIsAfter() throws {
    #expect(HomeMoment(workout: try Self.workout(percent: 40), finishedAt: .now) == .after)
    #expect(HomeMoment(workout: try Self.workout(percent: 100), finishedAt: nil) == .after)
    #expect(HomeMoment(workout: try Self.workout(percent: 40), finishedAt: nil) == .during)
    #expect(HomeMoment(workout: try Self.workout(percent: 0), finishedAt: nil) == .before)
    #expect(HomeMoment(workout: nil, finishedAt: nil) == .rest)
  }

  @Test("antes do treino a semana vem logo depois do cartão do dia")
  func weekRightAfterTheDay() {
    #expect(HomeMoment.before.sections.prefix(2) == [.day, .week])
    #expect(HomeMoment.during.sections.prefix(2) == [.day, .week])
  }

  @Test("depois do treino os recordes sobem e a semana vem antes dos próximos dias")
  func afterPutsRecordsAndWeekFirst() {
    let sections = HomeMoment.after.sections
    #expect(sections.prefix(3) == [.day, .records, .week])
    #expect(sections.firstIndex(of: .week)! < sections.firstIndex(of: .nextDays)!)
  }
}
