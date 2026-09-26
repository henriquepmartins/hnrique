import Foundation
import HenriqueCore
import Testing

@testable import HenriqueUI

@MainActor
private func storeWithSnapshot(_ url: URL) -> AcademiaStore {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [FakeNetwork.self]
  let client = APIClient(
    baseURL: URL(string: "https://exemplo.invalido")!,
    tokenStore: MemoryTokenStore(),
    session: URLSession(configuration: configuration))
  let store = AcademiaStore(
    client: client, restAlarm: FakeRestAlarm(),
    defaults: UserDefaults(suiteName: testDefaultsSuite)!, snapshotURL: url)
  store.resendsAutomatically = false
  return store
}

extension PendingSetQueueTests {
  @Suite("Abrir o app depois da meia-noite")
  @MainActor
  struct ColdLaunchAfterMidnightTests {
    init() {
      FakeNetwork.reset()
      resetLocalState()
    }

    /// O painel da fixture como se fosse de ontem, com a série 2 do supino feita
    /// há `ago` segundos.
    private func snapshotOfYesterday(lastSetAgo ago: TimeInterval) throws -> URL {
      let yesterday = CalendarDate.today.adding(days: -1)
      var dashboard = try JSONDecoder.henrique().decode(Dashboard.self, from: Data(dashboardDeHoje().utf8))
      dashboard.date = yesterday
      var workout = try #require(dashboard.workout)
      let marked = Date.now - ago
      workout.exercises[0].sets.prep[0].completedAt = marked - 120
      workout.exercises[0].sets.work[0].completedAt = marked - 60
      workout.exercises[0].sets.work[1].completedAt = marked
      dashboard.workout = workout
      let url = FileManager.default.temporaryDirectory
        .appending(path: "henrique-teste-\(UUID().uuidString).json")
      try JSONEncoder.henrique().encode(dashboard).write(to: url)
      return url
    }

    @Test("treino de ontem aberto há 20 min abre no dia dele e fica depois do chaveiro")
    func opensYesterdaysOpenSession() async throws {
      let url = try snapshotOfYesterday(lastSetAgo: 20 * 60)
      let store = storeWithSnapshot(url)
      let yesterday = CalendarDate.today.adding(days: -1)
      #expect(store.selectedDate == yesterday)
      #expect(store.dashboard?.date == yesterday)

      store.followToday()
      #expect(store.selectedDate == yesterday)
      await store.start()
      try? await Task.sleep(for: .milliseconds(100))
      #expect(store.selectedDate == yesterday)
    }

    @Test("treino de ontem parado há 4 h abre no dia de hoje")
    func staleSessionOpensToday() throws {
      let url = try snapshotOfYesterday(lastSetAgo: 4 * 60 * 60)
      let store = storeWithSnapshot(url)
      #expect(store.selectedDate == .today)
      #expect(store.dashboard == nil)
    }
  }
}
