import Foundation
import HenriqueCore
import SwiftUI
import UserNotifications

/// O aviso do fim do descanso com o app no fundo. Protocolo para os testes da
/// store não tocarem na central de notificações do sistema.
@MainActor
protocol RestAlarm {
  func schedule(at date: Date, next: NextSet?)
  func cancel()
}

func restAlarmBody(_ next: NextSet?) -> String {
  next?.summary ?? "hora da próxima série"
}

/// Um aviso só, sempre com o mesmo identificador: agendar de novo substitui o
/// anterior, então ±15 s não empilha avisos.
@MainActor
final class AcademiaRestAlarm: RestAlarm {
  nonisolated static let identifier = "academia.descanso.fim"
  /// Pedir, agendar e cancelar são assíncronos na central. Encadear evita que um
  /// cancelar chegue antes do agendar que ele deveria desfazer.
  private var tail: Task<Void, Never>?

  /// O executável de teste não é um app, e a central derruba o processo sem
  /// identificador de pacote.
  nonisolated static var isApp: Bool { Bundle.main.bundleURL.pathExtension == "app" }

  init() {
    if Self.isApp { UNUserNotificationCenter.current().delegate = RestAlarmPresenter.shared }
  }

  /// Nulo fora de um app.
  static func authorizationStatus() async -> UNAuthorizationStatus? {
    guard isApp else { return nil }
    return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
  }

  static func requestAuthorization() async -> UNAuthorizationStatus? {
    guard isApp else { return nil }
    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    return await authorizationStatus()
  }

  /// Só agenda com a permissão dada. O pedido sai do resumo, fora do treino:
  /// no primeiro "feito" o alerta do sistema caía em cima das séries.
  func schedule(at date: Date, next: NextSet?) {
    guard Self.isApp else { return }
    let previous = tail
    tail = Task {
      await previous?.value
      let center = UNUserNotificationCenter.current()
      let status = await center.notificationSettings().authorizationStatus
      guard status == .authorized || status == .provisional else { return }
      let interval = date.timeIntervalSinceNow
      guard interval >= 1 else {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        return
      }
      let content = UNMutableNotificationContent()
      content.title = "descanso completo"
      content.body = restAlarmBody(next)
      content.sound = .default
      let request = UNNotificationRequest(
        identifier: Self.identifier, content: content,
        trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
      try? await center.add(request)
    }
  }

  func cancel() {
    guard Self.isApp else { return }
    let previous = tail
    tail = Task {
      await previous?.value
      UNUserNotificationCenter.current()
        .removePendingNotificationRequests(withIdentifiers: [Self.identifier])
    }
  }
}

/// Sem um delegado, o iOS descarta o aviso com o app na frente, e o fim do
/// descanso passava em silêncio com o celular em cima do banco.
@MainActor
final class RestAlarmPresenter: NSObject, UNUserNotificationCenterDelegate {
  static let shared = RestAlarmPresenter()
  /// Com a sessão na tela a barra já diz "vai", então o aviso só toca.
  var sessionOnScreen = false

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    guard notification.request.identifier == AcademiaRestAlarm.identifier else { return [] }
    return await sessionOnScreen ? [.sound, .list] : [.banner, .sound, .list]
  }
}

/// O convite para o aviso do fim do descanso, no resumo do treino. Só aparece
/// enquanto o sistema ainda não perguntou; respondido, some de vez.
struct RestAlarmOffer: View {
  @Environment(\.accent) private var accent
  @State private var status: UNAuthorizationStatus?

  var body: some View {
    Group {
      if status == .notDetermined {
        HStack(spacing: Space.m) {
          Label("avisar quando o descanso acabar", systemImage: "bell.badge")
            .font(.subheadline).foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
          Button("ativar") {
            Task { status = await AcademiaRestAlarm.requestAuthorization() }
          }
          .buttonStyle(.bordered).tint(accent.deep)
          .accessibilityIdentifier("resumo.aviso-descanso")
        }
        .padding(Space.m)
        .background(Color.surfaceMuted, in: .rect(cornerRadius: Radius.row))
        .transition(.opacity)
      }
    }
    .animation(Motion.plain, value: status)
    .task { status = await AcademiaRestAlarm.authorizationStatus() }
  }
}
