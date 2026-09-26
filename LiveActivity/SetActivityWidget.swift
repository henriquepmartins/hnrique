import ActivityKit
import AppIntents
import HenriqueCore
import SwiftUI
import UIKit
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
          if let up = state.up {
            SetLabel(text: up.setLabel, tone: tone).padding(.leading, 6)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          Countdown(state: state, isStale: context.isStale)
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
              DoneButton(target: up.target, tone: tone)
            } else {
              Progress(done: state.done, total: state.total, tone: tone)
            }
          }
          .padding(.horizontal, 6)
        }
      } compactLeading: {
        if let up = state.up {
          SetLabel(text: up.setLabel, tone: tone)
        } else {
          Image(systemName: "checkmark").foregroundStyle(tone.fill)
        }
      } compactTrailing: {
        if let rest = state.rest, !context.isStale {
          Text(timerInterval: rest, countsDown: true)
            .monospacedDigit()
            .frame(maxWidth: 44)
        } else if let up = state.up {
          Text(up.weight).monospacedDigit()
        }
      } minimal: {
        if let rest = state.rest, !context.isStale {
          ProgressView(timerInterval: rest, countsDown: true) { EmptyView() }
            .progressViewStyle(.circular)
            .tint(tone.fill)
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
        Countdown(state: state, isStale: context.isStale)
          .font(.title2.weight(.semibold))
      }
      if let up = state.up {
        HStack(spacing: 10) {
          SetLabel(text: up.setLabel, tone: tone)
          Load(up: up, tone: tone)
          Spacer(minLength: 8)
          DoneButton(target: up.target, tone: tone)
        }
      }
      Progress(done: state.done, total: state.total, tone: tone)
    }
    .padding(16)
    .accessibilityElement(children: .contain)
  }
}

/// O contador do descanso. Passado o fim, a atividade fica velha e troca para "vai".
private struct Countdown: View {
  let state: SetActivityState
  let isStale: Bool

  var body: some View {
    if let rest = state.rest, !isStale {
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
  let tone: Tone

  var body: some View {
    Button(intent: CompleteSetIntent(target)) {
      Text("feito")
        .font(.body.weight(.semibold))
        .foregroundStyle(tone.ink)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(tone.fill, in: Capsule())
    }
    .buttonStyle(.plain)
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

/// A cor do treino e a tinta que vai por cima dela, com a mesma regra do app:
/// tinta escura do mesmo matiz, e branca quando a cor já é escura.
private struct Tone {
  let fill: Color
  let ink: Color

  init(hex: String?) {
    var digits = Substring(hex ?? "")
    if digits.hasPrefix("#") { digits = digits.dropFirst() }
    let rgb = digits.count == 6 ? UInt32(digits, radix: 16) ?? 0x22_c55e : 0x22_c55e
    let color = UIColor(
      red: CGFloat((rgb >> 16) & 0xff) / 255, green: CGFloat((rgb >> 8) & 0xff) / 255,
      blue: CGFloat(rgb & 0xff) / 255, alpha: 1)
    var hue: CGFloat = 0
    var saturation: CGFloat = 0
    var brightness: CGFloat = 0
    color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
    fill = Color(uiColor: color)
    ink = brightness < 0.4
      ? .white : Color(hue: hue, saturation: min(1, saturation * 1.1), brightness: brightness * 0.26)
  }
}
