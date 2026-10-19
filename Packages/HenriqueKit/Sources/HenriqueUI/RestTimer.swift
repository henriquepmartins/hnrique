import HenriqueCore
import SwiftUI

/// O descanso em curso. O fim é uma data, não um contador que decrementa: a tela
/// apaga entre uma série e outra, o app vai para o fundo, e um contador por
/// quadro pararia junto. A série que abriu o descanso fica junto porque só
/// desmarcar ela encerra a pausa.
public struct RestState: Codable, Equatable, Sendable {
  public let key: SetKey
  public let startedAt: Date
  public private(set) var endsAt: Date

  /// Quanto a barra fica dizendo "vai" depois do fim antes de sair sozinha.
  static let linger: TimeInterval = 6

  public init(key: SetKey, startedAt: Date, seconds: TimeInterval) {
    self.key = key
    self.startedAt = startedAt
    endsAt = startedAt + seconds
  }

  public var exerciseId: String { key.exerciseId }
  public var total: TimeInterval { endsAt.timeIntervalSince(startedAt) }
  var expiresAt: Date { endsAt + Self.linger }

  public func remaining(at now: Date) -> TimeInterval { max(0, endsAt.timeIntervalSince(now)) }
  public func fraction(at now: Date) -> Double { total <= 0 ? 0 : remaining(at: now) / total }
  public func isExpired(at now: Date) -> Bool { now >= expiresAt }

  /// O ±15 s mexe na duração inteira, contada do começo, dentro da faixa do plano.
  public func adjusted(by delta: TimeInterval) -> RestState {
    let seconds = (total + delta).clamped(
      to: TimeInterval(Limits.restSeconds.lowerBound)...TimeInterval(Limits.restSeconds.upperBound))
    return RestState(key: key, startedAt: startedAt, seconds: seconds)
  }
}

/// "1:05". Montado à mão porque roda a cada quadro da barra, e `String(format:)`
/// passa pelo parser de formato toda vez.
func restClock(_ seconds: TimeInterval) -> String {
  let whole = max(0, Int(seconds.rounded()))
  let rest = whole % 60
  return "\(whole / 60):\(rest < 10 ? "0" : "")\(rest)"
}

struct RestTimerBar: View {
  @Environment(\.accent) private var accent
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .title) private var timeSize = 26.0
  @ScaledMetric(relativeTo: .footnote) private var nextSize = 12.5
  @ScaledMetric(relativeTo: .body) private var buttonSize = 15.0
  let rest: RestState
  let next: NextSet?
  let onAdjust: (TimeInterval) -> Void
  let onDismiss: () -> Void

  private var nextLine: String {
    next?.summary ?? "última série do treino"
  }

  private var spokenNext: String {
    guard let next else { return "última série do treino" }
    let kind = next.kind == .prep ? "aquecimento \(next.index)" : "série \(next.index)"
    return "a seguir, \(next.exerciseName.lowercased()), \(kind), \(Formatting.trim(next.weightKg)) quilos"
  }

  /// O fim de descanso que já passou. Guardar o fim, e não um "acabou", impede
  /// que um descanso novo na mesma barra herde o estado do anterior por um quadro.
  @State private var finished: Date?
  @State private var adjustments = 0

  private var over: Bool { finished == rest.endsAt }

  init(
    rest: RestState, next: NextSet?, onAdjust: @escaping (TimeInterval) -> Void,
    onDismiss: @escaping () -> Void
  ) {
    self.rest = rest
    self.next = next
    self.onAdjust = onAdjust
    self.onDismiss = onDismiss
    _finished = State(initialValue: rest.remaining(at: .now) <= 0 ? rest.endsAt : nil)
  }

  /// Compacto de propósito: o cartão encolhe a lista por baixo, e alto ele
  /// tapava o "+ série" e o exercício seguinte. O cartão só redesenha quando o
  /// descanso acaba; o anel e os dígitos têm cada um o seu relógio.
  var body: some View {
    VStack(spacing: 10) {
      HStack(spacing: 12) {
        RestRing(rest: rest, color: accent.acid, paused: over)
          .frame(width: 36, height: 36)
          .accessibilityHidden(true)
        digits
        Text(nextLine)
          .font(.system(size: nextSize)).monospacedDigit()
          .foregroundStyle(Color.white.opacity(0.62)).lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityLabel(spokenNext)
      }
      WeightedRow(weights: [1, 1, 1.3], spacing: 8) {
        step("−15s", spoken: "menos 15 segundos") { onAdjust(-15) }
        step("+15s", spoken: "mais 15 segundos") { onAdjust(15) }
        Button(action: onDismiss) {
          Text(over ? "fechar" : "pular")
            .font(.system(size: buttonSize, weight: .semibold)).foregroundStyle(accent.deep)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(accent.acid, in: .capsule)
        }
        .buttonStyle(StudyPressStyle())
      }
      .sensoryFeedback(.selection, trigger: adjustments)
    }
    .padding(12)
    .background {
      RoundedRectangle(cornerRadius: 24)
        .fill(over ? accent.base : accent.deep)
        .shadow(color: accent.deep.opacity(0.75), radius: 24, y: 12)
    }
    .animation(Motion.resolve(Motion.crossfade, reduceMotion), value: over)
    .sensoryFeedback(.success, trigger: over) { _, fired in fired }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("descanso")
    .accessibilityIdentifier("descanso.cartao")
    .task(id: rest.endsAt) {
      let left = rest.remaining(at: .now)
      if left > 0 {
        guard (try? await Task.sleep(for: .seconds(left))) != nil else { return }
        AccessibilityNotification.Announcement("descanso completo").post()
      }
      finished = rest.endsAt
    }
    .task(id: rest.startedAt) {
      // O cartão volta a montar quando o teclado fecha; só o começo de verdade é anunciado.
      guard Date.now.timeIntervalSince(rest.startedAt) < 2 else { return }
      AccessibilityNotification.Announcement("descanso de \(restClock(rest.total))").post()
    }
  }

  /// O número arredondado troca no meio de cada segundo contado do início, então
  /// o tick cai ali; a âncora fica meio segundo antes do início para nunca estar
  /// no futuro. Lido 10 ms depois do tick, o arredondamento não fica em cima do
  /// meio exato, onde o erro de ponto flutuante decide para que lado vai.
  private var digits: some View {
    TimelineView(.periodic(from: rest.startedAt - 0.5, by: 1)) { context in
      let remaining = rest.remaining(at: context.date + 0.01)
      Group {
        if over {
          Text("vai").foregroundStyle(accent.acid)
        } else {
          Text(restClock(remaining)).foregroundStyle(.white)
            .contentTransition(.numericText(countsDown: true))
        }
      }
      .font(.system(size: timeSize, weight: .semibold)).monospacedDigit()
      .tracking(timeSize * -0.05)
      .fixedSize()
      .animation(reduceMotion ? nil : Motion.roll, value: Int(remaining.rounded()))
      .accessibilityLabel(over ? "descanso completo" : "descanso")
      .accessibilityValue(over ? "" : restClock(remaining))
    }
  }

  private func step(_ title: String, spoken: String, action: @escaping () -> Void) -> some View {
    Button {
      action()
      adjustments += 1
    } label: {
      Text(title)
        .font(.system(size: buttonSize, weight: .medium)).monospacedDigit()
        .foregroundStyle(Color.white.opacity(0.93))
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Color.white.opacity(0.12), in: .capsule)
    }
    .buttonStyle(StudyPressStyle())
    .accessibilityLabel(spoken)
  }
}

/// O anel do descanso, redesenhado a 30 quadros por segundo para esvaziar liso.
/// Num anel de 36 pontos que leva um minuto ou mais, 120 não se distinguem e só
/// gastam bateria. É o único pedaço do cartão que precisa disso, e para quando o
/// descanso acaba.
private struct RestRing: View {
  let rest: RestState
  let color: Color
  let paused: Bool

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { context in
      ZStack {
        Circle().stroke(Color.white.opacity(0.18), lineWidth: 4)
        Circle().trim(from: 0, to: paused ? 0 : rest.fraction(at: context.date))
          .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
          .rotationEffect(.degrees(-90))
      }
    }
  }
}

/// Uma linha em que cada filho leva uma fatia da largura proporcional ao seu
/// peso. É o `flex: 1.3 1 0` do botão de pular contra o `1 1 0` dos outros.
struct WeightedRow: Layout {
  let weights: [CGFloat]
  let spacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
    return CGSize(width: proposal.width ?? 0, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let total = weights.reduce(0, +)
    let free = bounds.width - spacing * CGFloat(max(0, subviews.count - 1))
    var x = bounds.minX
    for (index, subview) in subviews.enumerated() {
      let weight = weights.indices.contains(index) ? weights[index] : 1
      let width = free * weight / total
      subview.place(
        at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
        proposal: ProposedViewSize(width: width, height: bounds.height))
      x += width + spacing
    }
  }
}
