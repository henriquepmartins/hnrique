import Foundation
import HenriqueCore
import Testing

@testable import HenriqueUI

@Suite("O bloco no foco")
@MainActor
struct FocoBlockTests {
  private let url = FileManager.default.temporaryDirectory
    .appending(path: "foco-bloco-\(UUID().uuidString).json")

  @Test("o bloco que venceu com o app fechado vira sessão até o alvo ao abrir")
  func expiredBlockStopsAtItsTargetOnLaunch() throws {
    defer { try? FileManager.default.removeItem(at: url) }
    var ledger = FocoLedger()
    ledger.start(
      .alemao, target: 25 * 60, at: .now.addingTimeInterval(-40 * 60), calendar: StudyFormat.calendar)
    try JSONEncoder.henrique().encode(ledger).write(to: url)

    let store = FocoStore(fileURL: url, estudos: nil)

    #expect(store.ledger.running == nil)
    let counted = store.ledger.entries.reduce(0) { $0 + $1.seconds }
    #expect(abs(counted - 25 * 60) < 0.01)
    #expect(store.result != nil)
  }
}
