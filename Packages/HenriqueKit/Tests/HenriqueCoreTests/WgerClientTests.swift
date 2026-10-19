import Foundation
import Testing

@testable import HenriqueCore

/// Responde a lista da wger com dois exercícios de "curl": um de bíceps e um
/// de posterior.
final class WgerStub: URLProtocol, @unchecked Sendable {
  static let body = """
    {"results": [
      {"id": 1, "category": {"name": "Arms"}, "muscles": [{"name": "Biceps brachii", "name_en": "Biceps"}],
       "equipment": [{"name": "Dumbbell"}], "images": [{"image": "https://wger.de/a.png", "is_main": true}],
       "translations": [{"name": "Hammer curl", "language": 2}]},
      {"id": 2, "category": {"name": "Legs"}, "muscles": [{"name": "Biceps femoris", "name_en": "Hamstrings"}],
       "equipment": [{"name": "Machine"}], "images": [{"image": "https://wger.de/b.png", "is_main": true}],
       "translations": [{"name": "Leg curl", "language": 2}]}
    ]}
    """

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}

  override func startLoading() {
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
}

struct WgerClientTests {
  private func client() -> WgerClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [WgerStub.self]
    return WgerClient(session: URLSession(configuration: configuration))
  }

  @Test("o grupo escolhido filtra os resultados da wger como filtra os locais")
  func muscleFiltersRemoteResults() async throws {
    let wger = client()
    let all = try await wger.search("curl", excluding: [])
    #expect(Set(all.map(\.muscleGroup)) == ["Bíceps", "Posterior"])
    let biceps = try await wger.search("curl", muscle: "Bíceps", excluding: [])
    #expect(biceps.map(\.name) == ["Hammer curl"])
  }
}
