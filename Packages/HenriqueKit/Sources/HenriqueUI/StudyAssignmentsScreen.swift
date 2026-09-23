import HenriqueCore
import SwiftUI

public struct StudyAssignmentsScreen: View {
  @Environment(EstudosStore.self) private var store
  @State private var filter: AssignmentFilter = .todas
  @State private var switched = false
  @State private var selectedDay: CalendarDate?

  public init() {}

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        switch store.assignments {
        case .idle, .loading:
          StudyLoadingState().transition(.blurReplace)
        case .failed(let message):
          StudyFailedState(message: message) { Task { await store.loadAssignments(force: true) } }
            .transition(.blurReplace)
        case .ready(let groups):
          content(groups).transition(.blurReplace)
        }
      }
      .animation(Motion.crossfade, value: store.assignments.phase)
      .padding(.horizontal, 16)
      .padding(.bottom, 32)
    }
    .studyPage()
    // O overview manda no relógio da tela. Abrir direto nesta aba, sem passar
    // pela home, deixaria "atrasada" contando pela data do aparelho.
    .task {
      async let list: Void = store.loadAssignments()
      async let day: Void = store.loadOverview()
      _ = await (list, day)
    }
    .refreshable {
      async let list: Void = store.loadAssignments(force: true)
      async let day: Void = store.loadOverview(force: true)
      _ = await (list, day)
    }
  }

  /// O relógio da tela é o meio-dia do dia que o overview trouxe, e não o
  /// instante do desenho, para "atrasada" não mudar de resposta no meio da tela.
  private var today: CalendarDate {
    store.overview.value?.date ?? CalendarDate(Date(), in: StudyFormat.calendar)
  }

  @ViewBuilder
  private func content(_ groups: [AssignmentGroup]) -> some View {
    let now = today.date(in: StudyFormat.calendar)
    let all = groups.flatMap(\.items)

    StudyHeading(title: "entregas")

    syncCallout()

    StudyAssignmentsCalendarCard(assignments: all, now: now, selectedDay: $selectedDay)

    AssignmentAppleCalendarCard(assignments: all)

    if let day = selectedDay {
      HStack(spacing: 8) {
        StudyPill(
          tone: .neutral, systemImage: "calendar",
          text: StudyFormat.dayLabel(day, today: today))
        Button("limpar") { selectedDay = nil }
          .font(.footnote.weight(.medium))
          .foregroundStyle(Color.studyInk60)
          .buttonStyle(StudyPressStyle(slop: 13))
        Spacer(minLength: 0)
      }
    }

    ScrollView(.horizontal) {
      HStack(spacing: Space.s) {
        ForEach(AssignmentFilter.allCases) { entry in
          StudyChip(
            label: entry.label, count: count(of: entry, in: groups, now: now),
            isActive: entry == filter
          ) {
            switched = true
            filter = entry
          }
        }
      }
      .padding(.horizontal, 16)
    }
    .scrollIndicators(.hidden)
    .padding(.horizontal, -16)

    VStack(alignment: .leading, spacing: 20) {
      let visible = visibleGroups(groups, now: now)
      if visible.isEmpty {
        StudyEmptyState(
          icon: "checkmark.circle", title: filter.emptyTitle, detail: filter.emptyDetail)
      } else {
        ForEach(visible, id: \.group.id) { entry in
          VStack(alignment: .leading, spacing: 0) {
            StudyGroupLabel(left: StudyFormat.dayLabel(entry.group.date, today: today))
            VStack(spacing: 8) {
              ForEach(Array(entry.group.items.enumerated()), id: \.element.id) { index, item in
                StudyTaskCard(assignment: item, now: now) { next in
                  Task { await store.setStatus(of: item, to: next) }
                }
                .firstEntrance(index: entry.start + index, settled: switched)
              }
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .id("\(filter.rawValue)-\(selectedDay?.iso ?? "")")
    .transition(.opacity)
    .animation(Motion.swap, value: filter)
    .onChange(of: selectedDay) { switched = true }
  }

  private func count(of entry: AssignmentFilter, in groups: [AssignmentGroup], now: Date) -> Int {
    groups.reduce(0) { total, group in
      total + group.items.count { entry.matches($0, now: now) }
    }
  }

  /// O sync roda no servidor e o app mostra em que pé ele está. Com sync, a
  /// hora e as novas. Sem sync, o aviso de que o portal chega sozinho.
  @ViewBuilder
  private func syncCallout() -> some View {
    if let sync = store.overview.value?.lastSync {
      StudyCallout(
        icon: "arrow.triangle.2.circlepath", tone: .sky,
        title: "sincronizado \(StudyFormat.relative(sync.completedAt, now: Date()))",
        detail: sync.createdCount == 1 ? "1 nova" : "\(sync.createdCount) novas")
    } else {
      StudyCallout(
        icon: "arrow.triangle.2.circlepath", tone: .sky,
        title: "o portal chega sozinho",
        detail:
          "a varredura roda de quinze em quinze minutos e só cria o que ainda não existe.")
    }
  }

  private func visibleGroups(_ groups: [AssignmentGroup], now: Date) -> [VisibleGroup] {
    var visible: [VisibleGroup] = []
    var start = 0
    for group in groups {
      // Com dia marcado no calendário, a lista mostra só ele.
      if let day = selectedDay, group.date != day { continue }
      let items = group.items.filter { filter.matches($0, now: now) }
      guard !items.isEmpty else { continue }
      visible.append(
        VisibleGroup(group: AssignmentGroup(date: group.date, items: items), start: start))
      start += items.count
    }
    return visible
  }
}

private struct VisibleGroup {
  let group: AssignmentGroup
  /// Onde a cascata do grupo continua, para o atraso não reiniciar a cada dia.
  let start: Int
}

/// Os cinco filtros da tela, com a regra e o título do vazio no mesmo lugar. Um
/// filtro novo entra aqui inteiro e a barra de chips o mostra sem mais nada.
enum AssignmentFilter: String, Hashable, CaseIterable, Identifiable {
  case todas, atrasadas, semana, mes, feitas

  var id: String { rawValue }

  var label: String {
    switch self {
    case .todas: "todas"
    case .atrasadas: "atrasadas"
    case .semana: "semana"
    case .mes: "mês"
    case .feitas: "feitas"
    }
  }

  func matches(_ assignment: StudyAssignment, now: Date) -> Bool {
    switch self {
    case .todas: true
    case .atrasadas: assignment.status != .done && assignment.dueAt < now
    case .semana: assignment.status != .done && assignment.dueAt <= now.addingDays(7)
    case .mes: assignment.status != .done && assignment.dueAt <= now.addingDays(30)
    case .feitas: assignment.status == .done
    }
  }

  var emptyTitle: String {
    switch self {
    case .todas: "sem entregas"
    case .atrasadas: "nada atrasado"
    case .semana: "semana livre"
    case .mes: "mês livre"
    case .feitas: "nada feito"
    }
  }

  var emptyDetail: String? {
    self == .todas ? "as do moodle entram sozinhas na próxima sincronização." : nil
  }
}

extension Date {
  fileprivate func addingDays(_ days: Int) -> Date {
    addingTimeInterval(Double(days) * 86400)
  }
}
