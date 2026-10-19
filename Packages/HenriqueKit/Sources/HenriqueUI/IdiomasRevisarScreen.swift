import HenriqueCore
import SwiftUI

private enum IdiomasReviewPhase {
  case front, back
}

private enum IdiomasReviewAction {
  case flip
  case advance(total: Int)
  case hint(rating: FlashcardRating, interval: Int)
  case failed
}

/// A revisão congela a fila como os estudos: `grade` tira o treino de
/// `store.queue` na resposta, e um índice no array vivo pularia o seguinte.
private enum IdiomasReviewState {
  case empty
  case card(index: Int, phase: IdiomasReviewPhase, hints: [FlashcardRating: String], failed: Bool)
  case done

  func reduce(_ action: IdiomasReviewAction) -> IdiomasReviewState {
    guard case .card(let index, let phase, let hints, let failed) = self else { return self }
    switch action {
    case .flip:
      return .card(
        index: index, phase: phase == .front ? .back : .front, hints: hints, failed: failed)
    case .advance(let total):
      let next = index + 1
      guard next < total else { return .done }
      return .card(index: next, phase: .front, hints: hints, failed: false)
    case .hint(let rating, let interval):
      var updated = hints
      updated[rating] = interval <= 0 ? "hoje" : interval == 1 ? "amanhã" : "\(interval) dias"
      return .card(index: index, phase: phase, hints: updated, failed: failed)
    case .failed:
      return .card(index: index, phase: phase, hints: hints, failed: true)
    }
  }
}

public struct IdiomasRevisarScreen: View {
  @Environment(IdiomasStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var deck: LanguageReviewQueue?
  @State private var state: IdiomasReviewState = .empty
  @State private var grading = false

  public init() {}

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        StudyHeading(title: "revisar")
        switch store.queue {
        case .idle, .loading:
          StudyLoadingState().transition(.opacity)
        case .failed(let message):
          StudyFailedState(message: message) { Task { await store.loadQueue(force: true) } }
            .transition(.opacity)
        case .ready:
          ready.transition(.opacity)
        }
      }
      .animation(Motion.resolve(Motion.crossfade, reduceMotion), value: store.queue.phase)
      .padding(.horizontal, 16)
      .padding(.bottom, 32)
    }
    .studyPage()
    .task { await store.loadQueue() }
    .refreshable { await refresh() }
    .onChange(of: store.queue.value != nil, initial: true) { _, isReady in
      // A sessão que cai zera a fila do store. Segurar a cópia aqui mostraria
      // os treinos da conta anterior a quem entrasse depois.
      guard isReady else {
        deck = nil
        return
      }
      guard deck == nil, let queue = store.queue.value else { return }
      adopt(queue)
    }
  }

  @ViewBuilder private var ready: some View {
    if let deck {
      switch state {
      case .empty:
        StudyEmptyState(icon: "rectangle.on.rectangle", title: "sem revisões")
      case .done:
        StudyEmptyState(icon: "checkmark.circle", title: "fila limpa")
      case .card(let index, let phase, let hints, let failed):
        if deck.drills.indices.contains(index) {
          let drill = deck.drills[index]
          if failed || store.conflictDrillIds.contains(drill.id) {
            StudyCallout(
              icon: "arrow.triangle.2.circlepath", tone: .yellow,
              title: "resposta não salva",
              detail: store.conflictDrillIds.contains(drill.id)
                ? "o treino mudou" : "tente de novo")
            if store.conflictDrillIds.contains(drill.id) {
              Button("atualizar") { Task { await refresh() } }
                .buttonStyle(.glass)
                .controlSize(.large)
                .tint(Color.studyInk)
            }
          }
          face(drill: drill, index: index, total: deck.drills.count, phase: phase)
          grades(drill: drill, phase: phase, hints: hints)
        }
      }
    }
  }

  private func face(drill: LanguageDrill, index: Int, total: Int, phase: IdiomasReviewPhase)
    -> some View
  {
    StudyCard {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 8) {
          StudyPill(tone: .neutral, text: drill.kind.title)
          Spacer(minLength: 8)
          Text("\(index + 1)/\(total)")
            .font(.footnote)
            .monospacedDigit()
            .foregroundStyle(Color.studyInk40)
        }
        Text(drill.promptDE)
          .font(.system(size: 26, weight: .semibold).leading(.tight))
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 12)
        Text(drill.glossPT)
          .font(.system(size: 16))
          .foregroundStyle(Color.studyGraphite)
          .fixedSize(horizontal: false, vertical: true)
        if phase == .back {
          Text(drill.expectedDE ?? drill.glossPT)
            .font(.system(size: 16).weight(.medium))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
        } else {
          Text("toque para virar")
            .font(.system(size: 13))
            .foregroundStyle(Color.studyInk40)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
        }
      }
    }
    .contentShape(.rect)
    .onTapGesture { state = state.reduce(.flip) }
    .accessibilityAddTraits(.isButton)
  }

  private func grades(
    drill: LanguageDrill, phase: IdiomasReviewPhase, hints: [FlashcardRating: String]
  ) -> some View {
    HStack(spacing: 8) {
      ForEach(FlashcardRating.allCases, id: \.self) { rating in
        Button {
          Task { await grade(drill: drill, rating: rating) }
        } label: {
          VStack(spacing: 2) {
            Text(rating.label).font(.system(size: 14, weight: .semibold))
            if let hint = hints[rating] {
              Text(hint)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Color.studyInk40)
            }
          }
          .multilineTextAlignment(.center)
          .foregroundStyle(rating == .facil ? .white : Color.studyInk)
          .padding(6)
          .frame(maxWidth: .infinity, minHeight: 52)
          .modifier(StudyGradeSurface(fill: rating == .facil ? .idiomasTeal : nil))
          .contentShape(.capsule)
        }
        .buttonStyle(StudyPressStyle())
        .disabled(phase == .front || grading)
        .opacity(phase == .front || grading ? 0.45 : 1)
      }
    }
  }

  private func grade(drill: LanguageDrill, rating: FlashcardRating) async {
    guard case .card(let index, let phase, _, _) = state, phase == .back, !grading,
      let deck, deck.drills.indices.contains(index)
    else { return }
    grading = true
    defer { grading = false }
    if let result = await store.gradeReview(drill: drill, rating: rating) {
      state = state.reduce(.hint(rating: rating, interval: result.interval))
      state = state.reduce(.advance(total: deck.drills.count))
    } else if !store.conflictDrillIds.contains(drill.id) {
      state = state.reduce(.failed)
    }
  }

  private func adopt(_ queue: LanguageReviewQueue) {
    deck = queue
    state =
      queue.drills.isEmpty
      ? .empty : .card(index: 0, phase: .front, hints: [:], failed: false)
  }

  private func refresh() async {
    await store.loadQueue(force: true)
    guard let queue = store.queue.value else { return }
    adopt(queue)
  }
}
