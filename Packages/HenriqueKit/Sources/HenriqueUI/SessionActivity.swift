import Foundation
import HenriqueCore

#if canImport(ActivityKit) && os(iOS)
  import ActivityKit
#endif

/// A Live Activity da sessão de treino. Protocolo para os testes da store não
/// tocarem no ActivityKit, como `RestAlarm`.
@MainActor
protocol SessionActivity: AnyObject {
  /// O treino da atividade no ar, inclusive uma que sobrou de outra abertura do app.
  var current: SetActivityAttributes? { get }
  func start(_ attributes: SetActivityAttributes, _ state: SetActivityState)
  func update(_ state: SetActivityState)
  /// `state` nulo mantém o último conteúdo. Sem `immediately`, fica 15 min na tela.
  func end(_ state: SetActivityState?, immediately: Bool)
  /// Espera o sistema receber a última mudança. O "feito" roda com o app no
  /// fundo, e o processo pode ser suspenso logo depois.
  func flush() async
}

@MainActor
final class NoSessionActivity: SessionActivity {
  var current: SetActivityAttributes? { nil }
  func start(_ attributes: SetActivityAttributes, _ state: SetActivityState) {}
  func update(_ state: SetActivityState) {}
  func end(_ state: SetActivityState?, immediately: Bool) {}
  func flush() async {}
}

#if canImport(ActivityKit) && os(iOS)
  /// `Activity` não é `Sendable`. A store guarda só o id e os atributos; quem
  /// mexe na atividade procura ela pelo id, fora do ator principal.
  @MainActor
  final class AcademiaSessionActivity: SessionActivity {
    private var live: (id: String, attributes: SetActivityAttributes)?
    private var sent: SetActivityState?
    /// Pedir, atualizar e encerrar são assíncronos. Encadear mantém a ordem.
    private var tail: Task<Void, Never>?

    init() {
      live = Activity<SetActivityAttributes>.activities
        .first { $0.activityState == .active || $0.activityState == .stale }
        .map { ($0.id, $0.attributes) }
    }

    var current: SetActivityAttributes? { live?.attributes }

    func start(_ attributes: SetActivityAttributes, _ state: SetActivityState) {
      if live?.attributes == attributes {
        update(state)
        return
      }
      end(nil, immediately: true)
      guard ActivityAuthorizationInfo().areActivitiesEnabled,
        let activity = try? Activity.request(attributes: attributes, content: Self.content(state))
      else { return }
      live = (activity.id, attributes)
      sent = state
    }

    func update(_ state: SetActivityState) {
      guard let id = live?.id, state != sent else { return }
      sent = state
      let content = Self.content(state)
      chain { await Self.find(id)?.update(content) }
    }

    func end(_ state: SetActivityState?, immediately: Bool) {
      guard let id = live?.id else { return }
      live = nil
      sent = nil
      let content = state.map(Self.content)
      let policy: ActivityUIDismissalPolicy = immediately ? .immediate : .after(.now + 15 * 60)
      chain { await Self.find(id)?.end(content, dismissalPolicy: policy) }
    }

    func flush() async { await tail?.value }

    private func chain(_ work: @escaping @Sendable () async -> Void) {
      let previous = tail
      tail = Task.detached {
        await previous?.value
        await work()
      }
    }

    private nonisolated static func find(_ id: String) -> Activity<SetActivityAttributes>? {
      Activity<SetActivityAttributes>.activities.first { $0.id == id }
    }

    /// Passado o descanso, o conteúdo fica velho e a atividade troca o
    /// contador por "vai" sem o app acordar.
    private static func content(_ state: SetActivityState) -> ActivityContent<SetActivityState> {
      ActivityContent(state: state, staleDate: state.rest?.upperBound ?? .now + 30 * 60)
    }
  }
#endif
