import HenriqueCore
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

// MARK: - Tela

/// O bloco de 15, 25 ou 50 min. Não tem relógio próprio: começa uma corrida do
/// foco com alvo, então o tempo entra no dia, na chama, na meta e na grade, e a
/// corrida aberta em qualquer lugar do app aparece aqui.
public struct FocusSessionScreen: View {
  @Environment(EstudosStore.self) private var store
  @Environment(FocoStore.self) private var foco
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @ScaledMetric(relativeTo: .title3) private var labelSize = 19.0
  @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 34.0
  @ScaledMetric(relativeTo: .largeTitle) private var timerSize = 101.0
  @ScaledMetric(relativeTo: .body) private var rowSize = 16.0
  @ScaledMetric(relativeTo: .subheadline) private var metaSize = 14.0

  @State private var pickedSubjectId: String?
  @State private var minutes = 25
  @State private var quickNote = ""
  @State private var savingNote = false
  @State private var noteSaved = false
  @State private var noteFailed = false
  @State private var noteResult: FocoResult?
  @State private var askLeave = false

  private let onReview: () -> Void

  public init(onReview: @escaping () -> Void) {
    self.onReview = onReview
  }

  private enum Phase: Hashable {
    case idle, timing, done
  }

  private var phase: Phase {
    if foco.result != nil { return .done }
    return foco.isRunning ? .timing : .idle
  }

  public var body: some View {
    VStack(spacing: 0) {
      topBar
        .padding(.horizontal, Space.l)
      ScrollView {
        VStack(alignment: .leading, spacing: Space.xxl) {
          stateSection
          if let banner = store.banner {
            metaLine(banner)
          }
          rule
          noteCard
          if noteFailed {
            noteRetry
          }
          rule
          reviewLink
        }
        .padding(.horizontal, Space.l)
        .padding(.bottom, 40)
      }
      .scrollDismissesKeyboard(.interactively)
    }
    .keyboardDone()
    .background(Color.studyBlack.ignoresSafeArea())
    .foregroundStyle(Color.studyCream)
    .tint(Color.studyCream)
    .preferredColorScheme(.dark)
    .task { await store.loadSubjects() }
    .onAppear { foco.isBlockOpen = true }
    .onDisappear {
      foco.isBlockOpen = false
      keepScreenAwake(false)
      if foco.result != nil { foco.closeResult() }
    }
    .onChange(of: foco.ledger.running.map { !$0.isPaused } ?? false, initial: true) { _, counting in
      keepScreenAwake(counting)
    }
    .onChange(of: foco.result) { _, result in
      guard let result else { return }
      noteResult = result
      Task { await saveQuickNote(result) }
    }
    .confirmationDialog(
      "descartar nota?", isPresented: $askLeave, titleVisibility: .visible
    ) {
      Button("descartar", role: .destructive) { close() }
      Button("continuar", role: .cancel) {}
    }
  }

  // MARK: Barra de cima

  private var topBar: some View {
    HStack(spacing: 0) {
      IconButton(title: "fechar", systemImage: "xmark", size: 20, action: requestClose)
        .tint(Color.studyCream)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 2)
  }

  // MARK: Estados

  @ViewBuilder private var stateSection: some View {
    Group {
      switch phase {
      case .idle: idleSection
      case .timing: timingSection
      case .done: doneSection
      }
    }
    .animation(Motion.resolve(Motion.crossfade, reduceMotion), value: phase)
    .sensoryFeedback(.success, trigger: phase) { _, phase in phase == .done }
  }

  private var idleSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      title("matéria")
      subjectPicker
        .padding(.top, Space.xxl)
      StudyWrap(spacing: Space.s, lineSpacing: Space.s) {
        ForEach([15, 25, 50], id: \.self) { option in
          FocusSessionCapsule(active: option == minutes) {
            minutes = option
          } label: {
            Text("\(option) min")
          }
        }
      }
      .padding(.top, Space.xxl)
      FocusSessionGradientButton(title: "começar", systemImage: "play.fill", action: start)
        .disabled(pickedSubject == nil)
        .padding(.top, Space.xxl)
    }
    .sensoryFeedback(.selection, trigger: minutes)
    .sensoryFeedback(.selection, trigger: pickedSubjectId)
    .transition(.opacity)
  }

  @ViewBuilder private var subjectPicker: some View {
    switch store.subjects {
    case .idle, .loading:
      ProgressView()
        .frame(maxWidth: .infinity, alignment: .leading)
    case .failed(let message):
      StudyEmptyState(
        icon: "exclamationmark.triangle", title: "não carregou", detail: message, cream: true,
        action: (label: "tentar de novo", perform: { Task { await store.loadSubjects(force: true) } }))
    case .ready(let list) where list.isEmpty:
      StudyEmptyState(icon: "book", title: "sem matérias", cream: true)
    case .ready(let list):
      StudyWrap(spacing: Space.s, lineSpacing: Space.s) {
        ForEach(list) { item in
          FocusSessionCapsule(active: item.id == pickedSubject?.id, leadingGlyph: true) {
            pickedSubjectId = item.id
          } label: {
            HStack(spacing: Space.s) {
              StudyDot(color: item.color)
              Text(item.name)
            }
          }
        }
      }
    }
  }

  @ViewBuilder private var timingSection: some View {
    if let run = foco.ledger.running {
      FocoTicker(since: foco.ledger.tickAnchor { run.seconds(at: $0) }) { now in
        timingReadout(run: run, now: now)
      }
      .sensoryFeedback(.impact(weight: .light), trigger: run.isPaused)
      .transition(.opacity)
    }
  }

  /// Com alvo o relógio conta para baixo, como o bloco sempre contou. A corrida
  /// livre aberta pelo foco conta para cima.
  private func timingReadout(run: FocoRun, now: Date) -> some View {
    let elapsed = run.seconds(at: now)
    let remaining = run.remaining(at: now)
    let shown = remaining ?? elapsed
    return VStack(alignment: .leading, spacing: 0) {
      label(run.track.name, color: .studyMarigold)
      title(run.isPaused ? "pausado" : run.target.map { "\(Int($0 / 60)) min" } ?? "foco")
      Text.clock(StudyFormat.clock(shown))
        .font(.system(size: timerSize, weight: .semibold).leading(.tight))
        .tracking(-timerSize * 0.011)
        .lineLimit(1)
        .minimumScaleFactor(0.4)
        .offset(x: -3)
        .contentTransition(.numericText())
        .animation(reduceMotion ? nil : Motion.roll, value: Int(shown.rounded()))
        .padding(.top, Space.xxl)
        .accessibilityLabel(
          remaining.map { "faltam \(StudyFormat.minutes(Int($0 / 60)))" }
            ?? FocoFormat.spoken(elapsed))
        .accessibilityValue(run.isPaused ? "pausado" : "")
      if let target = run.target {
        progressBar(fraction: min(1, elapsed / target))
          .padding(.top, Space.xxl)
      }
      HStack(spacing: Space.m) {
        Text("\(StudyFormat.minutes(Int(elapsed / 60))) feitos")
        Spacer(minLength: 0)
        if let remaining, !run.isPaused {
          Text("até \(StudyFormat.hour(now.addingTimeInterval(remaining)))")
        }
      }
      .font(.system(size: metaSize))
      .monospacedDigit()
      .foregroundStyle(Color.studyCream50)
      .padding(.top, 10)
      StudyWrap(spacing: Space.s, lineSpacing: Space.s) {
        FocusSessionCapsule(leadingGlyph: true) {
          if run.isPaused { foco.resume() } else { foco.pause() }
        } label: {
          HStack(spacing: 6) {
            Image(systemName: run.isPaused ? "play.fill" : "pause.fill").font(.system(size: 16))
            Text(run.isPaused ? "retomar" : "pausar")
          }
        }
        FocusSessionGradientButton(title: "concluir", systemImage: "checkmark") { foco.stop() }
      }
      .padding(.top, Space.xxl)
    }
  }

  @ViewBuilder private var doneSection: some View {
    if let result = foco.result {
      VStack(alignment: .leading, spacing: 0) {
        label(result.track.name, color: .studyMarigold)
        title(result.entries.isEmpty ? "curta demais" : "concluído")
        Text.clock(StudyFormat.minutes(Int(result.seconds / 60)))
          .font(.system(size: timerSize, weight: .semibold).leading(.tight))
          .tracking(-timerSize * 0.011)
          .lineLimit(1)
          .minimumScaleFactor(0.4)
          .offset(x: -3)
          .padding(.top, Space.xxl)
        if let noteStatus {
          Text(noteStatus)
            .font(.system(size: metaSize))
            .foregroundStyle(Color.studyCream50)
            .padding(.top, 10)
        }
        FocusSessionCapsule(leadingGlyph: true, action: close) {
          Label("voltar", systemImage: "chevron.left")
        }
        .padding(.top, Space.xxl)
      }
      .transition(.opacity)
    }
  }

  // MARK: Peças de baixo

  private var rule: some View {
    Rectangle().fill(Color.studyCream25).frame(height: 1)
  }

  private var noteCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: Space.m) {
        StudyEyebrow("nota", cream: true)
        Spacer(minLength: 0)
        if let noteTrack { StudyPill(tone: .cream, text: noteTrack) }
      }
      TextEditor(text: $quickNote)
        .font(.system(size: rowSize))
        .foregroundStyle(Color.studyCream)
        .scrollContentBackground(.hidden)
        .frame(minHeight: 72)
        .overlay(alignment: .topLeading) {
          if quickNote.isEmpty {
            Text("nota")
              .font(.system(size: rowSize))
              .foregroundStyle(Color.studyCream50)
              .padding(.top, Space.s)
              .padding(.leading, 5)
              .allowsHitTesting(false)
          }
        }
        .disabled(savingNote || (phase == .done && noteSaved))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Space.l)
    .background(Color.studyOffBlack, in: .rect(cornerRadius: StudyRadius.outer))
  }

  private var noteRetry: some View {
    VStack(alignment: .leading, spacing: Space.m) {
      metaLine("nota não salva")
      FocusSessionCapsule(leadingGlyph: true, action: { Task { await retryNote() } }) {
        Label("tentar de novo", systemImage: "arrow.clockwise")
      }
      .disabled(savingNote || noteResult == nil)
    }
  }

  private var reviewLink: some View {
    Button {
      close()
      onReview()
    } label: {
      HStack(spacing: Space.m) {
        Text("revisar cartões")
          .font(.system(size: rowSize))
          .foregroundStyle(Color.studyCream)
        Spacer(minLength: 0)
        Image(systemName: "arrow.right")
          .font(.system(size: 20))
          .foregroundStyle(Color.studyCream)
      }
      .frame(minHeight: 44)
      .contentShape(.rect)
    }
    .buttonStyle(StudyPressStyle())
  }

  // MARK: Fragmentos

  private func label(_ text: String, color: Color) -> some View {
    Text(text)
      .font(.system(size: labelSize))
      .foregroundStyle(color)
      .lineLimit(1)
  }

  private func title(_ text: String) -> some View {
    Text(text)
      .font(.system(size: titleSize, weight: .semibold).leading(.tight))
      .tracking(-titleSize * 0.01)
      .foregroundStyle(Color.studyCream)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.top, 6)
      .accessibilityAddTraits(.isHeader)
  }

  private func metaLine(_ text: String) -> some View {
    Text(text)
      .font(.system(size: metaSize))
      .foregroundStyle(Color.studyCream50)
      .fixedSize(horizontal: false, vertical: true)
  }

  /// A fração já chega contínua do relógio, então animar a largura só deixaria
  /// a barra atrás do número.
  private func progressBar(fraction: Double) -> some View {
    Rectangle()
      .fill(Color.studyCream25)
      .frame(height: 2)
      .overlay(alignment: .leading) {
        GeometryReader { proxy in
          focusSessionGreen
            .frame(width: proxy.size.width * fraction)
        }
      }
      .clipShape(.rect)
      .accessibilityHidden(true)
  }

  // MARK: Valores derivados

  /// A escolhida, ou a primeira da lista: o bloco sempre conta para uma matéria.
  private var pickedSubject: StudySubject? {
    guard let list = store.subjects.value else { return nil }
    return list.first { $0.id == pickedSubjectId } ?? list.first
  }

  private var noteTrack: String? {
    foco.result?.track.name ?? foco.ledger.running?.track.name ?? pickedSubject?.name
  }

  private var noteStatus: String? {
    if savingNote { return "salvando…" }
    if noteSaved { return "nota salva" }
    return trimmedNote.isEmpty ? nil : "nota não salva"
  }

  private var trimmedNote: String {
    quickNote.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var hasUnsavedNote: Bool { !trimmedNote.isEmpty && !noteSaved }

  // MARK: Ações

  /// A corrida segue ao fechar: ela mora no foco e aparece na faixa e na tela
  /// de foco. Só a nota escrita se perderia.
  private func requestClose() {
    if hasUnsavedNote, phase != .done {
      askLeave = true
    } else {
      close()
    }
  }

  private func close() {
    if foco.result != nil { foco.closeResult() }
    dismiss()
  }

  private func start() {
    guard let subject = pickedSubject else { return }
    noteSaved = false
    noteFailed = false
    foco.start(
      .subject(id: subject.id, name: subject.name, color: subject.color),
      target: Double(minutes) * 60)
  }

  private func retryNote() async {
    guard let noteResult else { return }
    await saveQuickNote(noteResult)
  }

  /// Sem sessão no servidor (começou sem rede) a nota leva o id da primeira
  /// sessão do foco, para o caminho continuar único.
  private func saveQuickNote(_ result: FocoResult) async {
    let text = trimmedNote
    guard !text.isEmpty, !savingNote, !noteSaved else { return }
    let id = result.serverSessionId ?? result.entries.first?.id.uuidString.lowercased()
    guard let id else { return }
    savingNote = true
    noteFailed = false
    do {
      try await store.saveNote(
        SaveNoteInput(
          path: "notas/sessoes/\(result.startedAt.formatted(Self.noteDay))-\(id).md",
          title: "sessão de \(StudyFormat.weekdayLong(result.startedAt))",
          subjectId: result.track.subjectId,
          tags: ["sessão"],
          body: text))
      noteSaved = true
    } catch {
      noteFailed = true
    }
    savingNote = false
  }

  private func keepScreenAwake(_ awake: Bool) {
    #if canImport(UIKit)
      UIApplication.shared.isIdleTimerDisabled = awake
    #endif
  }

  /// O caminho da nota no web sai da fatia da string ISO, que é UTC. Trocar
  /// pelo fuso do aparelho daria outro arquivo para a mesma sessão.
  private static let noteDay = Date.ISO8601FormatStyle().year().month().day()
    .dateSeparator(.dash)
}

extension FocusSessionScreen {
  /// Para a casca reabrir o bloco que estava rodando quando o app fechou.
  static var hasActiveBlock: Bool { FocoStore.blockIsRunning }
}

// MARK: - Peças

private let focusSessionGreen = LinearGradient(
  colors: [.studyGreen, .studyLightGreen], startPoint: .topLeading, endPoint: .bottomTrailing)

private struct FocusSessionCapsule<Label: View>: View {
  var active = false
  /// Com ponto ou ícone na frente, o lado dele entra 2pt para o olho ver o
  /// mesmo respiro dos dois lados.
  var leadingGlyph = false
  let action: () -> Void
  @ViewBuilder let label: Label

  var body: some View {
    Button(action: action) {
      label
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(active ? Color.studyBlack : Color.studyCream)
        .padding(.vertical, 10)
        .padding(.leading, leadingGlyph ? 18 : 20)
        .padding(.trailing, Space.xl)
        .frame(minHeight: 44)
        .background(active ? Color.studyCream : Color.studyOffBlack, in: .capsule)
        .overlay(Capsule().strokeBorder(active ? .clear : Color.white.opacity(0.08)))
        .contentShape(.capsule)
    }
    .buttonStyle(StudyPressStyle())
    .accessibilityAddTraits(active ? .isSelected : [])
  }
}

private struct FocusSessionGradientButton: View {
  let title: String
  let systemImage: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: systemImage).font(.system(size: 16))
        Text(title)
      }
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(Color.studyCream)
      .padding(.vertical, 10)
      .padding(.leading, 18)
      .padding(.trailing, Space.xl)
      .frame(minHeight: 44)
      .overlay(Capsule().strokeBorder(focusSessionGreen, lineWidth: 1.5))
      .contentShape(.capsule)
    }
    .buttonStyle(StudyPressStyle())
  }
}
