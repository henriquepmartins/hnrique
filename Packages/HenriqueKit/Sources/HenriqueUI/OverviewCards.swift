import HenriqueCore
import SwiftUI

/// A data abre a tela. A sequência fica de fora porque o contador do topo já a
/// mostra.
struct DateHeader: View {
  let date: CalendarDate

  var body: some View {
    Text(label)
      .font(.title.weight(.medium)).tracking(-1.2)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityAddTraits(.isHeader)
  }

  private var label: String {
    date.date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "pt_BR")))
      .lowercased()
  }
}

/// O treino do dia na home, em quatro estados: programado, em andamento, feito e
/// descanso. O cartão anterior mostrava só o nome e uma seta, e dizia a mesma
/// coisa nos quatro.
struct DayCard: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.accent) private var accent
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let workout: WorkoutSummary?
  /// Nulo quando o servidor ainda não troca dia: sem menu, em vez de um menu que falha.
  let choices: DaySwapChoices?
  let onWorkout: () -> Void
  let onPlan: () -> Void
  let onSwap: @MainActor (String?) async -> Bool
  @State private var swaps = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let kicker {
        Text(kicker).font(.caption.weight(.medium)).foregroundStyle(accent.deep)
      }
      if let rest = store.rest, rest.key.date == store.selectedDate {
        RestChip(rest: rest, onOpen: onWorkout)
      }
      SyncStatusLine()
      ZStack(alignment: .topLeading) {
        DayCardTitle(
          workout: workout, tone: workout.flatMap { store.dashboard?.tone(forWorkout: $0.id) },
          time: time)
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
      Button(action, systemImage: actionSymbol) {
        if workout == nil {
          onPlan()
        } else {
          onWorkout()
        }
      }
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
      if let choices, !choices.all.isEmpty {
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

  /// Encerrado no "encerrar" da sessão, mesmo com série em aberto.
  private var isClosed: Bool {
    guard let workout else { return false }
    return percent >= 100 || store.finishedAt(workout.id, on: store.selectedDate) != nil
  }

  /// Só aparece quando o dia foge do comum. Treino por começar e descanso já
  /// se dizem pelo título.
  private var kicker: String? {
    let state: String? =
      if workout == nil { nil }
      else if percent >= 100 { "feito" }
      else if isClosed { "encerrado" }
      else if percent > 0 { "em andamento" }
      else { nil }
    let parts = [state, choices?.replaced].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  /// Aberto, o card mostra a estimativa; encerrado, o tempo que levou. Menos
  /// de um minuto é série marcada depois do treino, não duração, e some.
  private var time: DayCardTitle.Time {
    guard isClosed, let workout else { return .estimate }
    let date = store.selectedDate
    let elapsed = WorkoutSessionTiming(
      workout, anchor: store.startedAt(workout.id, on: date),
      finishedAt: store.finishedAt(workout.id, on: date)
    )?.elapsed(at: .now) ?? 0
    return elapsed >= 60 ? .took(elapsed) : .unknown
  }

  private var actionSymbol: String {
    guard workout != nil else { return "list.clipboard" }
    return isClosed ? "eye" : "play.fill"
  }

  private var action: String {
    guard workout != nil else { return "ver o plano" }
    if isClosed { return "ver o treino" }
    return percent > 0 ? "continuar" : "começar"
  }
}

/// Nome, foco e contagens do treino do dia. É o bloco que troca inteiro quando o
/// dia troca de treino.
private struct DayCardTitle: View {
  @Environment(\.accent) private var accent
  let workout: WorkoutSummary?
  /// A cor do treino no plano, a mesma da pasta e dos próximos dias.
  let tone: WorkoutTone?
  let time: Time

  enum Time {
    case estimate
    case took(TimeInterval)
    case unknown
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        if let tone {
          Circle().fill(tone.top).frame(width: 12, height: 12)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            .accessibilityHidden(true)
        }
        Text(workout?.name.lowercased() ?? "descanso")
          .font(.system(size: 34, weight: .medium)).tracking(-1.5)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let workout {
        if !workout.focus.isEmpty {
          Text(workout.focus).font(.subheadline).foregroundStyle(accent.deep)
        }
        Text(counts(workout))
          .font(.footnote).monospacedDigit().foregroundStyle(Color.mutedInk)
          .accessibilityLabel(spokenCounts(workout))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func counts(_ workout: WorkoutSummary) -> String {
    let parts = ["\(workout.exerciseCount) exercícios", "\(workout.workSetCount) séries"]
    switch time {
    case .estimate: return (parts + ["\(workout.estimatedMinutes) min"]).joined(separator: " · ")
    case .took(let seconds): return (parts + [HeroModel.clock(seconds)]).joined(separator: " · ")
    case .unknown: return parts.joined(separator: " · ")
    }
  }

  private func spokenCounts(_ workout: WorkoutSummary) -> String {
    let parts = ["\(workout.exerciseCount) exercícios", "\(workout.workSetCount) séries"]
    switch time {
    case .estimate:
      return (parts + ["uns \(workout.estimatedMinutes) minutos"]).joined(separator: ", ")
    case .took(let seconds):
      let spoken = Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes]))
      return (parts + ["durou \(spoken)"]).joined(separator: ", ")
    case .unknown: return parts.joined(separator: ", ")
    }
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

  /// Com série marcada no dia não há opção nenhuma: trocar ali deixaria as
  /// séries feitas num treino que não é mais o do dia. O "no lugar de" continua.
  init?(_ dashboard: Dashboard) {
    guard dashboard.daySwaps != nil else { return nil }
    let schedule = dashboard.schedule
    let locked = dashboard.hasMarkedSets
    let current = dashboard.workout?.id
    let late = dashboard.missedWorkouts(today: dashboard.date)
      .filter { $0.id != current }
    missed = locked ? [] : late.map {
      Option(
        title: "\($0.workout.name.lowercased()) · faltou \(planWeekdays[$0.lastMissed.weekday()])",
        workoutId: $0.id)
    }
    let listed = Set(late.map(\.id) + [current].compactMap { $0 })
    others = locked ? [] : dashboard.weekPlan.filter { !listed.contains($0.id) }
      .map { Option(title: $0.name.lowercased(), workoutId: $0.id) }
    if schedule.isSwapped(dashboard.date) {
      revert = locked ? nil : Option(title: "voltar ao plano", workoutId: nil)
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
