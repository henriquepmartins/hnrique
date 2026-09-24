import HenriqueCore
import SwiftUI

#if os(iOS)
  import UIKit
#endif

public struct IdiomasRotinaScreen: View {
  @Environment(IdiomasStore.self) private var store
  @Environment(IdiomasSpeech.self) private var speech
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  #if os(iOS)
    @Environment(\.openURL) private var openURL
  #endif

  @State private var session: LanguageSessionState = .empty
  @State private var selection = 0
  @State private var texts: [String: String] = [:]
  @State private var corrections: [String: LanguageCorrection] = [:]
  @State private var gradingIds: Set<String> = []
  @State private var completingIds: Set<String> = []
  @State private var sessionFinished = false

  public init() {}

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        StudyHeading(title: "rotina")
        switch store.routine {
        case .idle, .loading:
          StudyLoadingState().transition(.opacity)
        case .failed(let message):
          StudyFailedState(message: message) { Task { await store.loadRoutine(force: true) } }
            .transition(.opacity)
        case .ready(let routine):
          if routine.drills.isEmpty {
            StudyEmptyState(
              icon: "bubble.left.and.text.bubble.right",
              title: "sem treinos hoje",
              detail: "a rotina de alemão ainda não saiu. puxe para atualizar.")
          } else {
            content(drills: routine.drills).transition(.opacity)
          }
        }
      }
      .animation(.easeOut(duration: 0.25), value: store.routine.phase)
      .padding(.horizontal, 16)
      .padding(.bottom, 32)
    }
    .studyPage()
    .task { await store.loadRoutine() }
    .refreshable { await store.loadRoutine(force: true) }
    .onDisappear { speech.stop() }
    .onChange(of: store.routine.value?.drills.count, initial: true) { _, _ in
      guard case .empty = session, let drills = store.routine.value?.drills, !drills.isEmpty else {
        return
      }
      selection = 0
      session = .drill(index: 0, step: .listen, micArmed: false, played: false, failed: false)
    }
  }

  // MARK: Pager

  private func content(drills: [LanguageDrill]) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      if let progress = store.progress.value, progress.streakCount == 0,
        store.completedDrillIds.isEmpty
      {
        StudyCallout(
          icon: "info.circle", tone: .sky,
          title: "como funciona",
          detail:
            "ouça, sombreie em voz alta e produza a sua frase. \(drills.map(\.kind.minutes).reduce(0, +)) min hoje."
        )
      }
      if case .done = session {
        done
      } else {
        header(drills: drills)
        TabView(selection: $selection) {
          ForEach(Array(drills.enumerated()), id: \.element.id) { index, drill in
            drillPage(drill: drill, drills: drills)
              .tag(index)
          }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(minHeight: 420)
        .onChange(of: selection) { _, next in
          speech.stop()
          session = .drill(
            index: next, step: .listen, micArmed: false, played: false, failed: false)
        }
      }
    }
  }

  private func header(drills: [LanguageDrill]) -> some View {
    HStack(spacing: 8) {
      Text("treino \(min(selection + 1, drills.count)) de \(drills.count)")
      Spacer(minLength: 8)
      if drills.indices.contains(selection) {
        let drill = drills[selection]
        Text("\(drill.kind.title) · \(drill.kind.minutes) min")
      }
    }
    .font(.caption)
    .foregroundStyle(Color.studyInk60)
    .monospacedDigit()
  }

  private var done: some View {
    VStack(alignment: .leading, spacing: 12) {
      StudyEmptyState(icon: "checkmark.circle", title: sessionFinished ? "dia feito" : "rotina feita")
      if !sessionFinished {
        Button("concluir sessão") { Task { await finish() } }
          .buttonStyle(.glassProminent)
          .controlSize(.large)
          .tint(.idiomasTeal)
      }
    }
  }

  private func finish() async {
    sessionFinished = await store.finishSession()
  }

  // MARK: Treino

  private func drillPage(drill: LanguageDrill, drills: [LanguageDrill]) -> some View {
    StudyCard {
      VStack(alignment: .leading, spacing: 14) {
        StudyPill(tone: .neutral, text: "\(drill.kind.title) · \(drill.kind.minutes) min")
        Text(drill.promptDE)
          .font(.title2.weight(.semibold).leading(.tight))
          .fixedSize(horizontal: false, vertical: true)
        Text(drill.glossPT)
          .font(.subheadline)
          .foregroundStyle(Color.studyGraphite)
          .fixedSize(horizontal: false, vertical: true)
        if let expected = drill.expectedDE, drill.kind != .produce {
          Text(expected)
            .font(.callout)
            .foregroundStyle(Color.studyInk60)
            .fixedSize(horizontal: false, vertical: true)
        }
        Button {
          speech.speak(drill.promptDE)
          reduce(.play, drill: drill, drills: drills)
        } label: {
          Label("ouvir", systemImage: "play.fill").padding(.leading, -1.5)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .tint(.idiomasTeal)
        if drill.kind.needsMic {
          micRow(drill: drill, drills: drills)
        }
        if drill.kind.needsAI {
          produceRow(drill: drill, drills: drills)
        } else {
          Button("marcar feito") {
            Task { await completeAndAdvance(drill: drill, drills: drills, text: "", micUsed: micArmed) }
          }
          .buttonStyle(.glassProminent)
          .controlSize(.large)
          .tint(.idiomasTeal)
          .disabled(completingIds.contains(drill.id))
        }
        if store.conflictDrillIds.contains(drill.id) {
          StudyCallout(
            icon: "arrow.triangle.2.circlepath", tone: .yellow,
            title: "resposta não salva", detail: "o treino mudou em outro aparelho")
          Button("atualizar") {
            session = .empty
            selection = 0
            Task { await store.loadRoutine(force: true) }
          }
          .buttonStyle(.glass)
          .controlSize(.large)
          .tint(Color.studyInk)
        } else if isFailed {
          StudyCallout(
            icon: "arrow.triangle.2.circlepath", tone: .yellow,
            title: "resposta não salva", detail: "tente de novo")
        }
      }
    }
  }

  // MARK: Microfone

  private var micArmed: Bool {
    if case .drill(let index, _, let armed, _, _) = session, index == selection { return armed }
    return false
  }

  private var isFailed: Bool {
    if case .drill(let index, _, _, _, let failed) = session, index == selection { return failed }
    return false
  }

  private func micRow(drill: LanguageDrill, drills: [LanguageDrill]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if speech.micDenied {
        StudyCallout(
          icon: "mic.slash", tone: .yellow,
          title: "sem microfone",
          detail: "a repetição vira só escuta.")
        #if os(iOS)
          Button("abrir ajustes") {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
          }
          .buttonStyle(.glass)
          .controlSize(.large)
          .tint(Color.studyInk)
        #endif
      } else {
        Toggle("microfone", isOn: micBinding(drill: drill, drills: drills))
          .font(.subheadline)
      }
    }
  }

  private func micBinding(drill: LanguageDrill, drills: [LanguageDrill]) -> Binding<Bool> {
    Binding(
      get: { micArmed },
      set: { on in
        speech.setMicArmed(on)
        reduce(.armMic(on), drill: drill, drills: drills)
      })
  }

  // MARK: Produção

  private func produceRow(drill: LanguageDrill, drills: [LanguageDrill]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      TextField("responda em alemão", text: textBinding(drill: drill), axis: .vertical)
        .textFieldStyle(.roundedBorder)
        .lineLimit(3...6)
      if let correction = corrections[drill.id] {
        StudyCallout(
          icon: "checkmark.circle",
          title: correction.fixedDE,
          detail: "\(correction.correctionPT) · \(FocoFormat.count(correction.score, "ponto", "pontos"))")
        Button("próximo") {
          Task {
            await completeAndAdvance(drill: drill, drills: drills, text: texts[drill.id] ?? "", micUsed: false)
          }
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .tint(.idiomasTeal)
        .disabled(completingIds.contains(drill.id))
      } else if store.pendingCorrectionIds.contains(drill.id) {
        StudyCallout(
          icon: "wifi.slash", tone: .yellow,
          title: "sem correção agora",
          detail: "valeu do mesmo jeito. avalie para seguir.")
        selfGradeRow(drill: drill, drills: drills)
      } else {
        Button("corrigir") { Task { await correct(drill: drill, drills: drills) } }
          .buttonStyle(.glassProminent)
          .controlSize(.large)
          .tint(.idiomasTeal)
          .disabled((texts[drill.id] ?? "").isEmpty || gradingIds.contains(drill.id))
      }
    }
  }

  private func textBinding(drill: LanguageDrill) -> Binding<String> {
    Binding(
      get: { texts[drill.id] ?? "" },
      set: { texts[drill.id] = $0 })
  }

  private func correct(drill: LanguageDrill, drills: [LanguageDrill]) async {
    let text = texts[drill.id] ?? ""
    guard !text.isEmpty else { return }
    gradingIds.insert(drill.id)
    defer { gradingIds.remove(drill.id) }
    reduce(.submit, drill: drill, drills: drills)
    if let correction = await store.gradeCorrection(drill: drill, text: text) {
      corrections[drill.id] = correction
    } else if !store.conflictDrillIds.contains(drill.id)
      && !store.pendingCorrectionIds.contains(drill.id)
    {
      reduce(.failed, drill: drill, drills: drills)
    }
  }

  private func selfGradeRow(drill: LanguageDrill, drills: [LanguageDrill]) -> some View {
    HStack(spacing: 8) {
      ForEach(FlashcardRating.allCases, id: \.self) { rating in
        Button {
          Task {
            await completeAndAdvance(
              drill: drill, drills: drills, text: texts[drill.id] ?? "", micUsed: false)
          }
        } label: {
          VStack(spacing: 2) {
            Text(rating.label).font(.system(size: 14, weight: .semibold))
            Text(rating.localHint).font(.system(size: 11)).foregroundStyle(Color.studyInk40)
          }
          .multilineTextAlignment(.center)
          .foregroundStyle(rating == .facil ? .white : Color.studyInk)
          .padding(6)
          .frame(maxWidth: .infinity, minHeight: 52)
          .modifier(StudyGradeSurface(fill: rating == .facil ? .idiomasTeal : nil))
          .contentShape(.capsule)
        }
        .buttonStyle(StudyPressStyle())
      }
    }
  }

  // MARK: Mecânica

  private func reduce(
    _ action: LanguageSessionAction, drill: LanguageDrill, drills: [LanguageDrill]
  ) {
    session = session.reduce(action, kind: drill.kind, total: drills.count)
  }

  private func completeAndAdvance(drill: LanguageDrill, drills: [LanguageDrill], text: String, micUsed: Bool)
    async
  {
    completingIds.insert(drill.id)
    defer { completingIds.remove(drill.id) }
    let saved = await store.complete(drill: drill, text: text, micUsed: micUsed)
    if saved {
      advance(drills: drills, drill: drill)
    } else if !store.conflictDrillIds.contains(drill.id) {
      reduce(.failed, drill: drill, drills: drills)
    }
  }

  private func advance(drills: [LanguageDrill], drill: LanguageDrill) {
    reduce(.advance(total: drills.count), drill: drill, drills: drills)
    if case .drill(let index, _, _, _, _) = session {
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
        selection = index
      }
    }
  }
}
