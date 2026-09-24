import Foundation
import HenriqueCore
import Testing

@testable import HenriqueUI

/// O servidor do foco. A primeira lista demora, para a sessão parada cair no
/// meio de uma sincronização que já passou da fila.
final class FocoNetwork: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var saved: [UUID] = []
  nonisolated(unsafe) static var listCalls = 0

  static func reset() {
    saved = []
    listCalls = 0
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}

  override func startLoading() {
    switch request.url?.path {
    case Route.focoSave.rawValue:
      let entries = (Self.body(of: request)?["entries"] as? [[String: Any]]) ?? []
      let ids = entries.compactMap { ($0["id"] as? String).flatMap(UUID.init(uuidString:)) }
      Self.saved += ids
      let list = ids.map { "\"\($0.uuidString.lowercased())\"" }.joined(separator: ",")
      answer(#"{"saved":[\#(list)]}"#)
    case Route.focoList.rawValue:
      Self.listCalls += 1
      let delay = Self.listCalls == 1 ? 0.3 : 0
      DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
        self.answer(#"{"entries":[],"dailyGoalMinutes":null}"#)
      }
    default:
      answer("{}")
    }
  }

  private func answer(_ body: String) {
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  private static func body(of request: URLRequest) -> [String: Any]? {
    var data = request.httpBody ?? Data()
    if data.isEmpty, let stream = request.httpBodyStream {
      stream.open()
      defer { stream.close() }
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: buffer.count)
        guard read > 0 else { break }
        data.append(buffer, count: read)
      }
    }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }
}

@Suite("Foco sincronizando", .serialized)
@MainActor
struct FocoSyncTests {
  private let url = FileManager.default.temporaryDirectory
    .appending(path: "foco-\(UUID().uuidString).json")

  private func makeEstudos() -> EstudosStore {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FocoNetwork.self]
    let client = APIClient(
      baseURL: URL(string: "https://exemplo.invalido")!,
      tokenStore: HenriqueCore.MemoryTokenStore(token: "sessao"),
      session: URLSession(configuration: configuration))
    return EstudosStore(client: client, snapshotURL: nil)
  }

  @Test("a sessão parada enquanto outra sincronização roda sobe sem reabrir o app")
  func stopDuringSyncUploads() async throws {
    defer { try? FileManager.default.removeItem(at: url) }
    FocoNetwork.reset()
    var ledger = FocoLedger()
    ledger.start(.alemao, at: .now.addingTimeInterval(-120), calendar: StudyFormat.calendar)
    try JSONEncoder.henrique().encode(ledger).write(to: url)
    let store = FocoStore(fileURL: url, estudos: makeEstudos())

    let first = Task { await store.sync() }
    while FocoNetwork.listCalls == 0 { try await Task.sleep(for: .milliseconds(10)) }
    store.stop()
    let stopped = try #require(store.ledger.entries.first)
    await first.value
    for _ in 0..<100 where !store.ledger.pendingUploads.isEmpty {
      try await Task.sleep(for: .milliseconds(20))
    }

    #expect(FocoNetwork.saved == [stopped.id])
    #expect(store.ledger.pendingUploads.isEmpty)
  }
}
