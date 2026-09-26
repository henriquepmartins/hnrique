import HenriqueCore
import SwiftUI

/// O laranja da chama não é o acento do app. A sequência é a mesma coisa em
/// qualquer cor escolhida, então ela pega a primeira vaga da paleta de treino e
/// fica com ela.
private let streakTone = WorkoutTone.all[0]

/// O dia em que a sequência zera se ninguém treinar até lá. O servidor corta a
/// sequência com mais de 5 dias entre dois treinos, então é o último treino mais
/// 6. Nulo com treino hoje ou com a sequência já zerada.
func streakResetDay(lastAttended: CalendarDate?, today: CalendarDate) -> CalendarDate? {
  guard let last = lastAttended, last < today else { return nil }
  let reset = last.adding(days: 6)
  return reset > today ? reset : nil
}

let streakGradient = LinearGradient(
  colors: [streakTone.top, streakTone.bottom], startPoint: .top, endPoint: .bottom)

// MARK: - O contador do topo

/// Chama e número lado a lado, aceso quando hoje já teve série valendo. Fica em
/// toda tela da academia, então só o que muda anima: o número quando sobe e a
/// cor quando acende.
struct StreakCounter: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var rises = 0
  let count: Int
  let isLit: Bool
  /// A chama some enquanto a insígnia está aberta: a chama dela é esta, voando.
  var stage: InsigniaStage?
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        Image(systemName: "flame.fill")
          .foregroundStyle(Color.mutedInk)
          .overlay {
            Image(systemName: "flame.fill")
              .foregroundStyle(streakGradient)
              .opacity(isLit ? 1 : 0)
          }
          .symbolEffect(.bounce, value: rises)
          .opacity(stage?.show == nil ? 1 : 0)
          .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            stage?.flameFrame = $0
          }
        Text("\(count)")
          .foregroundStyle(isLit ? Color.ink : Color.mutedInk)
          .contentTransition(reduceMotion ? .identity : .numericText(value: Double(count)))
      }
      .font(.headline.weight(.bold))
      .fontDesign(.rounded)
      .monospacedDigit()
      .animation(.smooth(duration: 0.2), value: isLit)
      .animation(.snappy(duration: 0.25), value: count)
      .frame(minWidth: 44, minHeight: 44)
      .contentShape(.rect)
    }
    .buttonStyle(StudyPressStyle())
    .onChange(of: count) { old, new in
      if new > old, !reduceMotion { rises += 1 }
    }
    .accessibilityLabel("sequência")
    .accessibilityValue("\(count) treinos")
  }
}

// MARK: - A tela cheia

struct StreakScreen: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// A frequência da semana já veio. Antes disso, sem `weekAttendance`, a
  /// conta cai em `sessionDates`, que só tem treino completo.
  @State private var weekLoaded = false
  @State private var weekChecked = false
  @Environment(\.dismiss) private var dismiss
  @State private var entered = false
  @State private var celebrating = false
  let dashboard: Dashboard

  private var today: CalendarDate { .today }

  private var streak: WorkoutStreak {
    WorkoutStreak(dashboard: dashboard, today: today, fallback: weekLoaded ? store.attendance : nil)
  }

  /// Sem nenhuma fonte de presença nenhum dia sairia feito, e a fita desenharia
  /// uma semana perdida que talvez nunca tenha existido. Some sem aviso.
  private var hasWeek: Bool {
    dashboard.weekAttendance != nil || weekLoaded || dashboard.sessionDates != nil
  }

  private func resetDay(_ streak: WorkoutStreak) -> CalendarDate? {
    guard !streak.isTodayDone else { return nil }
    let last = store.attendance.values.filter { $0.workSets > 0 && $0.date < today }.map(\.date).max()
    return streakResetDay(lastAttended: last, today: today)
  }

  var body: some View {
    let streak = streak
    NavigationStack {
      ScrollView {
        VStack(spacing: Space.xxl) {
          StreakRing(streak: streak, entered: entered, celebrating: celebrating)
          if hasWeek {
            StreakRibbon(days: streak.days, today: today, entered: entered)
          }
          if let tenure = store.tenure, let tier = tenure.tier {
            InsigniaRow(tier: tier, months: tenure.months)
          }
          Text("\(streak.weeklyCompleted)/\(streak.weeklyPlanned) na semana")
            .font(.subheadline).monospacedDigit().foregroundStyle(Color.mutedInk)
            .opacity(weekChecked || dashboard.weekAttendance != nil ? 1 : 0)
            .animation(.smooth(duration: 0.2), value: weekChecked)
          if let reset = resetDay(streak) {
            Text("zera \(dayLabel(reset))")
              .font(.subheadline).foregroundStyle(Color.mutedInk)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(Space.xl)
              .paperCard()
              .accessibilityLabel(
                "sem treino até \(dayLabel(reset.adding(days: -1))), a sequência zera \(dayLabel(reset))")
          }
        }
        .padding(Space.l)
        .padding(.top, Space.s)
        .padding(.bottom, Space.page)
        .frame(maxWidth: .infinity)
      }
      .background(Color.canvas.ignoresSafeArea())
      .navigationTitle("sequência")
      .toolbarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("fechar", systemImage: "xmark") { dismiss() }
            .labelStyle(.iconOnly)
            .accessibilityLabel("fechar")
        }
      }
    }
    .presentationDragIndicator(.visible)
    .task {
      // Seis dias para trás alcançam o último treino que ainda segura a
      // sequência, mesmo quando ele foi na semana anterior.
      let from = min(today.trainingWeekStart(), today.adding(days: -6))
      weekLoaded = await store.loadAttendance(from: from, to: today)
      weekChecked = true
    }
    .task {
      try? await Task.sleep(for: .seconds(Entrance.sheet))
      entered = true
      guard !reduceMotion else { return }
      try? await Task.sleep(for: .seconds(Entrance.sparkle))
      celebrating = true
    }
  }

  private func dayLabel(_ day: CalendarDate) -> String {
    if day == today { return "hoje" }
    if day == today.adding(days: 1) { return "amanhã" }
    return planWeekdays[day.weekday()]
  }
}

// MARK: - A insígnia

private struct InsigniaRow: View {
  let tier: StreakTier
  let months: Int

  var body: some View {
    HStack(spacing: Space.l) {
      InsigniaBadge(tier: tier, size: 56)
      VStack(alignment: .leading, spacing: 2) {
        Text(tier.name).font(.title3.weight(.bold)).fontDesign(.rounded)
        Text(tier.monthsLabel(months)).font(.subheadline).foregroundStyle(Color.mutedInk)
      }
      Spacer(minLength: 0)
    }
    .padding(Space.l)
    .paperCard()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("insígnia \(tier.name), \(tier.monthsLabel(months))")
  }
}

// MARK: - A entrada

/// Quando cada peça entra, contado do momento em que a folha pousa.
///
/// A espera do começo não é enfeite. Enquanto a folha sobe, o SwiftUI corta
/// qualquer animação que esteja rodando dentro dela: filmando o simulador a 60
/// quadros, o anel crescia até 91% e no quadro seguinte estava em 100%, um
/// salto que se vê. A folha leva 0,47 s para subir e parar, então a entrada
/// espera meio segundo e só aí começa, com a folha imóvel.
private enum Entrance {
  static let sheet = 0.5
  static let ring = 0.0
  static let count = 0.08
  static let badge = 0.16
  static let ribbon = 0.24
  static let ribbonStep = 0.035
  static let sparkle = 0.2
}

// MARK: - O anel

private struct StreakRing: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let streak: WorkoutStreak
  let entered: Bool
  let celebrating: Bool

  private let diameter: CGFloat = 216
  private let line: CGFloat = 18
  private let badge: CGFloat = 54

  var body: some View {
    ZStack {
      Circle().stroke(streakTone.bottom.opacity(0.32), lineWidth: line)
      Circle()
        .trim(from: 0, to: streak.weekProgress)
        // Degradê reto e não angular: o angular emenda a última cor na primeira
        // bem no ponto onde o traço começa, e a ponta arredondada mostra o corte.
        .stroke(
          LinearGradient(
            colors: [streakTone.top, streakTone.bottom],
            startPoint: .topTrailing, endPoint: .bottomLeading),
          style: StrokeStyle(lineWidth: line, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
      StreakCount(attendance: streak.attendance, complete: streak.complete, entered: entered)
    }
    .frame(width: diameter, height: diameter)
    // Âncora no centro e só escala: o anel nasce do lugar onde vai ficar, sem
    // um pixel de deslocamento lateral.
    .scaleEffect(grown ? 1 : 0.82, anchor: .center)
    .opacity(grown ? 1 : 0)
    .animation(growth(duration: 0.55, bounce: 0.16, delay: Entrance.ring), value: entered)
    .overlay {
      if !reduceMotion { StreakSparkle(radius: diameter / 2, trigger: celebrating) }
    }
    .overlay(alignment: .bottom) {
      FlameBadge(size: badge)
        .scaleEffect(grown ? 1 : 0.72)
        .opacity(grown ? 1 : 0)
        .animation(growth(duration: 0.4, bounce: 0.24, delay: Entrance.badge), value: entered)
        .offset(y: badge / 2)
    }
    .padding(.bottom, badge / 2)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(streak.attendance.count) treinos, \(streak.complete.count) completos")
  }

  private var grown: Bool { entered || reduceMotion }

  private func growth(duration: Double, bounce: Double, delay: Double) -> Animation? {
    reduceMotion ? nil : .spring(duration: duration, bounce: bounce).delay(delay)
  }
}

/// O número entra um pouco depois do anel para a leitura não competir com o
/// crescimento. Com `reduceMotion` tudo já nasce no lugar.
private struct StreakCount: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let attendance: StreakFigure
  let complete: StreakFigure
  let entered: Bool

  var body: some View {
    label
      .scaleEffect(shown ? 1 : 0.88)
      .opacity(shown ? 1 : 0)
      .animation(
        reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.12).delay(Entrance.count),
        value: entered)
  }

  private var shown: Bool { entered || reduceMotion }

  private var label: some View {
    VStack(spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 2) {
        Text("\(attendance.count)")
          .font(.system(size: 66, weight: .medium))
          .contentTransition(.numericText())
        if let target = attendance.target {
          Text("/\(target)").font(.title3).foregroundStyle(Color.mutedInk)
        }
      }
      .monospacedDigit()
      Text("treinos").font(.caption).foregroundStyle(Color.mutedInk)
      Label {
        Text(complete.target.map { "\(complete.count)/\($0) completos" } ?? "\(complete.count) completos")
      } icon: {
        Image(systemName: "checkmark.seal.fill")
      }
      .font(.caption.weight(.medium)).monospacedDigit()
      .foregroundStyle(streakTone.ink)
      .padding(.top, 4)
    }
  }
}

// MARK: - A chama

struct FlameBadge: View {
  let size: CGFloat

  var body: some View {
    Circle()
      .fill(streakGradient)
      .frame(width: size, height: size)
      .overlay {
        Image(systemName: "flame.fill")
          .font(.system(size: size * 0.46, weight: .semibold))
          .foregroundStyle(.white)
      }
      .overlay { Circle().strokeBorder(Color.canvas, lineWidth: 3) }
  }
}

// MARK: - As bolinhas

/// Bolinhas em volta do anel. Cada uma dá um estalo e some logo depois, fora de
/// ordem, para virar uma pipoca e não uma varredura. Roda uma vez por abertura
/// da folha, que é uma tela que se abre de vez em quando, então a festa não
/// cansa.
///
/// Fica montada desde o começo e espera o gatilho. O `KeyframeAnimator` só anda
/// quando o gatilho muda com ele já na tela; montado junto com o valor novo,
/// ele fica parado no primeiro quadro para sempre.
private struct StreakSparkle: View {
  let radius: CGFloat
  let trigger: Bool

  var body: some View {
    ZStack {
      ForEach(SparkDot.all) { dot in
        Circle()
          .fill(dot.color)
          .frame(width: dot.size, height: dot.size)
          .modifier(Pop(delay: dot.delay, trigger: trigger))
          .offset(
            x: cos(dot.angle) * (radius + dot.lift),
            y: sin(dot.angle) * (radius + dot.lift))
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

/// Nasce pequena, passa do tamanho e recolhe apagando. O estalo é o passo de
/// mais: sem ele a bolinha só acende, e acender não é comemorar.
private struct Pop: ViewModifier {
  let delay: Double
  let trigger: Bool

  func body(content: Content) -> some View {
    KeyframeAnimator(initialValue: PopPose(), trigger: trigger) { pose in
      content.scaleEffect(pose.scale).opacity(pose.opacity)
    } keyframes: { _ in
      KeyframeTrack(\.scale) {
        LinearKeyframe(0.3, duration: delay)
        SpringKeyframe(1.15, duration: 0.17, spring: .bouncy)
        SpringKeyframe(0.8, duration: 0.31)
      }
      KeyframeTrack(\.opacity) {
        LinearKeyframe(0, duration: delay)
        LinearKeyframe(1, duration: 0.09)
        LinearKeyframe(1, duration: 0.11)
        LinearKeyframe(0, duration: 0.28)
      }
    }
  }
}

private struct PopPose {
  var scale: Double = 0.3
  var opacity: Double = 0
}

private struct SparkDot: Identifiable {
  let id: Int
  let angle: Double
  let lift: CGFloat
  let size: CGFloat
  let delay: Double
  let color: Color

  /// Sorteadas uma vez, com semente fixa. Sorteadas a cada desenho, a mesma
  /// bolinha saltaria para outro ponto do anel em cada quadro.
  static let all: [SparkDot] = {
    var rng = SeededRandom(seed: 0x5EED_1F0)
    let count = 16
    // O vão de baixo é da chama. Bolinha ali sai por trás do disco e some.
    let gap = 52.0
    let order = Array(0..<count).shuffled(using: &rng)
    return (0..<count).map { index in
      let sweep = 360 - gap
      let degrees = 90 + gap / 2 + sweep * Double(index) / Double(count - 1)
      return SparkDot(
        id: index,
        angle: (degrees + .random(in: -4...4, using: &rng)) * .pi / 180,
        lift: .random(in: 7...17, using: &rng),
        size: .random(in: 5...9, using: &rng),
        delay: 0.001 + 0.026 * Double(order[index]),
        color: colors[index % colors.count])
    }
  }()

  /// Laranja, amarelo e vermelho, as três cores de uma chama.
  private static let colors: [Color] = [
    streakTone.top, Color(hex: 0xfa_cc15), Color(hex: 0xef_4444),
  ]
}

/// splitmix64. Precisa ser igual em toda execução, não precisa ser bom em
/// estatística.
private struct SeededRandom: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

// MARK: - A fita dos sete dias

private struct StreakRibbon: View {
  @Environment(\.accent) private var accent
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let days: [StreakDay]
  let today: CalendarDate
  let entered: Bool

  var body: some View {
    HStack(spacing: 6) {
      ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
        VStack(spacing: 6) {
          // A inicial sozinha não serve em português, sexta, sábado e segunda
          // começam todas com s.
          Text(day.date.date(), format: .dateTime.weekday(.abbreviated))
            .font(.caption2).foregroundStyle(Color.mutedInk)
            .textCase(.lowercase)
          DayMarker(
            day: day, isToday: day.date == today, size: 32, accent: accent)
        }
        .frame(maxWidth: .infinity)
        .scaleEffect(shown ? 1 : 0.7)
        .opacity(shown ? 1 : 0)
        .animation(cascade(index), value: entered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          Text(
            "\(day.date.date(), format: .dateTime.weekday(.wide)), \(day.state.spokenLabel)"))
      }
    }
  }

  private var shown: Bool { entered || reduceMotion }

  private func cascade(_ index: Int) -> Animation? {
    guard !reduceMotion else { return nil }
    return .spring(duration: 0.38, bounce: 0.18)
      .delay(Entrance.ribbon + Entrance.ribbonStep * Double(index))
  }
}

private struct DayMarker: View {
  let day: StreakDay
  let isToday: Bool
  let size: CGFloat
  let accent: Accent

  var body: some View {
    ZStack {
      if isToday {
        Circle()
          .strokeBorder(accent.base.opacity(0.5), lineWidth: 1.5)
          .frame(width: size + 9, height: size + 9)
      }
      mark.frame(width: size, height: size)
    }
    .frame(width: size + 10, height: size + 10)
  }

  @ViewBuilder
  private var mark: some View {
    switch day.state {
    case .done:
      Circle().fill(streakTone.top)
        .overlay {
          Image(systemName: "checkmark")
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(.white)
            .offset(y: -0.5)
        }
    case .missed:
      Circle().strokeBorder(Color.ink.opacity(0.16), lineWidth: 1.5)
    case .rest:
      Circle().fill(Color.ink.opacity(0.16))
        .frame(width: size * 0.28, height: size * 0.28)
    case .planned:
      Circle().strokeBorder(accent.base, lineWidth: 2)
    case .open:
      Circle().fill(Color.ink.opacity(0.08))
        .frame(width: size * 0.28, height: size * 0.28)
    }
  }
}

extension StreakDayState {
  var spokenLabel: String {
    switch self {
    case .done: "treino feito"
    case .missed: "treino perdido"
    case .rest: "folga"
    case .planned: "treino planejado"
    case .open: "dia livre"
    }
  }
}
