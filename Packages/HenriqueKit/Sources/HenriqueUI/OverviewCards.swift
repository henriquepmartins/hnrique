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
    VStack(alignment: .leading, spacing: 4) {
      Text("volume desta semana").font(.caption.weight(.medium)).foregroundStyle(accent.base)
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(volume.weekKg.formatted(.number.precision(.fractionLength(0))))
          .font(.system(size: 42, weight: .semibold)).monospacedDigit().tracking(-1.8)
        Text("kg").font(.callout.weight(.medium)).foregroundStyle(Color.mutedInk)
      }
      Text(subtitle).font(.footnote).monospacedDigit().foregroundStyle(Color.mutedInk)
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
