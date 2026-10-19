import Foundation
import HenriqueCore
import Testing

@testable import HenriqueUI

private func historyBody(load: Double) -> String {
  #"{"exerciseId":"supino-reto","exerciseName":"Supino reto","load":{"exerciseId":"supino-reto","workWeightKg":\#(load),"prepWeightKg":null},"entries":[]}"#
}

extension PendingSetQueueTests {
  @Suite("O histórico do exercício na store")
  @MainActor
  struct ExerciseHistoryStoreTests {
    init() {
      FakeNetwork.reset()
      resetLocalState()
    }

    @Test("o histórico fica guardado até uma série do exercício ser gravada")
    func historyCacheDropsOnRecord() async throws {
      let store = await lojaComPainel()
      FakeNetwork.offline = false
      FakeNetwork.bodies[.exerciseHistory] = historyBody(load: 50)
      #expect(try await store.history(of: "supino-reto").load.workWeightKg == 50)

      FakeNetwork.bodies[.exerciseHistory] = historyBody(load: 55)
      #expect(try await store.history(of: "supino-reto").load.workWeightKg == 50)

      FakeNetwork.offline = true
      _ = await store.record(
        key: SetKey(date: .today, templateId: "tpl-terca", exerciseId: "desenvolvimento", kind: .work, index: 1),
        weightKg: 14, reps: 12, completed: true, toFailure: false)?.value
      #expect(store.cachedHistory(of: "supino-reto") != nil)

      _ = await store.record(
        key: SetKey(date: .today, templateId: "tpl-terca", exerciseId: "supino-reto", kind: .work, index: 2),
        weightKg: 55, reps: 8, completed: true, toFailure: true)?.value
      FakeNetwork.offline = false
      #expect(try await store.history(of: "supino-reto").load.workWeightKg == 55)
    }
  }
}
