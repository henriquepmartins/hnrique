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

  /// "puxada alta · 48 kg", ou "puxada alta · A · 35 kg" no aquecimento.
  private var nextLine: String {
    guard let next else { return "última série do treino" }
    let kind = next.kind == .prep ? " · A" : ""
    return "\(next.exerciseName.lowercased())\(kind) · \(Formatting.trim(next.weightKg)) kg"
  }

  private var spokenNext: String {
    guard let next else { return "última série do treino" }
    let kind = next.kind == .prep ? "aquecimento" : "série \(next.index)"
    return "a seguir, \(next.exerciseName.lowercased()), \(kind), \(Formatting.trim(next.weightKg)) quilos"
  }

  /// Compacto de propósito: o cartão encolhe a lista por baixo, e alto ele
  /// tapava o "+ série" e o exercício seguinte.
  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.2)) { context in
      let remaining = rest.remaining(at: context.date)
      let whole = Int(remaining.rounded())
      let over = remaining <= 0
      VStack(spacing: 10) {
        HStack(spacing: 12) {
          ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: 4)
            Circle().trim(from: 0, to: rest.fraction(at: context.date))
              .stroke(accent.acid, style: StrokeStyle(lineWidth: 4, lineCap: .round))
              .rotationEffect(.degrees(-90))
          }
          .frame(width: 36, height: 36)
          .accessibilityHidden(true)
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
          .animation(reduceMotion ? nil : Motion.roll, value: whole)
          .accessibilityLabel(over ? "descanso completo" : "descanso")
          .accessibilityValue(over ? "" : restClock(remaining))
          Text(nextLine)
            .font(.system(size: nextSize)).monospacedDigit()
            .foregroundStyle(Color.white.opacity(0.62)).lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(spokenNext)
        }
        WeightedRow(weights: [1, 1, 1.3], spacing: 8) {
          step("−15s") { onAdjust(-15) }
          step("+15s") { onAdjust(15) }
          Button(action: onDismiss) {
            Text(over ? "fechar" : "pular")
              .font(.system(size: buttonSize, weight: .semibold)).foregroundStyle(accent.deep)
              .padding(.vertical, 9).frame(maxWidth: .infinity)
              .background(accent.acid, in: .capsule)
          }
          .buttonStyle(PressScaleStyle())
        }
      }
      .padding(12)
      .background(over ? accent.base : accent.deep, in: .rect(cornerRadius: 24))
      .shadow(color: accent.deep.opacity(0.75), radius: 24, y: 12)
      .animation(reduceMotion ? nil : Motion.crossfade, value: over)
      .sensoryFeedback(.success, trigger: over) { _, fired in fired }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("descanso")
      .accessibilityIdentifier("descanso.cartao")
    }
  }

  private func step(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: buttonSize, weight: .medium)).monospacedDigit()
        .foregroundStyle(Color.white.opacity(0.93))
        .padding(.vertical, 9).frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.12), in: .capsule)
    }
    .buttonStyle(PressScaleStyle())
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

/// Encolhe sob o dedo, como os botões do board, sem o vidro do sistema. A
/// escala é um parâmetro porque o check da série encolhe mais que o resto.
struct PressScaleStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var scale: CGFloat = Motion.press

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .contentShape(.rect)
      .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
      .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
      .animation(configuration.isPressed ? nil : Motion.tap, value: configuration.isPressed)
  }
}
