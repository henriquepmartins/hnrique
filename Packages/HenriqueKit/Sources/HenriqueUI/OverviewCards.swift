import HenriqueCore
import SwiftUI

/// Abre a tela com a hora do dia, para o app dizer algo antes de pedir alguma coisa.
/// A sequência fica de fora porque o contador do topo já a mostra, e repetida ela
/// gasta a linha maior da tela dizendo o que já estava dito.
struct GreetingHeader: View {
  @Environment(\.accent) private var accent
  let date: CalendarDate

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(dateLabel).font(.caption.weight(.medium)).foregroundStyle(accent.base)
      Text(greeting)
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
