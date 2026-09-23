import HenriqueCore
import SwiftUI
import UserNotifications

#if canImport(UIKit)
  import UIKit
#endif

// MARK: - Estado

/// Os quatro momentos do bloco. O tempo corrido sai sempre da diferença entre
/// dois instantes, nunca de uma contagem de ticks, então o app pode ficar
/// minutos no segundo plano sem o cronômetro atrasar, e o bloco gravado no
/// disco volta certo depois de o sistema matar o app.
private enum FocusSessionState: Codable, Hashable {
  case idle(subjectId: String?, minutes: Int)
  case running(
    session: StudySession, subjectId: String?, minutes: Int, since: Date, before: TimeInterval)
  case paused(session: StudySession, subjectId: String?, minutes: Int, elapsed: TimeInterval)
  case done(subjectId: String?, minutes: Int, completed: Int)

  enum Phase: Hashable {
    case idle, timing, done
  }

  var phase: Phase {
    switch self {
    case .idle: .idle
    case .running, .paused: .timing
    case .done: .done
    }
  }

  var subjectId: String? {
    switch self {
    case .idle(let subjectId, _): subjectId
    case .running(_, let subjectId, _, _, _): subjectId
    case .paused(_, let subjectId, _, _): subjectId
    case .done(let subjectId, _, _): subjectId
    }
  }

  var minutes: Int {
    switch self {
    case .idle(_, let minutes): minutes
    case .running(_, _, let minutes, _, _): minutes
    case .paused(_, _, let minutes, _): minutes
    case .done(_, let minutes, _): minutes
    }
  }

  var session: StudySession? {
    switch self {
    case .running(let session, _, _, _, _), .paused(let session, _, _, _): session
    case .idle, .done: nil
    }
  }

  var isRunning: Bool {
    if case .running = self { return true }
    return false
  }

  var total: TimeInterval { Double(minutes) * 60 }

  func elapsed(at now: Date) -> TimeInterval {
    switch self {
    case .running(_, _, _, let since, let before): max(0, before + now.timeIntervalSince(since))
    case .paused(_, _, _, let elapsed): elapsed
    case .idle, .done: 0
    }
  }

  func remaining(at now: Date) -> TimeInterval { max(0, total - elapsed(at: now)) }

  func progress(at now: Date) -> Double {
    total == 0 ? 0 : min(1, elapsed(at: now) / total)
  }

  mutating func pick(subjectId: String?) {
    guard case .idle(_, let minutes) = self else { return }
    self = .idle(subjectId: subjectId, minutes: minutes)
  }

  mutating func block(minutes: Int) {
    guard case .idle(let subjectId, _) = self else { return }
    self = .idle(subjectId: subjectId, minutes: minutes)
  }

  mutating func started(_ session: StudySession, at now: Date) {
    guard case .idle(let subjectId, let minutes) = self else { return }
    self = .running(
      session: session, subjectId: subjectId, minutes: minutes, since: now, before: 0)
  }

  mutating func pause(at now: Date) {
    guard case .running(let session, let subjectId, let minutes, _, _) = self else { return }
    self = .paused(
      session: session, subjectId: subjectId, minutes: minutes, elapsed: elapsed(at: now))
  }

  mutating func resume(at now: Date) {
    guard case .paused(let session, let subjectId, let minutes, let elapsed) = self else { return }
    self = .running(
      session: session, subjectId: subjectId, minutes: minutes, since: now, before: elapsed)
  }

  mutating func finish(completed: Int) {
    switch self {
    case .running(_, let subjectId, let minutes, _, _),
      .paused(_, let subjectId, let minutes, _):
      self = .done(subjectId: subjectId, minutes: minutes, completed: completed)
    case .idle, .done:
      break
    }
  }
}

// MARK: - Tela

public struct FocusSessionScreen: View {
  @Environment(EstudosStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @ScaledMetric(relativeTo: .title3) private var labelSize = 19.0
  @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 34.0
  @ScaledMetric(relativeTo: .largeTitle) private var timerSize = 101.0
  @ScaledMetric(relativeTo: .body) private var rowSize = 16.0
  @ScaledMetric(relativeTo: .subheadline) private var metaSize = 14.0

  @State private var state = FocusBlockFile.load() ?? .idle(subjectId: nil, minutes: 25)
  @State private var quickNote = ""
  @State private var noteSession: StudySession?
  @State private var busy = false
  @State private var savingNote = false
  @State private var noteSaved = false
  @State private var startFailed = false
  @State private var finishFailed = false
  @State private var noteFailed = false
  @State private var askLeave = false
  @State private var pendingSessionID: String?

  private let onReview: () -> Void

  public init(onReview: @escaping () -> Void) {
    self.onReview = onReview
  }

  public var body: some View {
    VStack(spacing: 0) {
      topBar
        .padding(.horizontal, 16)
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
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
        .padding(.horizontal, 16)
        .padding(.bottom, 40)
      }
      .scrollDismissesKeyboard(.interactively)
    }
    .keyboardDone()
    .background(Color.studyBlack.ignoresSafeArea())
    .foregroundStyle(Color.studyCream)
    .tint(Color.studyCream)
    .preferredColorScheme(.dark)
    .task {
      // O bloco que venceu com o app fechado termina ao abrir, sem esperar o
      // relógio da tela mudar de valor.
      if state.isRunning, state.remaining(at: .now) == 0 { await finish() }
      await store.loadSubjects()
    }
    .onChange(of: state.isRunning, initial: true) { _, running in
      keepScreenAwake(running)
    }
    .onChange(of: state) {
      FocusBlockFile.save(state)
      FocusBlockAlarm.update(for: state)
    }
    .onDisappear { keepScreenAwake(false) }
    .confirmationDialog(
      "descartar sessão?", isPresented: $askLeave, titleVisibility: .visible
    ) {
      Button("descartar", role: .destructive) { discard() }
      Button("continuar", role: .cancel) {}
    }
  }

  // MARK: Barra de cima

  private var topBar: some View {
    HStack(spacing: 0) {
      IconButton(title: "sair do foco", systemImage: "xmark", size: 20, action: requestClose)
        .tint(Color.studyCream)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 2)
  }

  // MARK: Estados

  @ViewBuilder private var stateSection: some View {
    Group {
      switch state.phase {
      case .idle: idleSection
      case .timing: timingSection
      case .done: doneSection
      }
    }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: state.phase)
  }

  private var idleSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      title("matéria")
      subjectPicker
        .padding(.top, Space.xxl)
      StudyWrap(spacing: 8, lineSpacing: 8) {
        ForEach([15, 25, 50], id: \.self) { minutes in
          FocusSessionCapsule(active: minutes == state.minutes) {
            state.block(minutes: minutes)
          } label: {
            Text("\(minutes) min")
          }
          .disabled(busy || startFailed)
        }
      }
      .padding(.top, Space.xxl)
      FocusSessionGradientButton(
        title: "começar", systemImage: "play.fill",
        action: { Task { await start() } })
        .disabled(busy)
        .padding(.top, Space.xxl)
      if startFailed {
        metaLine("não abriu, tente de novo")
          .padding(.top, 10)
      }
    }
    .transition(.opacity)
  }

  @ViewBuilder private var subjectPicker: some View {
    switch store.subjects {
    case .idle, .loading:
      ProgressView()
        .frame(maxWidth: .infinity, alignment: .leading)
    case .failed(let message):
      metaLine(message)
    case .ready(let list) where list.isEmpty:
      StudyEmptyState(icon: "book", title: "sem matérias", cream: true)
    case .ready(let list):
      StudyWrap(spacing: 8, lineSpacing: 8) {
        ForEach(list) { item in
          FocusSessionCapsule(active: item.id == state.subjectId, leadingGlyph: true) {
            state.pick(subjectId: item.id == state.subjectId ? nil : item.id)
          } label: {
            HStack(spacing: 8) {
              StudyDot(color: item.color)
              Text(item.name)
            }
          }
          .disabled(busy || startFailed)
        }
      }
    }
  }

  private var timingSection: some View {
    FocusSessionTicker(running: state.isRunning) { now in
      timingReadout(now: now)
    }
    .transition(.opacity)
  }

  private func timingReadout(now: Date) -> some View {
    let remaining = state.remaining(at: now)
    return VStack(alignment: .leading, spacing: 0) {
      if let subjectName { label(subjectName, color: .studyMarigold) }
      title(isPaused ? "pausado" : "\(state.minutes) min")
      Text.clock(StudyFormat.clock(remaining))
        .font(.system(size: timerSize, weight: .semibold).leading(.tight))
        .tracking(-timerSize * 0.011)
        .lineLimit(1)
        .minimumScaleFactor(0.4)
        .offset(x: -3)
        .padding(.top, Space.xxl)
        .accessibilityLabel("faltam \(StudyFormat.minutes(Int(remaining / 60)))")
      progressBar(fraction: state.progress(at: now))
        .padding(.top, 24)
      HStack(spacing: 12) {
        Text("\(StudyFormat.minutes(Int(state.elapsed(at: now) / 60))) feitos")
        Spacer(minLength: 0)
        Text("até \(StudyFormat.hour(now.addingTimeInterval(remaining)))")
      }
      .font(.system(size: metaSize))
      .monospacedDigit()
      .foregroundStyle(Color.studyCream50)
      .padding(.top, 10)
      StudyWrap(spacing: 8, lineSpacing: 8) {
        FocusSessionCapsule(leadingGlyph: true) {
          if isPaused {
            state.resume(at: .now)
          } else {
            state.pause(at: .now)
          }
        } label: {
          HStack(spacing: 6) {
            Image(systemName: isPaused ? "play.fill" : "pause.fill").font(.system(size: 16))
            Text(isPaused ? "retomar" : "pausar")
          }
        }
        .disabled(busy)
        FocusSessionGradientButton(
          title: finishTitle, systemImage: "checkmark", action: { Task { await finish() } })
          .disabled(busy)
      }
      .padding(.top, Space.xxl)
      if finishFailed {
        metaLine("não salvou, tempo pausado")
          .padding(.top, 10)
      }
    }
    .onChange(of: remaining == 0) { _, expired in
      guard expired, state.isRunning else { return }
      Task { await finish() }
    }
  }

  private var doneSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let subjectName { label(subjectName, color: .studyMarigold) }
      title("concluído")
      Text.clock(StudyFormat.minutes(completedMinutes))
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
      FocusSessionCapsule(action: { dismiss() }) {
        Text("voltar")
      }
      .padding(.top, Space.xxl)
    }
    .transition(.opacity)
  }

  // MARK: Peças de baixo

  private var rule: some View {
    Rectangle().fill(Color.studyCream25).frame(height: 1)
  }

  private var noteCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        StudyEyebrow("nota", cream: true)
        Spacer(minLength: 0)
        if let subjectName { StudyPill(tone: .cream, text: subjectName) }
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
              .padding(.top, 8)
              .padding(.leading, 5)
              .allowsHitTesting(false)
          }
        }
        .disabled(busy || savingNote || (state.phase == .done && noteSaved))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(Color.studyOffBlack, in: .rect(cornerRadius: StudyRadius.outer))
  }

  private var noteRetry: some View {
    VStack(alignment: .leading, spacing: 12) {
      metaLine("nota não salva")
      FocusSessionCapsule(action: { Task { await retryNote() } }) {
        Text("tentar de novo")
      }
      .disabled(savingNote || noteSession == nil)
    }
  }

  private var reviewLink: some View {
    Button {
      dismiss()
      onReview()
    } label: {
      HStack(spacing: 12) {
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

  private var isPaused: Bool { state.phase == .timing && !state.isRunning }

  private var subjectName: String? {
    guard let id = state.subjectId else { return nil }
    return store.subjects.value?.first { $0.id == id }?.name
  }

  private var completedMinutes: Int {
    guard case .done(_, _, let completed) = state else { return 0 }
    return completed
  }

  private var finishTitle: String {
    if busy { return "salvando…" }
    return finishFailed ? "tentar de novo" : "concluir"
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

  private func requestClose() {
    if state.phase == .timing || hasUnsavedNote {
      askLeave = true
    } else {
      dismiss()
    }
  }

  /// O servidor não tem rota de descarte. Fechar a sessão com zero minuto é o
  /// que tira o bloco de aberto lá sem contar tempo que não valeu.
  private func discard() {
    let session = state.session
    FocusBlockFile.save(nil)
    FocusBlockAlarm.update(for: nil)
    state = .idle(subjectId: state.subjectId, minutes: state.minutes)
    dismiss()
    guard let session else { return }
    Task { _ = try? await store.finishSession(id: session.id, minutes: 0) }
  }

  private func start() async {
    guard case .idle = state, !busy else { return }
    busy = true
    startFailed = false
    // O servidor deduplica a sessão pelo id, então uma retentativa com o mesmo
    // id não deixa um bloco órfão aberto.
    let id = pendingSessionID ?? UUID().uuidString.lowercased()
    pendingSessionID = id
    do {
      let session = try await store.startSession(id: id, subjectId: state.subjectId)
      state.started(session, at: .now)
      pendingSessionID = nil
      await FocusBlockAlarm.requestPermission()
    } catch {
      startFailed = true
    }
    busy = false
  }

  private func finish() async {
    guard state.phase == .timing, !busy else { return }
    busy = true
    finishFailed = false
    state.pause(at: .now)
    guard let session = state.session else {
      busy = false
      return
    }
    let completed = min(state.minutes, Int((state.elapsed(at: .now) / 60).rounded()))
    do {
      let saved = try await store.finishSession(id: session.id, minutes: completed)
      noteSession = saved
      state.finish(completed: saved.completedMinutes)
      busy = false
      await saveQuickNote(saved)
    } catch {
      finishFailed = true
      busy = false
    }
  }

  private func retryNote() async {
    guard let session = noteSession else { return }
    await saveQuickNote(session)
  }

  private func saveQuickNote(_ session: StudySession) async {
    let text = trimmedNote
    guard !text.isEmpty, !savingNote else { return }
    savingNote = true
    noteFailed = false
    do {
      try await store.saveNote(
        SaveNoteInput(
          path: "notas/sessoes/\(session.startedAt.formatted(Self.noteDay))-\(session.id).md",
          title: "sessão de \(StudyFormat.weekdayLong(session.startedAt))",
          subjectId: session.subjectId,
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

// MARK: - Bloco no disco

/// O bloco em andamento, gravado como o foco grava a corrida. Só existe arquivo
/// enquanto o bloco corre ou está pausado; parado ou concluído, some. A cópia
/// em memória existe porque a casca pergunta a cada vez que se redesenha.
@MainActor
private enum FocusBlockFile {
  static var url: URL { URL.applicationSupportDirectory.appending(path: "estudos-bloco.json") }
  private static var loaded: FocusSessionState??

  static func load() -> FocusSessionState? {
    if let loaded { return loaded }
    let state = (try? Data(contentsOf: url))
      .flatMap { try? JSONDecoder.henrique().decode(FocusSessionState.self, from: $0) }
      .flatMap { $0.phase == .timing ? $0 : nil }
    loaded = .some(state)
    return state
  }

  static func save(_ state: FocusSessionState?) {
    let active = state.flatMap { $0.phase == .timing ? $0 : nil }
    loaded = .some(active)
    guard let active, let data = try? JSONEncoder.henrique().encode(active) else {
      try? FileManager.default.removeItem(at: url)
      return
    }
    try? FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
  }
}

extension FocusSessionScreen {
  /// Para a casca reabrir o bloco que estava rodando quando o app fechou.
  static var hasActiveBlock: Bool { FocusBlockFile.load() != nil }
}

/// O aviso de fim do bloco com o app fechado. O prefixo "estudos." separa estes
/// avisos dos da academia, que usam a mesma central.
private enum FocusBlockAlarm {
  static let identifier = "estudos.bloco"

  static func requestPermission() async {
    _ = try? await UNUserNotificationCenter.current()
      .requestAuthorization(options: [.alert, .sound])
  }

  /// Rodando, agenda para o fim; pausado, parado ou concluído, cancela. O mesmo
  /// identificador substitui o aviso anterior, então chamar de novo não duplica.
  static func update(for state: FocusSessionState?) {
    let center = UNUserNotificationCenter.current()
    guard let state, state.isRunning else {
      center.removePendingNotificationRequests(withIdentifiers: [identifier])
      return
    }
    let remaining = state.remaining(at: .now)
    guard remaining > 0 else {
      center.removePendingNotificationRequests(withIdentifiers: [identifier])
      return
    }
    let content = UNMutableNotificationContent()
    content.title = "bloco de \(state.minutes) min concluído"
    content.body = "abra o app para salvar a sessão."
    content.sound = .default
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
    center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
  }
}

// MARK: - Peças

private let focusSessionGreen = LinearGradient(
  colors: [.studyGreen, .studyLightGreen], startPoint: .topLeading, endPoint: .bottomTrailing)

/// O tick só existe enquanto o bloco corre. Parado, o tempo já está guardado no
/// estado e redesenhar quatro vezes por segundo não mudaria nada na tela.
private struct FocusSessionTicker<Content: View>: View {
  let running: Bool
  @ViewBuilder let content: (Date) -> Content

  var body: some View {
    if running {
      TimelineView(.periodic(from: .now, by: 0.25)) { context in
        content(context.date)
      }
    } else {
      content(.now)
    }
  }
}

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
        .padding(.trailing, 20)
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
      .padding(.trailing, 20)
      .frame(minHeight: 44)
      .overlay(Capsule().strokeBorder(focusSessionGreen, lineWidth: 1.5))
      .contentShape(.capsule)
    }
    .buttonStyle(StudyPressStyle())
  }
}
