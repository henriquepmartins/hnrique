import HenriqueCore
import SwiftUI

// MARK: - Estado

private enum StudyReviewPhase {
  case front, back
}

private enum StudyReviewAction {
  case flip
  case advance(total: Int)
  case hint(rating: FlashcardRating, interval: Int)
  case failed
}

/// Toda a revisão cabe em três casos. Quem não está com cartão na mão ignora as
/// ações, então não há booleano solto capaz de discordar do que a tela mostra.
private enum StudyReviewState {
  case empty
  case card(index: Int, phase: StudyReviewPhase, hints: [FlashcardRating: String], failed: Bool)
  case done

  func reduce(_ action: StudyReviewAction) -> StudyReviewState {
    guard case .card(let index, let phase, let hints, let failed) = self else { return self }
    switch action {
    case .flip:
      return .card(
        index: index, phase: phase == .front ? .back : .front, hints: hints, failed: failed)
    case .advance(let total):
      let next = index + 1
      guard next < total else { return .done }
      return .card(index: next, phase: .front, hints: [:], failed: false)
    case .hint(let rating, let interval):
      var updated = hints
      updated[rating] = Self.intervalHint(interval)
      return .card(index: index, phase: phase, hints: updated, failed: failed)
    case .failed:
      return .card(index: index, phase: phase, hints: hints, failed: true)
    }
  }

  static func intervalHint(_ interval: Int) -> String {
    if interval <= 0 { return "hoje" }
    return interval == 1 ? "amanhã" : "\(interval) dias"
  }
}

private enum StudyReviewSwipe {
  static let distance: CGFloat = 80
  static let velocity: CGFloat = 500
  static let floor: CGFloat = 24
  static let exit: CGFloat = 480
}

// MARK: - Tela

@MainActor
public struct StudyReviewScreen: View {
  @Environment(EstudosStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// A fila da tela é uma cópia. `grade` tira o cartão de `store.queue` assim
  /// que o servidor responde, e um índice apontando para o array vivo pularia o
  /// cartão seguinte a cada resposta. O web congela a fila do loader pelo mesmo
  /// motivo, e só a solta num refresh.
  @State private var deck: ReviewQueue?
  @State private var state: StudyReviewState = .empty
  @State private var conflict = false
  @State private var grading = false
  @State private var swiping = false
  @State private var dragX: CGFloat = 0
  @State private var cardY: CGFloat = 0
  @State private var cardOpacity: Double = 1
  @State private var flipAngle: Double = 0
  /// O verso já está na tela, isto é, o giro passou da metade. A fase troca no
  /// toque, antes disso.
  @State private var showsBack = false
  /// Conta as respostas gravadas, para a vibração disparar a cada uma.
  @State private var gradeTick = 0
  @State private var lastRating: FlashcardRating?
  @ScaledMetric(relativeTo: .title) private var frontSize = 26.0
  @ScaledMetric(relativeTo: .body) private var backSize = 16.0
  @ScaledMetric(relativeTo: .footnote) private var instructionSize = 13.0
  private let onWrite: (() -> Void)?

  public init(onWrite: (() -> Void)? = nil) {
    self.onWrite = onWrite
  }

  public var body: some View {
    ScrollView {
      VStack(spacing: 20) {
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
    }
    .studyPage()
    .refreshable { await refreshQueue() }
    .task { await store.loadQueue() }
    .onChange(of: store.queue.value != nil, initial: true) { _, isReady in
      // A sessão que cai zera a fila do store. Segurar a cópia congelada aqui
      // mostraria os cartões da conta anterior a quem entrasse depois.
      guard isReady else {
        deck = nil
        return
      }
      guard deck == nil, let queue = store.queue.value else { return }
      adopt(queue)
    }
    // A fila do disco entra antes da rede. Quando a nova chega e o dono ainda
    // não começou, ela toma o lugar da cópia velha.
    .onChange(of: store.queue.value?.cards.map(\.id)) { _, ids in
      guard let ids, let queue = store.queue.value, adoptsFresh(ids) else { return }
      adopt(queue)
    }
    .sensoryFeedback(trigger: gradeTick) { _, _ in
      switch lastRating {
      case .errei: .warning
      case .facil: .success
      case .dificil, nil: .selection
      }
    }
  }

  /// O cartão da frente, ainda sem resposta, ou uma fila vazia ou limpa que
  /// ganhou cartão novo. Uma fila que só encolheu é o próprio `grade` tirando
  /// o que já foi respondido, e não muda a cópia.
  private func adoptsFresh(_ ids: [String]) -> Bool {
    guard let deck, ids != deck.cards.map(\.id), !grading else { return false }
    switch state {
    case .card(let index, let phase, _, let failed):
      return index == 0 && phase == .front && !failed
    case .empty, .done:
      return !Set(ids).isSubset(of: deck.cards.map(\.id))
    }
  }

  @ViewBuilder private var ready: some View {
    if let deck {
      switch state {
      case .empty:
        StudyEmptyState(
          icon: "rectangle.on.rectangle", title: "sem cartões",
          detail: "os cartões nascem das notas. escreva uma aula e marque o trecho que quer lembrar.",
          action: onWrite.map { (label: "escrever", perform: $0) })
      case .done:
        StudyEmptyState(icon: "checkmark.circle", title: "fila limpa", celebrate: true)
      case .card(let index, let phase, let hints, let failed):
        if deck.cards.indices.contains(index) {
          let card = deck.cards[index]
          if failed { failure }
          stack(card: card, index: index, total: deck.cards.count, phase: phase)
          grades(phase: phase, hints: hints)
        }
      }
      let counts = store.queue.value?.bySubject ?? deck.bySubject
      if !counts.isEmpty { queueList(counts) }
    }
  }

  // MARK: Por matéria

  /// O respiro entre o título da seção e a lista já mora no próprio título, por
  /// isso os dois ficam numa pilha sem espaçamento.
  private func queueList(_ rows: [SubjectCount]) -> some View {
    VStack(spacing: 0) {
      StudySectionHeading(title: "por matéria")
      StudyDbList {
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
          StudyDbRow(
            dot: row.color, title: row.name,
            end: {
              Text("\(row.count)")
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(row.count)))
            }
          )
          .staggeredEntrance(index: index, isReady: true)
        }
      }
      .animation(Motion.resolve(Motion.swap, reduceMotion), value: rows)
    }
  }

  // MARK: Falha

  private var failure: some View {
    VStack(alignment: .leading, spacing: 10) {
      StudyCallout(
        icon: "arrow.triangle.2.circlepath",
        tone: .yellow,
        title: "resposta não salva",
        detail: conflict ? "cartão mudou" : "tente de novo")
      if conflict {
        Button("atualizar", systemImage: "arrow.clockwise") { Task { await refreshQueue() } }
          .buttonStyle(.glass)
          .controlSize(.large)
          .tint(Color.studyInk)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: Cartão

  private func stack(card: Flashcard, index: Int, total: Int, phase: StudyReviewPhase)
    -> some View
  {
    ZStack(alignment: .top) {
      slip.padding(.horizontal, 20)
      slip.padding(.horizontal, 12).offset(y: 6)
      face(card: card, index: index, total: total, phase: phase)
        .padding(.top, 12)
    }
  }

  private var slip: some View {
    Color.clear.frame(height: 40).paperCard(radius: StudyRadius.card)
  }

  private func face(card: Flashcard, index: Int, total: Int, phase: StudyReviewPhase) -> some View {
    StudyReviewFlip(angle: flipAngle, onTurn: { showsBack = $0 }) { turned in
      side(card: card, index: index, total: total, back: reduceMotion ? phase == .back : turned)
    }
    .overlay(alignment: .bottom) { swipeHint }
    .rotationEffect(.degrees(tilt))
    .offset(x: dragX, y: cardY)
    .opacity(cardOpacity)
    .onTapGesture { flip() }
    .gesture(swipe, isEnabled: swipeEnabled)
    .sensoryFeedback(.impact(weight: .light), trigger: pastThreshold) { _, past in past }
    .accessibilityElement(children: .ignore)
    .accessibilityAddTraits(.isButton)
    .accessibilityLabel(phase == .back ? "\(card.front). resposta: \(card.back)" : card.front)
    .accessibilityValue("\(index + 1) de \(total)")
    .accessibilityHint(phase == .front ? "toque duas vezes para virar" : "")
    .accessibilityAction { flip() }
    .accessibilityActions {
      Button("virar") { flip() }
      if phase == .back {
        Button("errei") { Task { await grade(.errei, fling: nil) } }
        Button("fácil") { Task { await grade(.facil, fling: nil) } }
      }
    }
  }

  private var pastThreshold: Bool { abs(dragX) > StudyReviewSwipe.distance }

  /// A nota que o arrasto vai dar, acendendo conforme o cartão se afasta.
  private var swipeHint: some View {
    let toRight = dragX > 0
    return Label(toRight ? "fácil" : "errei", systemImage: toRight ? "checkmark" : "xmark")
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(toRight ? Color.studyBlue : StudyPillTone.coral.foreground)
      .padding(.horizontal, 12)
      .frame(minHeight: 32)
      .background(toRight ? Color.studySky : StudyPillTone.coral.background, in: .capsule)
      .padding(.bottom, 12)
      .opacity(swiping ? min(abs(dragX) / StudyReviewSwipe.distance, 1) : 0)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }

  private func side(card: Flashcard, index: Int, total: Int, back: Bool) -> some View {
    ZStack(alignment: .topLeading) {
      // O piso de 300 mora num filho invisível porque `frame(minHeight:)` não
      // repropõe a altura ao conteúdo, e o rodapé precisa dela para descer.
      Color.clear.frame(minHeight: 300)
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 8) {
          if let name = card.subjectName {
            StudyPill(color: card.subjectColor, text: name)
          }
          Spacer(minLength: 8)
          Text("\(index + 1)/\(total)")
            .font(.footnote)
            .monospacedDigit()
            .foregroundStyle(Color.studyInk40)
        }
        Text(card.front)
          .font(.system(size: frontSize, weight: .semibold).leading(.tight))
          .tracking(-frontSize * 0.02)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 36)
        if back {
          Text(card.back)
            .font(.system(size: backSize))
            .foregroundStyle(Color.studyGraphite)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 16)
            .modifier(StudyReviewAnswerEntrance())
        }
        Spacer(minLength: 28)
        Text(back ? "← errei · fácil →" : "toque para virar")
          .font(.system(size: instructionSize))
          .foregroundStyle(Color.studyInk40)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity, alignment: .center)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 18)
      .padding(.horizontal, 20)
    }
    .paperCard(radius: StudyRadius.card)
    .contentShape(.rect)
  }

  private var tilt: Double {
    min(max(Double(dragX) / 20, -6), 6)
  }

  private func grades(phase: StudyReviewPhase, hints: [FlashcardRating: String]) -> some View {
    HStack(spacing: 8) {
      ForEach(FlashcardRating.allCases, id: \.self) { rating in
        StudyReviewGradeButton(
          rating: rating,
          hint: hints[rating],
          isDisabled: phase == .front || grading || conflict
        ) {
          Task { await grade(rating, fling: nil) }
        }
      }
    }
  }

  // MARK: Arrasto

  private var swipeEnabled: Bool {
    guard case .card(_, let phase, _, let failed) = state else { return false }
    // Arrastar ainda de frente daria nota a um cartão que ninguém leu.
    return phase == .back && (reduceMotion || showsBack) && !grading && !conflict && !failed
  }

  private var swipe: some Gesture {
    DragGesture(minimumDistance: 10)
      .onChanged { value in
        // O cartão mora numa lista que rola. Sem travar a direção no primeiro
        // movimento, o dedo disputa o arrasto com a rolagem vertical.
        if !swiping {
          guard abs(value.translation.width) > abs(value.translation.height) else { return }
          swiping = true
        }
        dragX = value.translation.width
      }
      .onEnded { value in
        guard swiping else { return }
        swiping = false
        let travelled = abs(value.translation.width)
        let flicked = abs(value.velocity.width) > StudyReviewSwipe.velocity
          && travelled > StudyReviewSwipe.floor
        guard travelled > StudyReviewSwipe.distance || flicked else {
          withAnimation(returnCurve(velocity: value.velocity.width)) { dragX = 0 }
          return
        }
        let toRight = value.translation.width > 0
        Task {
          await grade(
            toRight ? .facil : .errei,
            fling: toRight ? StudyReviewSwipe.exit : -StudyReviewSwipe.exit,
            velocity: value.velocity.width)
        }
      }
  }

  /// A velocidade da mola é relativa ao que falta andar, e não ao módulo do
  /// deslocamento, senão a volta sai para o lado errado.
  private func returnCurve(velocity: CGFloat) -> Animation {
    fling(to: 0, velocity: velocity)
  }

  private func fling(to target: CGFloat, velocity: CGFloat) -> Animation {
    guard !reduceMotion else { return Motion.plain }
    let distance = target - dragX
    let relative = abs(distance) > 0.5 ? Double(velocity / distance) : 0
    return .interpolatingSpring(
      mass: 1, stiffness: 420, damping: 36, initialVelocity: min(max(relative, -40), 40))
  }

  // MARK: Virar

  /// A fase troca no toque e libera as notas na hora; o giro só alcança depois.
  /// Um segundo toque no meio do giro redireciona a mola sem esperar.
  private func flip() {
    guard case .card = state, !grading else { return }
    guard !reduceMotion else {
      withAnimation(Motion.plain) { dispatch(.flip) }
      return
    }
    dispatch(.flip)
    withAnimation(Motion.confirm) { flipAngle += 180 }
  }

  // MARK: Resposta

  private func grade(_ rating: FlashcardRating, fling: CGFloat?, velocity: CGFloat = 0) async {
    guard case .card(let index, let phase, _, _) = state, phase == .back, !grading, !conflict,
      let deck, deck.cards.indices.contains(index)
    else { return }
    let card = deck.cards[index]
    grading = true
    defer { grading = false }
    let exit = Duration.milliseconds(reduceMotion ? 150 : 200)
    let started = ContinuousClock.now
    if let fling {
      // A saída começa junto com a chamada. Esperar a rede com o cartão parado
      // debaixo do dedo faria o arrasto parecer travado.
      withAnimation(self.fling(to: fling, velocity: velocity)) {
        if !reduceMotion { dragX = fling }
      }
      withAnimation(Motion.plain) { cardOpacity = 0 }
    }
    do {
      let result = try await store.grade(card: card, rating: rating)
      dispatch(.hint(rating: rating, interval: result.interval))
      // O último cartão já vibra com a fila limpa; duas vibrações seguidas
      // contariam a mesma coisa.
      if index + 1 < deck.cards.count {
        lastRating = rating
        gradeTick += 1
      }
      if fling == nil {
        withAnimation(Motion.plain) {
          if !reduceMotion { cardY = -14 }
          cardOpacity = 0
        }
        try? await Task.sleep(for: exit)
      } else {
        try? await Task.sleep(for: max(.zero, exit - (ContinuousClock.now - started)))
      }
      dispatch(.advance(total: deck.cards.count))
      setNow {
        dragX = 0
        cardY = reduceMotion ? 0 : 14
        cardOpacity = 0
        flipAngle = 0
      }
      await holdFrame()
      withAnimation(Motion.resolve(Motion.subtleEntrance, reduceMotion)) {
        cardY = 0
        cardOpacity = 1
      }
    } catch {
      if case APIError.http(status: 409, _) = error { conflict = true }
      dispatch(.failed)
      withAnimation(returnCurve(velocity: 0)) {
        dragX = 0
        cardY = 0
        cardOpacity = 1
      }
    }
  }

  // MARK: Mecânica

  private func dispatch(_ action: StudyReviewAction) {
    state = state.reduce(action)
  }

  private func setNow(_ change: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, change)
  }

  /// Um valor escrito com animação desligada só vira ponto de partida depois de
  /// ser desenhado. Sem este quadro, a animação seguinte interpola a partir do
  /// valor anterior e o cartão anda para o lado errado.
  private func holdFrame() async {
    try? await Task.sleep(for: .milliseconds(16))
  }

  private func adopt(_ queue: ReviewQueue) {
    deck = queue
    state =
      queue.cards.isEmpty
      ? .empty : .card(index: 0, phase: .front, hints: [:], failed: false)
    conflict = false
    swiping = false
    setNow {
      dragX = 0
      cardY = 0
      cardOpacity = 1
      flipAngle = 0
    }
  }

  /// Puxar para baixo sem trocar a cópia congelada não mudaria nada na tela, e o
  /// botão do conflito precisa da mesma fila nova.
  private func refreshQueue() async {
    await store.loadQueue(force: true)
    guard let queue = store.queue.value else { return }
    adopt(queue)
  }
}

// MARK: - Peças

/// O lado à mostra sai do ângulo desenhado, quadro a quadro, e não da fase: a
/// fase já trocou no toque, e o verso só pode surgir quando o cartão passa de
/// perfil. Depois disso o conteúdo vai espelhado para o giro desfazer.
@Animatable
private struct StudyReviewFlip<Content: View>: View {
  var angle: Double
  @AnimatableIgnored var onTurn: (Bool) -> Void
  @AnimatableIgnored var content: (Bool) -> Content

  var body: some View {
    let turned = abs(angle.truncatingRemainder(dividingBy: 360))
    let back = turned > 90 && turned < 270
    content(back)
      .scaleEffect(x: back ? -1 : 1)
      .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.3)
      .onChange(of: back) { onTurn(back) }
  }
}

private struct StudyReviewAnswerEntrance: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var shown = false

  func body(content: Content) -> some View {
    content
      .animation(Motion.resolve(Motion.subtleEntrance, reduceMotion)) { view in
        view.opacity(shown ? 1 : 0)
      }
      .onAppear { shown = true }
  }
}

private struct StudyReviewGradeButton: View {
  let rating: FlashcardRating
  let hint: String?
  let isDisabled: Bool
  let action: () -> Void
  @ScaledMetric(relativeTo: .subheadline) private var labelSize = 14.0
  @ScaledMetric(relativeTo: .caption2) private var hintSize = 11.0

  var body: some View {
    Button(action: action) {
      VStack(spacing: 2) {
        Text(rating.label).font(.system(size: labelSize, weight: .semibold))
        if let hint {
          Text(hint)
            .font(.system(size: hintSize))
            .monospacedDigit()
            .foregroundStyle(hintColor)
        }
      }
      .multilineTextAlignment(.center)
      .foregroundStyle(labelColor)
      .padding(6)
      .frame(maxWidth: .infinity, minHeight: 52)
      .modifier(StudyGradeSurface(fill: rating == .facil ? .studyBlue : nil))
      .contentShape(.capsule)
    }
    .buttonStyle(StudyPressStyle())
    .disabled(isDisabled)
    .opacity(isDisabled ? 0.45 : 1)
  }

  private var labelColor: Color {
    switch rating {
    case .errei: Color(hex: 0xa3200e)
    case .dificil: .studyInk
    case .facil: .white
    }
  }

  private var hintColor: Color {
    rating == .facil ? .white.opacity(0.7) : .studyInk40
  }
}

/// Botão de nota: com `fill` é a cápsula sólida; sem, o branco com anel.
struct StudyGradeSurface: ViewModifier {
  let fill: Color?

  @ViewBuilder
  func body(content: Content) -> some View {
    if let fill {
      content.background(fill, in: .capsule)
    } else {
      content.elevated(Capsule())
    }
  }
}
