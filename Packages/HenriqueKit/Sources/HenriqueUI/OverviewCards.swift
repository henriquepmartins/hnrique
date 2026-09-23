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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let workout: WorkoutSummary?
  /// Nulo quando o servidor ainda não troca dia: sem menu, em vez de um menu que falha.
  let choices: DaySwapChoices?
  let onWorkout: () -> Void
  let onSwap: @MainActor (String?) async -> Bool
  @State private var swaps = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(kicker).font(.caption.weight(.medium)).foregroundStyle(accent.deep)
      ZStack(alignment: .topLeading) {
        DayCardTitle(workout: workout)
          .id(workout?.id)
          .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("hoje.treino")
      .accessibilityActions {
        ForEach(choices?.all ?? []) { option in
          Button(option.title) { choose(option) }
        }
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
    .contentShape(.contextMenuPreview, .rect(cornerRadius: Radius.card))
    .contextMenu {
      if let choices {
        DaySwapMenu(choices: choices, choose: choose)
      }
    }
    .animation(
      reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.15),
      value: workout?.id)
    .sensoryFeedback(.selection, trigger: swaps)
  }

  private func choose(_ option: DaySwapChoices.Option) {
    Task {
      if await onSwap(option.workoutId) { swaps += 1 }
    }
  }

  private var percent: Int { workout?.completionPercent ?? 0 }

  private var kicker: String {
    let state: String
    if workout == nil {
      state = "hoje é descanso"
    } else if percent >= 100 {
      state = "treino de hoje, concluído"
    } else {
      state = percent > 0 ? "treino em andamento" : "treino de hoje"
    }
    guard let replaced = choices?.replaced else { return state }
    return "\(state) · \(replaced)"
  }

  private var action: String {
    guard workout != nil else { return "ver o plano" }
    if percent >= 100 { return "ver o treino" }
    return percent > 0 ? "continuar" : "começar"
  }
}

/// Nome, foco e contagens do treino do dia. É o bloco que troca inteiro quando o
/// dia troca de treino.
private struct DayCardTitle: View {
  @Environment(\.accent) private var accent
  let workout: WorkoutSummary?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(workout?.name.lowercased() ?? "corpo em recuperação")
        .font(.system(size: 34, weight: .medium)).tracking(-1.5)
        .fixedSize(horizontal: false, vertical: true)
      Text(workout?.focus ?? "sem treino programado. mobilidade e uma caminhada já contam.")
        .font(.subheadline).foregroundStyle(workout == nil ? Color.mutedInk : accent.deep)
      if let workout {
        Text("\(workout.exerciseCount) exercícios · \(workout.workSetCount) séries · \(workout.estimatedMinutes) min")
          .font(.footnote).monospacedDigit().foregroundStyle(Color.mutedInk)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// O que o menu do card de hoje oferece: primeiro o que ficou para trás na semana,
/// depois o resto do plano, e a volta ao plano quando o dia já está trocado.
struct DaySwapChoices: Equatable {
  struct Option: Identifiable, Equatable {
    let title: String
    /// Nulo volta o dia para o plano.
    let workoutId: String?

    var id: String { workoutId ?? "plano" }
  }

  let missed: [Option]
  let others: [Option]
  let revert: Option?
  /// "no lugar de pernas" quando o dia está trocado.
  let replaced: String?

  var all: [Option] { missed + others + (revert.map { [$0] } ?? []) }

  init?(_ dashboard: Dashboard) {
    guard dashboard.daySwaps != nil else { return nil }
    let schedule = dashboard.schedule
    let current = dashboard.workout?.id
    let late = schedule
      .missedWorkouts(today: dashboard.date, sessions: dashboard.weeklyWorkoutSessions ?? [])
      .filter { $0.id != current }
    missed = late.map {
      Option(
        title: "\($0.workout.name.lowercased()) · faltou \(planWeekdays[$0.lastMissed.weekday()])",
        workoutId: $0.id)
    }
    let listed = Set(late.map(\.id) + [current].compactMap { $0 })
    others = dashboard.weekPlan.filter { !listed.contains($0.id) }
      .map { Option(title: $0.name.lowercased(), workoutId: $0.id) }
    if schedule.isSwapped(dashboard.date) {
      revert = Option(title: "voltar ao plano", workoutId: nil)
      replaced = schedule.weekdayWorkout(on: dashboard.date)
        .map { "no lugar de \($0.name.lowercased())" } ?? "no lugar do descanso"
    } else {
      revert = nil
      replaced = nil
    }
  }
}

private struct DaySwapMenu: View {
  let choices: DaySwapChoices
  let choose: (DaySwapChoices.Option) -> Void

  var body: some View {
    if !choices.missed.isEmpty {
      Section("ficou para trás") {
        ForEach(choices.missed) { option in
          Button(option.title, systemImage: "clock.arrow.circlepath") { choose(option) }
        }
      }
    }
    if !choices.others.isEmpty {
      Section("treinar outro hoje") {
        ForEach(choices.others) { option in
          Button(option.title) { choose(option) }
        }
      }
    }
    if let revert = choices.revert {
      Section {
        Button(revert.title, systemImage: "arrow.uturn.backward") { choose(revert) }
      }
    }
  }
}
