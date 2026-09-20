import HenriqueCore
import SwiftUI

/// Abre a tela com a hora do dia e a sequência, para o app dizer algo antes de
/// pedir alguma coisa.
struct GreetingHeader: View {
  @Environment(\.accent) private var accent
  let date: CalendarDate
  let streak: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(dateLabel).font(.caption.weight(.medium)).foregroundStyle(accent.base)
      Text(streak > 0 ? "\(greeting), \(streak) dias seguidos" : greeting)
        .font(.title.weight(.medium)).tracking(-1.2)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var greeting: String {
    switch Calendar.autoupdatingCurrent.component(.hour, from: .now) {
    case ..<12: "bom dia"
    case ..<18: "boa tarde"
    default: "boa noite"
    }
  }

  private var dateLabel: String {
    date.date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "pt_BR")))
      .lowercased()
  }
}

/// O volume da semana em quilos, com a variação sobre a semana anterior. Tonelada
/// cabia melhor no cartão, mas ninguém levanta pensando em "2,1 t".
struct WeeklyVolumeCard: View {
  @Environment(\.accent) private var accent
  let volume: VolumeSummary

  var body: some View {
    HStack(alignment: .bottom, spacing: Space.l) {
      VStack(alignment: .leading, spacing: 4) {
        Text("volume desta semana").font(.caption.weight(.medium)).foregroundStyle(accent.base)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(volume.weekKg.formatted(.number.precision(.fractionLength(0))))
            .font(.system(size: 42, weight: .semibold)).monospacedDigit().tracking(-1.8)
          Text("kg").font(.callout.weight(.medium)).foregroundStyle(Color.mutedInk)
        }
        Text(subtitle).font(.footnote).monospacedDigit().foregroundStyle(Color.mutedInk)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let points = volume.trendPoints {
        Sparkline(values: points)
          .stroke(accent.base, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
          .overlay(alignment: .topTrailing) {
            SparklineTip(values: points).fill(accent.base)
          }
          .frame(width: 92, height: 52)
          .accessibilityLabel("volume das últimas \(points.count) semanas")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Space.xl)
    .paperCard()
  }

  private var subtitle: String {
    let sessions = "\(volume.weekSessions) treinos registrados"
    guard let delta = volume.deltaPercent else { return sessions }
    return "\(sessions), \(delta >= 0 ? "+" : "")\(delta)% sobre a semana passada"
  }
}

/// O treino do dia na home, em quatro estados: programado, em andamento, feito e
/// descanso. O cartão anterior mostrava só o nome e uma seta, e dizia a mesma
/// coisa nos quatro.
struct DayCard: View {
  @Environment(\.accent) private var accent
  let workout: WorkoutSummary?
  let onWorkout: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(kicker).font(.caption.weight(.medium)).foregroundStyle(accent.deep)
      Text(workout?.name.lowercased() ?? "corpo em recuperação")
        .font(.system(size: 34, weight: .medium)).tracking(-1.5)
        .fixedSize(horizontal: false, vertical: true)
      Text(workout?.focus ?? "sem treino programado. mobilidade e uma caminhada já contam.")
        .font(.subheadline).foregroundStyle(workout == nil ? Color.mutedInk : accent.deep)
      if let workout {
        Text("\(workout.exerciseCount) exercícios · \(workout.workSetCount) séries · \(workout.estimatedMinutes) min")
          .font(.footnote).monospacedDigit().foregroundStyle(Color.mutedInk)
      }
      Button(action, systemImage: workout == nil ? "list.clipboard" : "play.fill", action: onWorkout)
        .buttonStyle(.glassProminent).tint(accent.deep).foregroundStyle(.white).controlSize(.large)
        .padding(.top, 6)
        .accessibilityIdentifier("hoje.abrir")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Space.xl)
    .background(workout == nil ? AnyShapeStyle(Color.white) : AnyShapeStyle(accent.acid),
      in: .rect(cornerRadius: Radius.card))
    .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(accent.deep.opacity(0.12)))
  }

  private var percent: Int { workout?.completionPercent ?? 0 }

  private var kicker: String {
    guard workout != nil else { return "hoje é descanso" }
    if percent >= 100 { return "treino de hoje, concluído" }
    return percent > 0 ? "treino em andamento" : "treino de hoje"
  }

  private var action: String {
    guard workout != nil else { return "ver o plano" }
    if percent >= 100 { return "ver o treino" }
    return percent > 0 ? "continuar" : "começar"
  }
}

/// A linha das últimas semanas. Desenhada à mão em vez de virar um gráfico do Charts
/// porque são seis pontos sem eixo, sem legenda e sem toque: o traço é o dado inteiro.
struct Sparkline: Shape {
  let values: [Double]

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let points = Sparkline.points(values, in: Sparkline.plot(rect))
    guard let first = points.first else { return path }
    path.move(to: first)
    path.addLines(Array(points.dropFirst()))
    return path
  }

  /// O mesmo recorte para a linha e para o ponto, senão um sai de cima do outro. A
  /// folga é o raio do ponto mais a espessura do traço.
  static func plot(_ rect: CGRect) -> CGRect { rect.insetBy(dx: 5, dy: 5) }

  /// O piso é zero, não o menor valor: uma semana fraca deve aparecer baixa, e não
  /// colada na base porque foi a pior de seis.
  static func points(_ values: [Double], in rect: CGRect) -> [CGPoint] {
    guard values.count > 1 else { return [] }
    let peak = max(values.max() ?? 0, 1)
    let step = rect.width / CGFloat(values.count - 1)
    return values.enumerated().map { index, value in
      CGPoint(
        x: rect.minX + CGFloat(index) * step,
        y: rect.maxY - rect.height * CGFloat(value / peak))
    }
  }
}

/// O ponto da semana corrente, onde a linha termina.
struct SparklineTip: Shape {
  let values: [Double]

  func path(in rect: CGRect) -> Path {
    guard let last = Sparkline.points(values, in: Sparkline.plot(rect)).last else { return Path() }
    return Path(ellipseIn: CGRect(x: last.x - 4, y: last.y - 4, width: 8, height: 8))
  }
}
