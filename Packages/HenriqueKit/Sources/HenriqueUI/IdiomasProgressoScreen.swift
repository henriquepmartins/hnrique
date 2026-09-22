import HenriqueCore
import SwiftUI

public struct IdiomasProgressoScreen: View {
  @Environment(IdiomasStore.self) private var store

  public init() {}

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        StudyHeading(title: "progresso")
        switch store.progress {
        case .idle, .loading:
          StudyLoadingState().transition(.opacity)
        case .failed(let message):
          StudyFailedState(message: message) { Task { await store.loadProgress(force: true) } }
            .transition(.opacity)
        case .ready(let payload):
          let progress = LanguageProgress(
            doneDates: payload.doneDates, streakCount: payload.streakCount,
            target: payload.target)
          StudyCard {
            VStack(alignment: .leading, spacing: 4) {
              HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(progress.figure.count)")
                  .font(.system(size: 44, weight: .semibold))
                  .padding(.leading, -1.5)
                  .foregroundStyle(Color.idiomasTeal)
                if let target = progress.figure.target {
                  Text("/\(target) dias")
                    .font(.callout)
                    .foregroundStyle(Color.studyInk60)
                }
              }
              Text("dias de alemão em sequência")
                .font(.caption)
                .foregroundStyle(Color.studyInk60)
            }
          }
          .transition(.opacity)
          StudyCard {
            VStack(alignment: .leading, spacing: 12) {
              Text("últimos 7 dias")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.studyInk60)
              HStack(spacing: 6) {
                ForEach(Array(progress.days.enumerated()), id: \.element.id) { index, day in
                  VStack(spacing: 6) {
                    Text(day.date.date(), format: .dateTime.weekday(.abbreviated))
                      .font(.caption2)
                      .foregroundStyle(Color.studyInk60)
                      .textCase(.lowercase)
                    IdiomasDayMarker(
                      state: day.state, isToday: index == progress.days.count - 1)
                  }
                  .frame(maxWidth: .infinity)
                  .accessibilityElement(children: .ignore)
                  .accessibilityLabel(
                    Text(
                      "\(day.date.date(), format: .dateTime.weekday(.wide)), \(day.state.idiomasLabel)"
                    ))
                }
              }
            }
          }
          .transition(.opacity)
        }
      }
      .animation(.easeOut(duration: 0.25), value: store.progress.phase)
      .padding(.horizontal, 16)
      .padding(.bottom, 32)
    }
    .studyPage()
    .task { await store.loadProgress() }
    .refreshable { await store.loadProgress(force: true) }
  }
}

private struct IdiomasDayMarker: View {
  let state: StreakDayState
  let isToday: Bool

  var body: some View {
    ZStack {
      if isToday {
        Circle()
          .strokeBorder(Color.idiomasTeal.opacity(0.5), lineWidth: 1.5)
          .frame(width: 41, height: 41)
      }
      mark.frame(width: 32, height: 32)
    }
    .frame(width: 42, height: 42)
  }

  @ViewBuilder
  private var mark: some View {
    switch state {
    case .done:
      Circle().fill(Color.idiomasTeal)
        .overlay {
          Image(systemName: "checkmark")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .offset(y: -0.5)
        }
    case .missed:
      Circle().strokeBorder(Color.studyInk20, lineWidth: 1.5)
    case .planned:
      Circle().strokeBorder(Color.idiomasTeal, lineWidth: 2)
    case .rest, .open:
      Circle().fill(Color.studyInk20)
        .frame(width: 9, height: 9)
    }
  }
}

extension StreakDayState {
  var idiomasLabel: String {
    switch self {
    case .done: "treino feito"
    case .missed: "treino perdido"
    case .planned: "treino planejado"
    case .rest: "folga"
    case .open: "dia livre"
    }
  }
}
