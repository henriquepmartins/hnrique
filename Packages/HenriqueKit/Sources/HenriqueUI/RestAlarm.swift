import Foundation
import UserNotifications

/// O aviso do fim do descanso com o app no fundo. Protocolo para os testes da
/// store não tocarem na central de notificações do sistema.
@MainActor
protocol RestAlarm {
  func schedule(at date: Date)
  func cancel()
}

/// Um aviso só, sempre com o mesmo identificador: agendar de novo substitui o
/// anterior, então ±15 s não empilha avisos.
@MainActor
final class AcademiaRestAlarm: RestAlarm {
  static let identifier = "academia.descanso.fim"
  /// Pedir, agendar e cancelar são assíncronos na central. Encadear evita que um
  /// cancelar chegue antes do agendar que ele deveria desfazer.
  private var tail: Task<Void, Never>?

  /// O executável de teste não é um app, e a central derruba o processo sem
  /// identificador de pacote.
  private var isApp: Bool { Bundle.main.bundleURL.pathExtension == "app" }

  func schedule(at date: Date) {
    guard isApp else { return }
    let previous = tail
    tail = Task {
      await previous?.value
      let center = UNUserNotificationCenter.current()
      let status = await center.notificationSettings().authorizationStatus
      if status == .notDetermined {
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
      } else if status == .denied {
        return
      }
      let interval = date.timeIntervalSinceNow
      guard interval >= 1 else {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        return
      }
      let content = UNMutableNotificationContent()
      content.title = "descanso completo"
      content.body = "hora da próxima série"
      content.sound = .default
      let request = UNNotificationRequest(
        identifier: Self.identifier, content: content,
        trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
      try? await center.add(request)
    }
  }

  func cancel() {
    guard isApp else { return }
    let previous = tail
    tail = Task {
      await previous?.value
      UNUserNotificationCenter.current()
        .removePendingNotificationRequests(withIdentifiers: [Self.identifier])
    }
  }
}
