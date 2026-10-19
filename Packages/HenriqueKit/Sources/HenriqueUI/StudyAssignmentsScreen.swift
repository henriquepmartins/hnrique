import HenriqueCore
import SwiftUI

public struct StudyAssignmentsScreen: View {
  @Environment(EstudosStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var filter: AssignmentFilter = .todas
  @State private var switched = false
  @State private var selectedDay: CalendarDate?
  /// Entregas que acabaram de trocar de estado. Ficam na lista mesmo fora do
  /// filtro até o check aparecer, e só então saem com transição.
  @State private var settling: Set<String> = []

  public init() {}

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        switch store.assignments {
        case .idle, .loading:
          StudyLoadingState().transition(.opacity)
        case .failed(let message):
          StudyFailedState(message: message) { Task { await store.loadAssignments(force: true) } }
            .transition(.opacity)
        case .ready(let groups):
          content(groups).transition(.opacity)
        }
      }
      .animation(Motion.resolve(Motion.crossfade, reduceMotion), value: store.assignments.phase)
      .padding(.horizontal, 16)
      .padding(.bottom, 32)
    }
    .studyPage()
    // O overview manda no dia dos rótulos. Abrir direto nesta aba, sem passar
    // pela home, deixaria "hoje" e "amanhã" contando pela data do aparelho.
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

  /// O dia dos rótulos "hoje" e "amanhã". O atraso não sai daqui: ele compara
  /// o prazo com o instante atual, e não com o meio-dia deste dia.
  private var today: CalendarDate {
    store.overview.value?.date ?? CalendarDate(Date(), in: StudyFormat.calendar)
  }

  @ViewBuilder
  private func content(_ groups: [AssignmentGroup]) -> some View {
    let now = Date()
    let all = groups.flatMap(\.items)

    StudyHeading(title: "entregas")

    syncCallout()

    StudyAssignmentsCalendarCard(assignments: all, now: now, selectedDay: $selectedDay)

    AssignmentAppleCalendarCard(assignments: all)

    if let day = selectedDay {
      let label = StudyFormat.dayLabel(day, today: today)
      Button { selectedDay = nil } label: {
        HStack(spacing: 4) {
          Image(systemName: "calendar").imageScale(.small)
          Text(label)
          Image(systemName: "xmark.circle.fill").foregroundStyle(Color.studyInk40)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(Color.studyInk)
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .background(StudyPillTone.neutral.background, in: .capsule)
      }
      .buttonStyle(StudyPressStyle(slop: 6))
      .accessibilityLabel("tirar filtro de \(label)")
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
                  setStatus(of: item, to: next)
                }
                .firstEntrance(index: entry.start + index, settled: switched)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
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

  private func setStatus(of item: StudyAssignment, to next: AssignmentStatus) {
    settling.insert(item.id)
    Task {
      async let save: Void = store.setStatus(of: item, to: next)
      try? await Task.sleep(for: .milliseconds(600))
      _ = withAnimation(Motion.resolve(Motion.swap, reduceMotion)) {
        settling.remove(item.id)
      }
      await save
    }
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
      .accessibilityIdentifier("entregas.sync")
    } else {
      StudyCallout(
        icon: "arrow.triangle.2.circlepath", tone: .sky, title: "portal a cada 15 min"
      )
      .accessibilityHint("a varredura só cria o que ainda não existe")
      .accessibilityIdentifier("entregas.sync")
    }
  }

  private func visibleGroups(_ groups: [AssignmentGroup], now: Date) -> [VisibleGroup] {
    var visible: [VisibleGroup] = []
    var start = 0
    for group in groups {
      // Com dia marcado no calendário, a lista mostra só ele.
      if let day = selectedDay, group.date != day { continue }
      let items = group.items.filter {
        filter.matches($0, now: now) || settling.contains($0.id)
      }
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
    case .atrasadas: assignment.isOverdue(at: now)
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
