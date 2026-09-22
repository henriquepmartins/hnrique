import HenriqueCore
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

/// A tela escura do cronômetro. Enquanto roda mostra a sessão; ao parar, a
/// mesma tela troca para o resultado.
struct FocoRunningScreen: View {
  @Environment(FocoStore.self) private var foco
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var result: FocoResult?

  var body: some View {
    Group {
      if let result {
        FocoResultView(result: result, track: result.entry?.track ?? foco.ledger.running?.track) {
          dismiss()
        }
        .transition(.blurReplace)
      } else if let run = foco.ledger.running {
        FocoTimerView(run: run, minimize: { dismiss() }) {
          result = foco.stop()
        }
        .transition(.blurReplace)
      } else {
        // A corrida foi parada pela lista com o cover fechado; nada a mostrar.
        Color.clear.onAppear { dismiss() }
      }
    }
    .animation(reduceMotion ? nil : Motion.crossfade, value: result == nil)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.studyBlack.ignoresSafeArea())
    .foregroundStyle(Color.studyCream)
    .tint(Color.studyCream)
    .preferredColorScheme(.dark)
    .onAppear { keepScreenAwake(true) }
    .onDisappear { keepScreenAwake(false) }
  }

  private func keepScreenAwake(_ awake: Bool) {
    #if canImport(UIKit)
      UIApplication.shared.isIdleTimerDisabled = awake
    #endif
  }
}

// MARK: - Cronômetro

private struct FocoTimerView: View {
  @Environment(FocoStore.self) private var foco
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .largeTitle) private var timerSize = 101.0
  let run: FocoRun
  let minimize: () -> Void
  let stop: () -> Void

  private var color: Color { Color(hexString: run.track.color) }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Circle().fill(color).frame(width: 10, height: 10)
        Text(run.track.name)
          .font(.title3)
          .lineLimit(1)
        Spacer(minLength: 0)
        IconButton(title: "minimizar", systemImage: "chevron.down", size: 20, action: minimize)
      }
      .padding(.leading, 16)
      .padding(.trailing, 3)
      Spacer(minLength: 0)
      TimelineView(.periodic(from: .now, by: 1)) { context in
        let seconds = run.seconds(at: context.date)
        let today = foco.ledger.seconds(
          on: CalendarDate(context.date, in: StudyFormat.calendar), now: context.date,
          calendar: StudyFormat.calendar)
        VStack(spacing: 12) {
          Text(FocoFormat.clock(seconds))
            .font(.system(size: timerSize, weight: .semibold).leading(.tight))
            .monospacedDigit()
            .tracking(-timerSize * 0.011)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .offset(x: -1.5)
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : Motion.crossfade, value: Int(seconds))
            .accessibilityLabel("\(FocoFormat.spoken(seconds)) nesta sessão")
          Text("hoje \(FocoFormat.clock(today))")
            .font(.subheadline)
            .monospacedDigit()
            .contentTransition(.numericText())
            .foregroundStyle(Color.studyCream50)
        }
        .padding(.horizontal, 24)
      }
      .background { aura }
      Spacer(minLength: 0)
      Button(action: stop) {
        Label("parar", systemImage: "stop.fill").padding(.leading, -1.5)
      }
        .buttonStyle(.glassProminent)
        .tint(color)
        .controlSize(.large)
        .font(.headline)
        .accessibilityLabel("parar")
        .padding(.bottom, 32)
    }
    .padding(.top, 8)
  }

  /// Um círculo borrado na cor da trilha que respira devagar atrás do número.
  @ViewBuilder private var aura: some View {
    if reduceMotion {
      auraCircle(scale: 1, opacity: 0.45)
    } else {
      TimelineView(.animation) { context in
        let angle = context.date.timeIntervalSinceReferenceDate / 4 * 2 * .pi
        let wave = (sin(angle) + 1) / 2
        auraCircle(scale: 0.92 + 0.13 * wave, opacity: 0.35 + 0.25 * wave)
      }
    }
  }

  private func auraCircle(scale: Double, opacity: Double) -> some View {
    Circle()
      .fill(color)
      .frame(width: 280, height: 280)
      .blur(radius: 70)
      .scaleEffect(scale)
      .opacity(opacity)
      .allowsHitTesting(false)
  }
}

// MARK: - Resultado

private struct FocoResultView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .largeTitle) private var bigSize = 72.0
  let result: FocoResult
  let track: FocoTrack?
  let close: () -> Void

  @State private var minutes = 0
  @State private var streakShown: Int
  @State private var celebrate = false

  init(result: FocoResult, track: FocoTrack?, close: @escaping () -> Void) {
    self.result = result
    self.track = track
    self.close = close
    _streakShown = State(initialValue: result.streakBefore.current)
  }

  private var streakRose: Bool { result.streakAfter.current > result.streakBefore.current }
  private var party: Bool { result.entry != nil && (streakRose || result.goalJustReached) }

  var body: some View {
    VStack(spacing: 24) {
      Spacer(minLength: 0)
      if let entry = result.entry {
        Text(entry.seconds < 60 ? "+\(minutes) s" : "+\(minutes) min")
          .font(.system(size: bigSize, weight: .semibold).leading(.tight))
          .monospacedDigit()
          .tracking(-bigSize * 0.02)
          .contentTransition(.numericText(value: Double(minutes)))
          .animation(reduceMotion ? nil : .easeOut(duration: 0.8), value: minutes)
          .accessibilityLabel(entry.seconds < 60 ? "mais \(minutes) segundos" : "mais \(minutes) minutos")
        if streakRose {
          VStack(spacing: 8) {
            flame
            Text("\(streakShown)")
              .font(.system(size: 40, weight: .semibold))
              .monospacedDigit()
              .contentTransition(.numericText())
              .animation(reduceMotion ? nil : Motion.grow, value: streakShown)
            Text("dias seguidos")
              .font(.subheadline)
              .foregroundStyle(Color.studyCream50)
          }
          .accessibilityElement(children: .combine)
          .background { if !reduceMotion { FocoBurst(colors: burstColors, fire: celebrate) } }
        }
        if result.goalJustReached {
          StudyPill(tone: .cream, systemImage: "checkmark", text: "meta do dia batida")
        }
      } else {
        Text("curta demais, não contou")
          .font(.title3)
          .foregroundStyle(Color.studyCream50)
      }
      Spacer(minLength: 0)
      Button("fechar", action: close)
        .buttonStyle(.glass)
        .controlSize(.large)
        .font(.headline)
        .padding(.bottom, 32)
    }
    .padding(.horizontal, 24)
    .sensoryFeedback(.success, trigger: celebrate) { _, fired in fired && party }
    .task {
      guard let entry = result.entry else { return }
      try? await Task.sleep(for: .milliseconds(150))
      minutes = entry.seconds < 60 ? Int(entry.seconds) : Int(entry.seconds / 60)
      celebrate = true
      try? await Task.sleep(for: .milliseconds(400))
      streakShown = result.streakAfter.current
    }
  }

  private var burstColors: [Color] {
    [Color(hexString: track?.color), .studyCoral, .studyMarigold]
  }

  private var flame: some View {
    Image(systemName: "flame.fill")
      .font(.system(size: 64))
      .foregroundStyle(Color.studyCoral)
      .keyframeAnimator(
        initialValue: FlamePose(scale: reduceMotion ? 1 : 0.3, rotation: 0), trigger: celebrate
      ) { view, pose in
        view.scaleEffect(pose.scale).rotationEffect(.degrees(pose.rotation))
      } keyframes: { _ in
        KeyframeTrack(\.scale) {
          SpringKeyframe(reduceMotion ? 1 : 1.2, duration: 0.3)
          SpringKeyframe(1, duration: 0.3)
        }
        KeyframeTrack(\.rotation) {
          CubicKeyframe(reduceMotion ? 0 : -8, duration: 0.15)
          CubicKeyframe(reduceMotion ? 0 : 8, duration: 0.2)
          CubicKeyframe(0, duration: 0.25)
        }
      }
      .accessibilityHidden(true)
  }
}

private struct FlamePose {
  var scale: Double
  var rotation: Double
}

/// Catorze pontinhos que saem do centro e somem. O raio de cada um é fixo pelo
/// índice para a explosão ser a mesma toda vez que a tela abre.
private struct FocoBurst: View {
  let colors: [Color]
  let fire: Bool

  private let count = 14

  var body: some View {
    ZStack {
      ForEach(0..<count, id: \.self) { index in
        let angle = Double(index) / Double(count) * 2 * .pi
        let radius = 90.0 + Double((index * 37) % 50)
        Circle()
          .fill(colors[index % colors.count])
          .frame(width: 8, height: 8)
          .keyframeAnimator(initialValue: 0.0, trigger: fire) { view, progress in
            view
              .offset(x: cos(angle) * radius * progress, y: sin(angle) * radius * progress)
              .opacity(fire ? 1 - progress : 0)
              .scaleEffect(1 - 0.5 * progress)
          } keyframes: { _ in
            CubicKeyframe(1, duration: 0.9)
          }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
