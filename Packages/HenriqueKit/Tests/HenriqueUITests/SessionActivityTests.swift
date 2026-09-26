import Foundation
import HenriqueCore
import Testing

@testable import HenriqueUI

/// A atividade sem o ActivityKit: guarda o que a store pediu.
@MainActor
final class FakeSessionActivity: SessionActivity {
  var current: SetActivityAttributes?
  var state: SetActivityState?
  var ended: [(state: SetActivityState?, immediately: Bool)] = []

  func start(_ attributes: SetActivityAttributes, _ state: SetActivityState) {
    current = attributes
    self.state = state
  }
  func update(_ state: SetActivityState) { self.state = state }
  func end(_ state: SetActivityState?, immediately: Bool) {
    current = nil
    ended.append((state, immediately))
  }
  func flush() async {}
}

/// O retrato do painel de cada teste mora num arquivo só dele: o da suíte é o
/// mesmo de todos os testes que carregam painel.
@MainActor
private func activityStore(
  _ activity: FakeSessionActivity, snapshot: URL? = nil
) -> AcademiaStore {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [FakeNetwork.self]
  let client = APIClient(
    baseURL: URL(string: "https://exemplo.invalido")!,
    tokenStore: MemoryTokenStore(),
    session: URLSession(configuration: configuration))
  let store = AcademiaStore(
    client: client, restAlarm: FakeRestAlarm(), activity: activity,
    defaults: UserDefaults(suiteName: testDefaultsSuite)!,
    snapshotURL: snapshot ?? FileManager.default.temporaryDirectory
      .appending(path: "henrique-teste-\(UUID().uuidString).json"))
  store.resendsAutomatically = false
  return store
}

@MainActor
private func storeWithDashboard(_ activity: FakeSessionActivity) async -> AcademiaStore {
  FakeNetwork.offline = false
  let store = activityStore(activity)
  await store.start()
  FakeNetwork.offline = true
  return store
}

private func key(_ exercise: String, _ kind: SetKind, _ index: Int, on date: CalendarDate = .today)
  -> SetKey
{
  SetKey(date: date, templateId: "tpl-terca", exerciseId: exercise, kind: kind, index: index)
}

@MainActor
private func isDone(_ store: AcademiaStore, _ key: SetKey) -> Bool {
  completionDate(in: store, key: key) != nil
}

/// Dentro da suíte da fila, que é serial: a rede falsa, a fila em disco e os
/// `UserDefaults` são os mesmos para todas.
extension PendingSetQueueTests {
  @Suite("A Live Activity da sessão")
  @MainActor
  struct SessionActivityTests {
    init() {
      FakeNetwork.reset()
      resetLocalState()
    }

    @Test("a primeira série marcada abre a atividade com a série seguinte e o descanso")
    func startsOnFirstSet() async throws {
      let activity = FakeSessionActivity()
      let store = await storeWithDashboard(activity)
      _ = await store.record(
        key: key("supino-reto", .work, 2), weightKg: 42.5, reps: 8, completed: true, toFailure: true)?
        .value

      let attributes = try #require(activity.current)
      #expect(attributes.date == .today)
      #expect(attributes.templateId == "tpl-terca")
      #expect(attributes.workoutName == "empurrar a")
      let state = try #require(activity.state)
      #expect(state.up?.exerciseName == "desenvolvimento com halteres")
      #expect(state.up?.setLabel == "A1")
      #expect(state.up?.weight == "10 kg")
      #expect(state.up?.reps == 12)
      #expect(state.up?.target == key("desenvolvimento", .prep, 1))
      #expect(state.done == 2)
      #expect(state.total == 4)
      let rest = try #require(store.rest)
      #expect(state.rest == rest.startedAt...rest.endsAt)
    }

    @Test("o feito de ontem não marca e fecha a atividade")
    func refusesYesterday() async {
      let activity = FakeSessionActivity()
      let store = await storeWithDashboard(activity)
      activity.current = SetActivityAttributes(
        date: .today.adding(days: -1), templateId: "tpl-terca", workoutName: "empurrar a", toneHex: nil)

      await store.completeFromActivity(key("supino-reto", .work, 2, on: .today.adding(days: -1)))

      #expect(store.unsentCount == 0)
      #expect(FakeNetwork.recordedSets == 0)
      #expect(activity.ended.count == 1)
      #expect(store.selectedDate == .today)
    }

    @Test("sem painel e sem rede não marca nada")
    func noDashboardNoNetwork() async {
      let activity = FakeSessionActivity()
      let store = activityStore(activity)
      #expect(store.dashboard == nil)

      await store.completeFromActivity(key("supino-reto", .work, 2))

      #expect(store.isSignedIn)
      #expect(store.dashboard == nil)
      #expect(store.unsentCount == 0)
      #expect(FakeNetwork.recordedSets == 0)
    }

    @Test("série já feita não marca a seguinte")
    func doneSetIsIdempotent() async {
      let activity = FakeSessionActivity()
      let store = await storeWithDashboard(activity)
      #expect(isDone(store, key("supino-reto", .work, 1)))

      await store.completeFromActivity(key("supino-reto", .work, 1))

      #expect(store.unsentCount == 0)
      #expect(!isDone(store, key("supino-reto", .work, 2)))
      #expect(store.rest == nil)
    }

    @Test("série válida entra na fila com a carga da linha e fica em disco")
    func queuesValidSet() async throws {
      let activity = FakeSessionActivity()
      let store = await storeWithDashboard(activity)
      let target = key("supino-reto", .work, 2)

      await store.completeFromActivity(target)
      await store.completeFromActivity(target)

      #expect(store.unsentCount == 1)
      #expect(store.isWaiting(target))
      let set = try #require(
        store.dashboard?.workout?.exercises.first { $0.id == "supino-reto" }?.sets.work.first { $0.index == 2 })
      #expect(set.isDone)
      #expect(set.weightKg == 42.5)
      #expect(set.reps == 10)
      #expect(!isDone(store, key("desenvolvimento", .prep, 1)))
      #expect(store.rest?.key == target)
      #expect(activityStore(FakeSessionActivity()).isWaiting(target))
    }

    @Test("a última série valendo fecha a atividade com o placar final")
    func endsWhenWorkSetsRunOut() async throws {
      let activity = FakeSessionActivity()
      let store = await storeWithDashboard(activity)
      for target in [
        key("supino-reto", .work, 2), key("desenvolvimento", .work, 1), key("desenvolvimento", .work, 2),
      ] {
        _ = await store.record(key: target, weightKg: 20, reps: 10, completed: true, toFailure: false)?.value
      }
      let last = try #require(activity.ended.last)
      #expect(!last.immediately)
      #expect(last.state?.up == nil)
      #expect(last.state?.done == 4)
      #expect(activity.current == nil)
    }

    @Test("sair da conta fecha a atividade na hora")
    func signOutEndsImmediately() async {
      let activity = FakeSessionActivity()
      let store = await storeWithDashboard(activity)
      _ = await store.record(
        key: key("supino-reto", .work, 2), weightKg: 42.5, reps: 8, completed: true, toFailure: true)?
        .value
      await store.signOut(discardingUnsent: true)
      #expect(activity.ended.last?.immediately == true)
    }
  }
}
