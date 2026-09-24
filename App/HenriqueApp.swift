import HenriqueCore
import HenriqueUI
import SwiftUI

@main
struct HenriqueApp: App {
  @State private var stores = AppConfiguration.makeStores()

  var body: some Scene {
    WindowGroup {
      RootView(
        store: stores.academia,
        estudos: stores.estudos,
        idiomas: stores.idiomas,
        initialSection: AppConfiguration.launch.section,
        initialTab: AppConfiguration.launch.academiaTab,
        initialEstudosTab: AppConfiguration.launch.estudosTab,
        initialIdiomasTab: AppConfiguration.launch.idiomasTab,
        openSession: AppConfiguration.launch.openSession,
        openWrite: AppConfiguration.launch.openWrite)
    }
  }
}

/// O que a linha de comando pede do app. Fora de DEBUG nada é lido, para uma
/// captura não conseguir mudar o que o dono do aparelho vê.
struct LaunchArguments: Sendable {
  var shell = false
  var section: AppSection?
  var academiaTab: AcademiaTab = .hoje
  var estudosTab: EstudosTab = .hoje
  var idiomasTab: IdiomasTab = .rotina
  var openSession = false
  var openWrite = false
}

extension LaunchArguments {
  /// `--app estudos` abre o outro app. `--aba <nome>` abre direto naquela aba,
  /// lida como aba de estudos quando veio `--app estudos`, onde ela também
  /// aceita `sessao` e `escrever`, que não são abas e sim o bloco de foco e a
  /// folha de escrever. Com `--app idiomas` a aba é `rotina`, `foco`, `revisar`
  /// ou `progresso`. Os nomes aposentados continuam valendo: `medidas` cai
  /// em progresso e `cadernos` cai em matérias, que é onde essas telas moram
  /// agora.
  ///
  /// `--casca` abre o app já dentro, sem servidor e sem conta, com as abas
  /// vazias. Serve só para capturar a casca do app quando não há sessão à mão.
  static func parse(_ arguments: [String]) -> LaunchArguments {
    var launch = LaunchArguments()
    #if DEBUG
      launch.shell = arguments.contains("--casca")
      let value = { (flag: String) -> String? in
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
          return nil
        }
        return arguments[index + 1]
      }
      launch.section = value("--app").flatMap(AppSection.init(rawValue:))
      let tab = value("--aba")
      if launch.section == .estudos {
        switch tab {
        case "sessao": launch.openSession = true
        case "escrever": launch.openWrite = true
        default: launch.estudosTab = tab.flatMap(EstudosTab.init(named:)) ?? .hoje
        }
      } else if launch.section == .idiomas {
        launch.idiomasTab = tab.flatMap(IdiomasTab.init(named:)) ?? .rotina
      }
      else if let tab, let academia = AcademiaTab(named: tab) {
        launch.academiaTab = academia
      }
    #endif
    return launch
  }
}

enum AppConfiguration {
  static let launch = LaunchArguments.parse(CommandLine.arguments)

  /// Os três apps dividem o mesmo `APIClient` para uma sessão só valer para
  /// todos e o logout de um derrubar os outros.
  @MainActor static func makeStores() -> (
    academia: AcademiaStore, estudos: EstudosStore, idiomas: IdiomasStore
  ) {
    let client = makeClient()
    let stores = (
      academia: AcademiaStore(client: client), estudos: EstudosStore(client: client),
      idiomas: IdiomasStore(client: client)
    )
    #if DEBUG
      if launch.shell {
        stores.academia.openCaptureShell()
        stores.estudos.openCaptureShell()
        stores.idiomas.openCaptureShell()
      }
    #endif
    return stores
  }

  static func makeClient() -> APIClient {
    APIClient(baseURL: baseURL, tokenStore: KeychainTokenStore())
  }

  /// O endereço da API vem do Info.plist para o build de simulador apontar para
  /// o servidor local sem recompilar o app com outra constante embutida.
  static var baseURL: URL {
    let raw = Bundle.main.object(forInfoDictionaryKey: "HenriqueAPIBaseURL") as? String
    guard let raw, let url = URL(string: raw) else {
      fatalError("HenriqueAPIBaseURL faltando ou inválida no Info.plist")
    }
    return url
  }
}
