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
  let rest: RestState
  let onAdjust: (TimeInterval) -> Void
  let onDismiss: () -> Void

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.2)) { context in
      let remaining = rest.remaining(at: context.date)
      let over = remaining <= 0
      VStack(spacing: Space.m) {
        HStack(spacing: Space.l) {
          ZStack {
            Circle().stroke(ring.opacity(0.22), lineWidth: 5)
            Circle().trim(from: 0, to: rest.fraction(at: context.date))
              .stroke(ring, style: StrokeStyle(lineWidth: 5, lineCap: .round))
              .rotationEffect(.degrees(-90))
            Image(systemName: over ? "checkmark" : "timer").font(.caption.weight(.semibold))
          }
          .frame(width: 54, height: 54)
          .foregroundStyle(ring)
          VStack(alignment: .leading, spacing: 1) {
            Text(over ? "descanso acabou" : "descanso")
              .font(.caption.weight(.medium)).foregroundStyle(ring.opacity(0.75))
            Text(clock(remaining))
              .font(.system(size: 34, weight: .semibold)).monospacedDigit().tracking(-1.2)
            if let next = rest.next {
              Text("a seguir, \(next.exerciseName), série \(next.index) com \(weightLabel(next.weightKg))")
                .font(.caption2).foregroundStyle(ring.opacity(0.75)).lineLimit(1)
            } else {
              Text("última série do treino")
                .font(.caption2).foregroundStyle(ring.opacity(0.75))
            }
          }
          Spacer(minLength: 0)
        }
        HStack(spacing: Space.s) {
          step("−15s") { onAdjust(-15) }
          step("+15s") { onAdjust(15) }
          Button(over ? "fechar" : "pular", action: onDismiss)
            .buttonStyle(.glassProminent).tint(over ? .white : accent.deep)
            .foregroundStyle(over ? accent.deep : .white)
            .controlSize(.large).frame(maxWidth: .infinity)
        }
      }
      .foregroundStyle(over ? .white : Color.ink)
      .padding(Space.l)
      .background(over ? AnyShapeStyle(accent.deep) : AnyShapeStyle(accent.acid.opacity(0.92)),
        in: .rect(cornerRadius: Radius.card))
      .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(accent.deep.opacity(over ? 0 : 0.14)))
      .shadow(color: accent.deep.opacity(0.16), radius: 22, y: 10)
      .sensoryFeedback(.success, trigger: over) { _, fired in fired }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("descanso")
      .accessibilityValue(clock(remaining))
    }
  }

  private var ring: Color { accent.deep }

  private func step(_ title: String, action: @escaping () -> Void) -> some View {
    Button(title, action: action)
      .buttonStyle(.glass).controlSize(.large).frame(maxWidth: .infinity)
  }

  private func clock(_ seconds: TimeInterval) -> String {
    let whole = Int(seconds.rounded())
    return "\(whole / 60):\(String(format: "%02d", whole % 60))"
  }
}
