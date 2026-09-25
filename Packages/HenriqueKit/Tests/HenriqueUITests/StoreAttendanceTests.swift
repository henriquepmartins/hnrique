import Foundation
import HenriqueCore
import Testing

@testable import HenriqueUI

private func workKey(_ exercise: String, _ index: Int) -> SetKey {
  SetKey(date: .today, templateId: "tpl-terca", exerciseId: exercise, kind: .work, index: index)
}

@MainActor
private func planWeight(_ store: AcademiaStore) -> [Double?] {
  [
    store.dashboard?.weekPlan.first?.exercises.first?.startingWeightKg,
    store.dashboard?.workout?.exercises.first?.prescription.startingWeightKg,
  ]
}

extension PendingSetQueueTests {
  @Suite("A frequência e a carga do plano na store")
  @MainActor
  struct StoreAttendanceTests {
    init() {
      FakeNetwork.reset()
      resetLocalState()
    }

    @Test("o plano fica com a série mais pesada da sessão, não com a última")
    func planKeepsTheTopSet() async {
      let store = await lojaComPainel()
      #expect(planWeight(store) == [40, 40])

      _ = await store.record(
        key: workKey("supino-reto", 2), weightKg: 38, reps: 10, completed: true, toFailure: true)?
        .value
      #expect(planWeight(store) == [42.5, 42.5])

      _ = await store.record(
        key: workKey("supino-reto", 2), weightKg: 45, reps: 8, completed: true, toFailure: true)?
        .value
      #expect(planWeight(store) == [45, 45])
    }

    @Test("a resposta do servidor antigo também fica com a série mais pesada")
    func acceptedDashboardKeepsTheTopSet() async {
      let store = await lojaComPainel()
      FakeNetwork.offline = false
      let outcome = await store.record(
        key: workKey("supino-reto", 2), weightKg: 38, reps: 10, completed: true, toFailure: true)?
        .value
      #expect(outcome == .applied)
      #expect(planWeight(store) == [42.5, 42.5])
    }
  }
}
