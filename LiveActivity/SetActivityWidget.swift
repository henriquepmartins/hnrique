import ActivityKit
import AppIntents
import HenriqueCore
import SwiftUI
import WidgetKit

struct SetActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: SetActivityAttributes.self) { context in
      LockScreenView(context: context)
        .widgetURL(URL(string: "henrique://sessao"))
    } dynamicIsland: { context in
      let tone = Tone(hex: context.attributes.toneHex)
      let state = context.state
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          VStack(alignment: .leading, spacing: 4) {
            if let up = state.up {
              SetLabel(text: up.setLabel, tone: tone)
              Elapsed(startedAt: context.attributes.startedAt, state: state)
                .font(.caption).foregroundStyle(.secondary)
            } else if state.finishedAt != nil {
              FinishedMark(tone: tone)
            }
          }
          .padding(.leading, 6)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Countdown(startedAt: context.attributes.startedAt, state: state, isStale: context.isStale)
            .font(.title3.weight(.semibold))
            .padding(.trailing, 6)
        }
        DynamicIslandExpandedRegion(.center) {
          Text(state.up?.exerciseName ?? context.attributes.workoutName)
            .font(.headline)
            .lineLimit(1)
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack {
            if let up = state.up {
              Load(up: up, tone: tone)
              Spacer()
              DoneButton(target: up.target, exerciseName: up.exerciseName, tone: tone)
            } else {
              Score(done: state.done, total: state.total, tone: tone)
              Progress(done: state.done, total: state.total, tone: tone)
            }
          }
          .padding(.horizontal, 6)
        }
      } compactLeading: {
        if let up = state.up {
          SetLabel(text: up.setLabel, tone: tone)
        } else {
          FinishedMark(tone: tone)
        }
      } compactTrailing: {
        if let rest = state.rest, !context.isStale {
          Text(timerInterval: rest, countsDown: true)
            .monospacedDigit()
            .frame(maxWidth: 44)
        } else if let up = state.up {
          Text(up.weight).monospacedDigit()
        } else {
          Text("\(state.done)/\(state.total)").monospacedDigit()
            .accessibilityLabel("\(state.done) de \(state.total) séries")
        }
      } minimal: {
        if let rest = state.rest, !context.isStale {
          ProgressView(timerInterval: rest, countsDown: true) { EmptyView() }
            .progressViewStyle(.circular)
            .tint(tone.fill)
        } else if state.up == nil {
          FinishedMark(tone: tone)
        } else {
          Image(systemName: "dumbbell.fill").foregroundStyle(tone.fill)
        }
      }
      .widgetURL(URL(string: "henrique://sessao"))
      .keylineTint(tone.fill)
    }
  }
}

private struct LockScreenView: View {
  let context: ActivityViewContext<SetActivityAttributes>

  var body: some View {
    let tone = Tone(hex: context.attributes.toneHex)
    let state = context.state
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text(state.up?.exerciseName ?? context.attributes.workoutName)
          .font(.headline)
          .lineLimit(1)
        Spacer(minLength: 8)
        Countdown(startedAt: context.attributes.startedAt, state: state, isStale: context.isStale)
          .font(.title2.weight(.semibold))
      }
      if let up = state.up {
        HStack(spacing: 10) {
          SetLabel(text: up.setLabel, tone: tone)
          Load(up: up, tone: tone)
          Spacer(minLength: 8)
          DoneButton(target: up.target, exerciseName: up.exerciseName, tone: tone)
        }
      } else {
        Score(done: state.done, total: state.total, tone: tone)
      }
      HStack(spacing: 10) {
        Progress(done: state.done, total: state.total, tone: tone)
        if state.finishedAt == nil {
          Elapsed(startedAt: context.attributes.startedAt, state: state)
            .font(.caption).foregroundStyle(.secondary)
        }
      }
    }
    .padding(16)
    .accessibilityElement(children: .contain)
  }
}

/// O contador do descanso. Passado o fim, a atividade fica velha e troca para
/// "vai". No treino acabado, o tempo final parado.
private struct Countdown: View {
  let startedAt: Date?
  let state: SetActivityState
  let isStale: Bool

  var body: some View {
    if state.finishedAt != nil {
      Elapsed(startedAt: startedAt, state: state)
    } else if let rest = state.rest, !isStale {
      Text(timerInterval: rest, countsDown: true)
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: 80, alignment: .trailing)
        .accessibilityLabel("descanso")
    } else if state.up != nil {
      Text("vai")
    }
  }
}

/// O tempo de treino desde a primeira série: correndo durante o treino, parado
/// no fim. Some numa atividade que não sabe o começo.
private struct Elapsed: View {
  let startedAt: Date?
  let state: SetActivityState

  var body: some View {
    if let startedAt {
      Group {
        if let end = state.finishedAt {
          Text(timerInterval: startedAt...max(startedAt, end), pauseTime: max(startedAt, end), countsDown: false)
        } else {
          Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
        }
      }
      .monospacedDigit()
      .multilineTextAlignment(.trailing)
      .frame(maxWidth: 80, alignment: .trailing)
      .accessibilityLabel("tempo de treino")
    }
  }
}

/// O placar do treino acabado, no lugar da linha da série.
private struct Score: View {
  let done: Int
  let total: Int
  let tone: Tone

  var body: some View {
    Label {
      Text("\(done)/\(total)").monospacedDigit()
    } icon: {
      Image(systemName: "checkmark.circle.fill").foregroundStyle(tone.fill)
    }
    .font(.body.weight(.medium))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("treino encerrado, \(done) de \(total) séries")
  }
}

private struct FinishedMark: View {
  let tone: Tone

  var body: some View {
    Image(systemName: "checkmark.circle.fill").foregroundStyle(tone.fill)
      .accessibilityLabel("treino encerrado")
  }
}

private struct SetLabel: View {
  let text: String
  let tone: Tone

  var body: some View {
    Text(text)
      .font(.subheadline.weight(.bold))
      .monospacedDigit()
      .foregroundStyle(tone.ink)
      .padding(.horizontal, 7)
      .frame(minWidth: 26, minHeight: 22)
      .background(tone.fill, in: Capsule())
      .accessibilityLabel(text.hasPrefix("A") ? "aquecimento \(text.dropFirst())" : "série \(text)")
  }
}

/// "48 kg × 8" e o raio quando a série vai até a falha.
private struct Load: View {
  let up: SetActivityState.Up
  let tone: Tone

  var body: some View {
    HStack(spacing: 4) {
      Text("\(up.weight) × \(up.reps)")
        .font(.body.weight(.medium))
        .monospacedDigit()
      if up.toFailure {
        Image(systemName: "bolt.fill")
          .font(.caption)
          .foregroundStyle(tone.fill)
          .accessibilityLabel("até a falha")
      }
    }
  }
}

private struct DoneButton: View {
  let target: SetKey
  let exerciseName: String
  let tone: Tone

  var body: some View {
    Button(intent: CompleteSetIntent(target)) {
      Label("feito", systemImage: "checkmark")
        .font(.body.weight(.semibold))
        .foregroundStyle(tone.ink)
        .padding(.horizontal, 18)
        .frame(minHeight: 44)
        .background(tone.fill, in: Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      "marcar \(target.kind == .prep ? "aquecimento" : "série") \(target.index), \(exerciseName.lowercased())")
  }
}

private struct Progress: View {
  let done: Int
  let total: Int
  let tone: Tone

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(.secondary.opacity(0.25))
        Capsule().fill(tone.fill)
          .frame(width: total == 0 ? 0 : proxy.size.width * CGFloat(min(done, total)) / CGFloat(total))
      }
    }
    .frame(height: 4)
    .accessibilityElement()
    .accessibilityLabel("séries")
    .accessibilityValue("\(done) de \(total)")
  }
}

/// A cor do treino e a tinta que vai por cima dela, pela mesma conta que a
/// sessão no app usa.
private struct Tone {
  let fill: Color
  let ink: Color

  init(hex: String?) {
    let fill = hex.flatMap(ToneRGB.init(hex:)) ?? ToneRGB(hex: "22c55e")!
    self.fill = Color(fill)
    ink = Color(ToneContrast.ink(on: fill))
  }
}

extension Color {
  fileprivate init(_ rgb: ToneRGB) {
    self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
  }
}
