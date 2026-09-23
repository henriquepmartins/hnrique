import Foundation
import Testing

@testable import HenriqueCore

@Suite("Retrato de estudos no disco")
struct EstudosSnapshotTests {
  @Test("as cinco abas fazem ida e volta pelo arquivo")
  func roundTripsThroughDisk() throws {
    let amostra = try EstudosContractTests.amostra()
    let snapshot = EstudosSnapshot(
      overview: amostra.overview, subjects: amostra.subjects, assignments: amostra.assignments,
      notebooks: amostra.notebooks, queue: amostra.queue)
    let url = FileManager.default.temporaryDirectory
      .appending(path: "estudos-\(UUID().uuidString)/retrato.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try snapshot.write(to: url)
    let back = try #require(EstudosSnapshot.read(from: url))
    #expect(back == snapshot)
    #expect(back.subjects?.map(\.id) == ["s-eda", "s-so", "s-calc"])
    #expect(back.overview?.date.iso == "2026-09-08")
    #expect(back.queue?.cards.count == 2)
  }

  @Test("arquivo ausente ou corrompido não derruba nada")
  func missingOrBrokenFileReadsNil() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "estudos-\(UUID().uuidString).json")
    #expect(EstudosSnapshot.read(from: url) == nil)
    try Data("{".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(EstudosSnapshot.read(from: url) == nil)
  }
}
