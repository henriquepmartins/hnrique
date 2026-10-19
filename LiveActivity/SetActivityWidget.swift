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
              DoneButton(target: up.target, exerciseName: up.exerciseName, tone: tone)
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
          DoneButton(target: up.target, exerciseName: up.exerciseName, tone: tone)
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

/// A cor do treino e a tinta que vai por cima dela: tinta escura do mesmo matiz
/// ou branca, a que tiver mais contraste. O contraste é o do APCA, que pesa como
/// o olho lê cor saturada; pela conta do WCAG 2 o vermelho ficava com a tinta
/// escura, que some nele.
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
    let dark = UIColor(
      hue: hue, saturation: min(1, saturation * 1.1), brightness: brightness * 0.26, alpha: 1)
    ink = abs(apcaContrast(text: dark, on: color)) > abs(apcaContrast(text: .white, on: color))
      ? Color(uiColor: dark) : .white
  }
}

/// O Lc do APCA 0.0.98G: positivo para texto escuro em fundo claro, negativo ao contrário.
private func apcaContrast(text: UIColor, on background: UIColor) -> Double {
  func luminance(_ color: UIColor) -> Double {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    color.getRed(&red, green: &green, blue: &blue, alpha: nil)
    let y = 0.2126729 * pow(Double(red), 2.4) + 0.7151522 * pow(Double(green), 2.4)
      + 0.0721750 * pow(Double(blue), 2.4)
    return y > 0.022 ? y : y + pow(0.022 - y, 1.414)
  }
  let text = luminance(text)
  let background = luminance(background)
  if background > text {
    let contrast = (pow(background, 0.56) - pow(text, 0.57)) * 1.14
    return contrast < 0.1 ? 0 : (contrast - 0.027) * 100
  }
  let contrast = (pow(background, 0.65) - pow(text, 0.62)) * 1.14
  return contrast > -0.1 ? 0 : (contrast + 0.027) * 100
}
