import Foundation
import Testing

@testable import HenriqueCore

/// Um servidor falso que responde o mesmo status a qualquer rota, ou derruba a
/// conexão quando `status` é nulo.
final class StubServer: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var status: Int? = 401

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}

  override func startLoading() {
    guard let status = Self.status else {
      client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
      return
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(#"{"message":"Invalid username or password"}"#.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  static func client(token: String? = nil) -> APIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubServer.self]
    return APIClient(
      baseURL: URL(string: "http://localhost:3001")!,
      tokenStore: MemoryTokenStore(token: token),
      session: URLSession(configuration: configuration))
  }
}

@Suite("Erros do cliente", .serialized)
struct APIClientErrorTests {
  @Test("senha errada no login não vira sessão expirada")
  func signInRejectsCredentials() async throws {
    StubServer.status = 401
    let client = StubServer.client()
    let error = await #expect(throws: APIError.self) {
      try await client.signIn(username: "henrique", password: "errada")
    }
    #expect(error == .invalidCredentials)
    #expect(error?.message == "usuário ou senha incorretos")
  }

  @Test("401 numa rota com sessão derruba o token e diz que a sessão expirou")
  func authenticatedCallExpires() async throws {
    StubServer.status = 401
    let client = StubServer.client(token: "sessao")
    let error = await #expect(throws: APIError.self) {
      _ = try await client.studySubjects()
    }
    #expect(error == .unauthorized)
    #expect(error?.message == "sessão expirou")
    #expect(await client.isSignedIn == false)
  }

  @Test("sem servidor a mensagem não mostra o endereço e a casca fica sabendo")
  func transportHidesHost() async throws {
    StubServer.status = nil
    let client = StubServer.client(token: "sessao")
    let error = await #expect(throws: APIError.self) {
      _ = try await client.studySubjects()
    }
    #expect(error?.message == "sem conexão")
    #expect(await client.connectivity.isOffline == true)

    StubServer.status = 500
    _ = try? await client.studySubjects()
    #expect(await client.connectivity.isOffline == false)
  }
}
