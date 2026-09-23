import HenriqueCore
import SwiftUI

public struct StudyTodayScreen: View {
  @Environment(EstudosStore.self) private var store
  let onSession: () -> Void
  let onAssignments: () -> Void
  let onReview: () -> Void

  public init(
    onSession: @escaping () -> Void, onAssignments: @escaping () -> Void,
    onReview: @escaping () -> Void
  ) {
    self.onSession = onSession
    self.onAssignments = onAssignments
    self.onReview = onReview
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        // O cabeçalho e o foco ficam fora do estado do resumo: o cronômetro é
        // local e precisa abrir mesmo quando o servidor não responde.
        StudyHeading(title: StudyFormat.weekdayLong(headingDate))
          .staggeredEntrance(index: 0, isReady: true)
        FocoTodayCard()
          .staggeredEntrance(index: 1, isReady: true)
        switch store.overview {
        case .idle, .loading:
          StudyLoadingState().transition(.blurReplace)
        case .failed(let message):
          StudyFailedState(message: message) { Task { await store.loadOverview(force: true) } }
            .transition(.blurReplace)
        case .ready(let overview):
          // Numerar os blocos faz a abertura descer de cima para baixo, na
          // ordem em que o olho lê, e o índice de cada um é o que os cards de
          // pendência continuam a partir.
          VStack(alignment: .leading, spacing: 20) {
            StudyTodayMetrics(overview: overview)
              .staggeredEntrance(index: 2, isReady: true)
            StudyTodayPending(overview: overview, onAssignments: onAssignments, base: 3)
            if overview.reviewCount > 0 || overview.lastSession != nil {
              StudyTodayContinue(overview: overview, onSession: onSession, onReview: onReview)
                .staggeredEntrance(index: 5, isReady: true)
            }
          }
          .transition(.blurReplace)
        }
      }
      .animation(Motion.crossfade, value: store.overview.phase)
      .padding(.horizontal, 16)
      .padding(.bottom, 32)
    }
    .studyPage()
    .task { await store.loadOverview() }
    .refreshable { await store.loadOverview(force: true) }
  }

  private var headingDate: Date {
    (store.overview.value?.date ?? .today).date(in: StudyFormat.calendar)
  }
}

private func contagem(_ total: Int, _ singular: String, _ plural: String) -> String {
  "\(total) \(total == 1 ? singular : plural)"
}

struct StudyTodayMetrics: View {
  let overview: StudyOverview

  var body: some View {
    HStack(spacing: 8) {
      StudyMetric(value: StudyFormat.minutes(overview.weekMinutes), caption: "na semana")
      StudyMetric(
        value: "\(overview.dueSoon.count { $0.status == .done })/\(overview.dueSoon.count)",
        caption: "entregas")
      StudyMetric(value: "\(overview.reviewCount)", caption: "cartões")
    }
    .fixedSize(horizontal: false, vertical: true)
  }
}

// MARK: - Pendências

struct StudyTodayPending: View {
  @Environment(EstudosStore.self) private var store
  let overview: StudyOverview
  let onAssignments: () -> Void
  /// Onde este bloco entra na cascata da tela. Os cards continuam daqui, então
  /// eles nunca chegam antes do próprio título.
  var base = 0

  var body: some View {
    let now = overview.date.date(in: StudyFormat.calendar)
    VStack(alignment: .leading, spacing: 0) {
      StudySectionHeading(title: "pendências", action: ("ver todas", onAssignments))
        .staggeredEntrance(index: base, isReady: true)
      VStack(spacing: 8) {
        if let sync = overview.lastSync {
          StudyCallout(
            icon: "arrow.triangle.2.circlepath", tone: .sky,
            title: "sincronizado \(StudyFormat.relative(sync.completedAt, now: Date()))",
            detail: contagem(sync.createdCount, "nova", "novas"))
            .staggeredEntrance(index: base + 1, isReady: true)
        }
        if overview.dueSoon.isEmpty {
          StudyEmptyState(
            icon: "calendar", title: "sem entregas",
            detail: "as do moodle entram sozinhas na próxima sincronização.")
            .staggeredEntrance(index: base + 1, isReady: true)
        } else {
          ForEach(Array(overview.dueSoon.enumerated()), id: \.element.id) { index, item in
            StudyTaskCard(assignment: item, now: now) { next in
              Task { await store.setStatus(of: item, to: next) }
            }
            .staggeredEntrance(index: base + 1 + index, isReady: true)
          }
        }
      }
    }
  }
}

// MARK: - Continuar

struct StudyTodayContinue: View {
  let overview: StudyOverview
  let onSession: () -> Void
  let onReview: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      StudySectionHeading(title: "continuar")
      StudyDbList {
        if overview.reviewCount > 0 {
          StudyDbRow(
            icon: "rectangle.on.rectangle",
            title: contagem(overview.reviewCount, "cartão", "cartões"),
            end: { StudyPill(tone: .coral, text: "hoje") },
            action: onReview)
        }
        if let session = overview.lastSession {
          StudyDbRow(
            icon: "timer", title: "retomar", detail: sessionDetail(session), action: onSession)
        }
      }
    }
  }

  private func sessionDetail(_ session: StudySession) -> String {
    let minutes = StudyFormat.minutes(session.completedMinutes)
    return "\(minutes) · \(StudyFormat.relative(session.startedAt, now: Date()))"
  }
}
