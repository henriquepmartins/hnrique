import Foundation
import HenriqueCore
import Testing

@testable import HenriqueUI

/// Responde a lista de matérias enquanto `online` estiver ligado; fora disso a
/// conexão cai, como no ônibus sem sinal.
final class EstudosNetwork: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var online = true

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}

  override func startLoading() {
    guard Self.online, request.url?.path == Route.studySubjectList.rawValue else {
      client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
      return
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"])!
    let body = ##"[{"id":"s-eda","name":"Estruturas de Dados","color":"#0075de","code":"SCC0202","semester":3}]"##
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
}

@Suite("Estudos sem rede", .serialized)
@MainActor
struct EstudosCacheTests {
  private let url = FileManager.default.temporaryDirectory
    .appending(path: "estudos-cache-\(UUID().uuidString).json")

  private func makeStore() -> EstudosStore {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [EstudosNetwork.self]
    let client = APIClient(
      baseURL: URL(string: "https://exemplo.invalido")!,
      tokenStore: HenriqueCore.MemoryTokenStore(token: "sessao"),
      session: URLSession(configuration: configuration))
    return EstudosStore(client: client, snapshotURL: url)
  }

  @Test("a lista que chegou com rede abre sem rede no próximo lançamento")
  func subjectsSurviveARelaunchOffline() async throws {
    defer { try? FileManager.default.removeItem(at: url) }
    EstudosNetwork.online = true
    let online = makeStore()
    await online.loadSubjects()
    #expect(online.subjects.value?.map(\.name) == ["Estruturas de Dados"])

    // A gravação sai do main actor; espera o arquivo aparecer.
    for _ in 0..<50 where EstudosSnapshot.read(from: url)?.subjects == nil {
      try await Task.sleep(for: .milliseconds(20))
    }

    EstudosNetwork.online = false
    let offline = makeStore()
    #expect(offline.subjects.value?.map(\.id) == ["s-eda"])
    await offline.loadSubjects()
    #expect(offline.subjects.value?.map(\.id) == ["s-eda"])
    #expect(offline.subjects.failure == nil)
  }

  @Test("o resumo de outro dia não volta do disco")
  func staleOverviewIsDropped() throws {
    defer { try? FileManager.default.removeItem(at: url) }
    let yesterday = CalendarDate.today.adding(days: -1)
    let overview = StudyOverview(
      date: yesterday, subjects: [], dueSoon: [], reviewCount: 3, weekMinutes: 40,
      lastSession: nil, lastSync: nil)
    try EstudosSnapshot(overview: overview, subjects: []).write(to: url)
    let store = makeStore()
    #expect(store.overview.value == nil)
    #expect(store.subjects.value == [])
  }
}
