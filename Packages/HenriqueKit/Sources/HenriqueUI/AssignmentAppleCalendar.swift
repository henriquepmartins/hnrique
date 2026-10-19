import EventKit
import HenriqueCore
import SwiftUI

/// Espelha as entregas pendentes num calendário do sistema, para o prazo
/// aparecer no Apple Calendar. Só o mapeamento entrega -> evento mora no
/// aparelho. O que decide criar, atualizar e apagar é o plano puro do Core,
/// e aqui só executa.
@MainActor
@Observable
final class AssignmentCalendarSync {
  enum State: Equatable {
    case idle
    case syncing
    case synced(count: Int)
    case denied
    case failed(String)
  }

  private(set) var state: State = .idle
  private let store = EKEventStore()
  private let mappingKey = "henrique.assignmentCalendarMap"
  private let calendarKey = "henrique.assignmentCalendarID"

  var mappedCount: Int { mapping.count }

  /// Já liberado antes. Só aí a lista pode ressincronizar sozinha, sem o
  /// pedido de acesso surgir na frente do dono.
  var hasAccess: Bool {
    switch EKEventStore.authorizationStatus(for: .event) {
    case .writeOnly, .fullAccess: true
    default: false
    }
  }

  private var mapping: [String: String] {
    get { UserDefaults.standard.dictionary(forKey: mappingKey) as? [String: String] ?? [:] }
    set { UserDefaults.standard.set(newValue, forKey: mappingKey) }
  }

  /// Pede acesso de escrita e leva o calendário do sistema ao estado da lista.
  /// Feita ou apagada sai do calendário, e não vira evento riscado, porque o
  /// riscado já mora na aba de feitas.
  func sync(_ assignments: [StudyAssignment]) async {
    state = .syncing
    do {
      let granted = try await store.requestWriteOnlyAccessToEvents()
      guard granted else {
        state = .denied
        return
      }
      let calendar = try resolveCalendar()
      let plan = planCalendarExport(assignments: assignments, mapped: mapping)
      var mapping = mapping
      for doomed in plan.removeEventIDs {
        if let event = store.calendarItem(withIdentifier: doomed) as? EKEvent {
          try store.remove(event, span: .thisEvent, commit: false)
        }
        mapping = mapping.filter { $0.value != doomed }
      }
      for assignment in plan.update {
        guard let event = store.calendarItem(withIdentifier: mapping[assignment.id] ?? "")
          as? EKEvent
        else {
          mapping.removeValue(forKey: assignment.id)
          continue
        }
        fill(event, with: assignment, in: calendar)
        try store.save(event, span: .thisEvent, commit: false)
      }
      for assignment in plan.create {
        let event = EKEvent(eventStore: store)
        fill(event, with: assignment, in: calendar)
        try store.save(event, span: .thisEvent, commit: false)
        mapping[assignment.id] = event.calendarItemIdentifier
      }
      try store.commit()
      self.mapping = mapping
      let pending = assignments.count { $0.status != .done }
      state = .synced(count: pending)
    } catch {
      state = .failed("não sincronizou")
    }
  }

  func openSettings() {
    #if os(iOS)
      guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
      UIApplication.shared.open(url)
    #endif
  }

  private func fill(_ event: EKEvent, with assignment: StudyAssignment, in calendar: EKCalendar) {
    event.calendar = calendar
    event.title = assignment.title
    event.startDate = assignment.dueAt
    event.endDate = assignment.dueAt.addingTimeInterval(3600)
    var notes = "h&nrique · entrega \(assignment.id)"
    if let url = assignment.url, !url.isEmpty { notes += "\n\(url)" }
    event.notes = notes
    if let url = assignment.url.flatMap(URL.init(string:)) { event.url = url }
  }

  private func resolveCalendar() throws -> EKCalendar {
    if let id = UserDefaults.standard.string(forKey: calendarKey),
      let found = store.calendar(withIdentifier: id)
    {
      return found
    }
    let calendar = EKCalendar(for: .event, eventStore: store)
    calendar.title = "estudos"
    calendar.source =
      store.defaultCalendarForNewEvents?.source
      ?? store.sources.first { $0.sourceType == .local }
      ?? store.sources.first { $0.sourceType == .calDAV }
    try store.saveCalendar(calendar, commit: true)
    UserDefaults.standard.set(calendar.calendarIdentifier, forKey: calendarKey)
    return calendar
  }
}

/// A linha do Apple Calendar dentro de entregas. Mostra em que pé está e
/// sincroniza as pendentes com um toque.
struct AssignmentAppleCalendarCard: View {
  let assignments: [StudyAssignment]
  @State private var sync = AssignmentCalendarSync()

  var body: some View {
    StudyDbList {
      StudyDbRow(
        icon: "calendar.badge.plus",
        title: "Apple Calendar",
        detail: detail,
        end: {
          Group {
            switch sync.state {
            case .syncing:
              ProgressView().controlSize(.small)
            case .synced(let count):
              Text(events(count))
            case .denied:
              Text("abrir ajustes")
            case .failed:
              Text("tentar de novo")
            case .idle:
              Text(sync.mappedCount > 0 ? events(sync.mappedCount) : "sincronizar")
            }
          }
          .font(.caption)
          .monospacedDigit()
          .foregroundStyle(Color.studyInk40)
        }
      ) {
        if case .denied = sync.state {
          sync.openSettings()
        } else {
          Task { await sync.sync(assignments) }
        }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("sincronizar entregas com o Apple Calendar")
    .accessibilityIdentifier("entregas.apple-calendar")
    .accessibilityValue(detail ?? "")
    // Concluir uma entrega tira o evento do calendário na hora, sem esperar
    // outro toque aqui.
    .task(id: assignments.map { "\($0.id)\($0.status)\($0.dueAt)" }) {
      guard sync.mappedCount > 0, sync.hasAccess, sync.state != .syncing else { return }
      await sync.sync(assignments)
    }
  }

  private func events(_ count: Int) -> String {
    count == 1 ? "1 evento" : "\(count) eventos"
  }

  private var detail: String? {
    switch sync.state {
    case .idle:
      return sync.mappedCount > 0 ? "leva os prazos ao calendário do iphone" : nil
    case .syncing:
      return "sincronizando"
    case .synced:
      return "prazos no calendário do iphone"
    case .denied:
      return "acesso negado"
    case .failed:
      return "falhou, toque para tentar de novo"
    }
  }
}
