import HenriqueCore
import SwiftUI

/// A série que vem depois da que acabou de ser marcada. O descanso só ajuda com o
/// próximo peso à vista, e a busca segue para o exercício seguinte porque terminar
/// um exercício não encerra a pausa.
struct NextSet: Equatable {
  let exerciseName: String
  let index: Int
  let weightKg: Double

  init?(from exerciseIndex: Int, in workout: WorkoutSummary) {
    guard workout.exercises.indices.contains(exerciseIndex) else { return nil }
    for step in 0..<workout.exercises.count {
      let exercise = workout.exercises[(exerciseIndex + step) % workout.exercises.count]
      if let pending = exercise.sets.work.first(where: { !$0.isDone }) {
        exerciseName = exercise.name.lowercased()
        index = pending.index
        weightKg = pending.weightKg
        return
      }
    }
    return nil
  }
}

/// O descanso em curso. O fim é uma data, não um contador que decrementa: a tela
/// apaga entre uma série e outra e um contador por quadro pararia junto.
struct RestState: Equatable {
  var total: TimeInterval
  var endsAt: Date
  var next: NextSet?

  func remaining(at now: Date) -> TimeInterval { max(0, endsAt.timeIntervalSince(now)) }
  func fraction(at now: Date) -> Double { total <= 0 ? 0 : remaining(at: now) / total }
}

let defaultRestSeconds: TimeInterval = 90

struct RestTimerBar: View {
  @Environment(\.accent) private var accent
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .largeTitle) private var timeSize = 38.0
  @ScaledMetric(relativeTo: .caption) private var labelSize = 11.5
  @ScaledMetric(relativeTo: .footnote) private var nextSize = 12.5
  @ScaledMetric(relativeTo: .body) private var buttonSize = 15.0
  let rest: RestState
  let onAdjust: (TimeInterval) -> Void
  let onDismiss: () -> Void

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.2)) { context in
      let remaining = rest.remaining(at: context.date)
      let whole = Int(remaining.rounded())
      let over = remaining <= 0
      VStack(spacing: 0) {
        HStack(spacing: 14) {
          ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: 5)
            Circle().trim(from: 0, to: rest.fraction(at: context.date))
              .stroke(accent.acid, style: StrokeStyle(lineWidth: 5, lineCap: .round))
              .rotationEffect(.degrees(-90))
          }
          .frame(width: 54, height: 54)
          VStack(alignment: .leading, spacing: 0) {
            Text(over ? "descanso completo" : "descanso")
              .font(.system(size: labelSize, design: .monospaced)).tracking(labelSize * 0.03)
              .foregroundStyle(accent.acid)
              .padding(.bottom, 2)
            Group {
              if over {
                Text("vai").foregroundStyle(accent.acid)
              } else {
                Text(clock(remaining)).foregroundStyle(.white)
                  .contentTransition(.numericText(countsDown: true))
              }
            }
            .font(.system(size: timeSize, weight: .semibold)).monospacedDigit()
            .tracking(timeSize * -0.055)
            .animation(reduceMotion ? nil : Motion.roll, value: whole)
            Group {
              if let next = rest.next {
                Text("a seguir · \(next.exerciseName) · série \(next.index) · \(weightLabel(next.weightKg))")
              } else {
                Text("última série do treino")
              }
            }
            .font(.system(size: nextSize)).monospacedDigit()
            .foregroundStyle(Color.white.opacity(0.62)).lineLimit(1)
            .padding(.top, 4)
          }
          Spacer(minLength: 0)
        }
        WeightedRow(weights: [1, 1, 1.3], spacing: 8) {
          step("−15s") { onAdjust(-15) }
          step("+15s") { onAdjust(15) }
          Button(action: onDismiss) {
            Text(over ? "fechar" : "pular")
              .font(.system(size: buttonSize, weight: .semibold)).foregroundStyle(accent.deep)
              .padding(.vertical, 13).frame(maxWidth: .infinity)
              .background(accent.acid, in: .capsule)
          }
          .buttonStyle(PressScaleStyle())
        }
        .padding(.top, 16)
      }
      .padding(.top, 16).padding(.horizontal, 18).padding(.bottom, 18)
      .background(over ? accent.base : accent.deep, in: .rect(cornerRadius: 30))
      .shadow(color: accent.deep.opacity(0.75), radius: 24, y: 12)
      .animation(reduceMotion ? nil : Motion.crossfade, value: over)
      .sensoryFeedback(.success, trigger: over) { _, fired in fired }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("descanso")
      .accessibilityValue(clock(remaining))
    }
  }

  private func step(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: buttonSize, weight: .medium)).monospacedDigit()
        .foregroundStyle(Color.white.opacity(0.93))
        .padding(.vertical, 13).frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.12), in: .capsule)
    }
    .buttonStyle(PressScaleStyle())
  }

  private func clock(_ seconds: TimeInterval) -> String {
    let whole = Int(seconds.rounded())
    return "\(whole / 60):\(String(format: "%02d", whole % 60))"
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
