import Foundation
import HenriqueCore
import UserNotifications

/// O aviso do fim do descanso com o app no fundo. Protocolo para os testes da
/// store não tocarem na central de notificações do sistema.
@MainActor
protocol RestAlarm {
  func schedule(at date: Date, next: NextSet?)
  func cancel()
}

/// "puxada alta · 48 kg", ou "puxada alta · A · 35 kg" no aquecimento.
func restAlarmBody(_ next: NextSet?) -> String {
  guard let next else { return "hora da próxima série" }
  let warmup = next.kind == .prep ? " · A" : ""
  return "\(next.exerciseName.lowercased())\(warmup) · \(Formatting.trim(next.weightKg)) kg"
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

  func schedule(at date: Date, next: NextSet?) {
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
      content.body = restAlarmBody(next)
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
