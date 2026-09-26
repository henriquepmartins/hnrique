import Foundation
import HenriqueCore
import Testing

@testable import HenriqueUI

@Suite("A coluna anterior da sessão")
struct SessionPreviousTests {
  private func previous(_ json: String) throws -> PreviousWorkSets {
    try JSONDecoder().decode(PreviousWorkSets.self, from: Data(json.utf8))
  }

  @Test("pirâmide: cada série compara com a carga dela da última vez, casada pelo índice")
  func matchesByIndex() throws {
    let last = try previous("""
      {"date":"2026-09-16","weightKg":100,"reps":[6,8,10],"volumeKg":2140,
       "sets":[{"index":3,"weightKg":80,"reps":10},{"index":1,"weightKg":100,"reps":6},
               {"index":2,"weightKg":90,"reps":8}]}
      """)
    #expect(previousLabel(last, index: 1) == "100 × 6")
    #expect(previousLabel(last, index: 2) == "90 × 8")
    #expect(previousLabel(last, index: 3) == "80 × 10")
    #expect(previousLabel(last, index: 4) == nil)
    #expect(previousTop(last)?.weightKg == 100)
    #expect(previousTop(last)?.reps == 6)
  }

  @Test("servidor antigo sem sets: maior carga e repetições pela posição")
  func oldShape() throws {
    let last = try previous("""
      {"date":"2026-09-16","weightKg":48,"reps":[8,7],"volumeKg":720}
      """)
    #expect(previousLabel(last, index: 1) == "48 × 8")
    #expect(previousLabel(last, index: 2) == "48 × 7")
    #expect(previousLabel(last, index: 3) == nil)
    #expect(previousTop(last)?.weightKg == 48)
    #expect(previousTop(last)?.reps == 8)
    #expect(previousLabel(PreviousWorkSets?.none, index: 1) == nil)
    #expect(previousTop(nil) == nil)
  }
}
