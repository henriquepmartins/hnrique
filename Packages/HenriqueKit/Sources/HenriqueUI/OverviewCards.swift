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

/// O treino do dia na home, um cartão por momento do dia. Antes ele chama para
/// começar, durante conta as séries, depois vira o resumo do que saiu e no
/// descanso aponta o próximo treino.
struct DayCard: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.accent) private var accent
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let workout: WorkoutSummary?
  let moment: HomeMoment
  /// O próximo dia com treino no plano, que o cartão de descanso aponta.
  let next: PlannedDay?
  /// Nulo quando o servidor ainda não troca dia: sem menu, em vez de um menu que falha.
  let choices: DaySwapChoices?
  let onWorkout: () -> Void
  let onPlan: () -> Void
  let onSwap: @MainActor (String?) async -> Bool
  @State private var swaps = 0
  @State private var showingRecap = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      kicker
      if let rest = store.rest, rest.key.date == store.selectedDate {
        RestChip(rest: rest, onOpen: onWorkout)
      }
      SyncStatusLine()
      HStack(alignment: .top, spacing: Space.s) {
        ZStack(alignment: .topLeading) {
          DayCardTitle(
            workout: workout, moment: moment, next: next,
            tone: workout.flatMap { store.dashboard?.tone(forWorkout: $0.id) },
            recap: recap)
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
        // O toque longo no cartão continua, mas sozinho ninguém o descobre.
        if let choices, !choices.all.isEmpty {
          Menu {
            DaySwapMenu(choices: choices, choose: choose)
          } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(accent.deep)
              .frame(width: 32, height: 32)
              .glassEffect(.regular.interactive(), in: .circle)
              .frame(width: 44, height: 44)
              .contentShape(.rect)
          }
          .accessibilityLabel("trocar o treino do dia")
        }
      }
      if moment == .during, let workout {
        ProgressView(value: Double(workout.completionPercent) / 100)
          .tint(accent.deep)
          .animation(Motion.resolve(Motion.glide, reduceMotion), value: workout.completionPercent)
          .accessibilityHidden(true)
      }
      actions.padding(.top, 6)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Space.xl)
    .background(background, in: .rect(cornerRadius: Radius.card))
    .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(accent.deep.opacity(0.12)))
    .contentShape(.contextMenuPreview, .rect(cornerRadius: Radius.card))
    .contextMenu {
      if let choices, !choices.all.isEmpty {
        DaySwapMenu(choices: choices, choose: choose)
      }
    }
    .animation(Motion.resolve(Motion.confirm, reduceMotion), value: workout?.id)
    .animation(Motion.resolve(Motion.confirm, reduceMotion), value: moment)
    .sensoryFeedback(.selection, trigger: swaps)
    .sheet(isPresented: $showingRecap) {
      if let recap { WorkoutRecapSheet(recap: recap) }
    }
  }

  private func choose(_ option: DaySwapChoices.Option) {
    Task {
      if await onSwap(option.workoutId) { swaps += 1 }
    }
  }

  /// O lima é o chamado para treinar. Feito o treino, o cartão vira papel e
  /// deixa a semana e os recordes falarem mais alto.
  private var background: AnyShapeStyle {
    switch moment {
    case .before, .during: AnyShapeStyle(accent.acid)
    case .rest, .after: AnyShapeStyle(Color.white)
    }
  }

  /// Só aparece quando o dia foge do comum. Treino por começar e descanso já
  /// se dizem pelo título.
  @ViewBuilder
  private var kicker: some View {
    let replaced = choices?.replaced
    switch moment {
    case .after:
      Label {
        Text([isComplete ? "feito" : "encerrado", replaced].compactMap { $0 }.joined(separator: " · "))
      } icon: {
        Image(systemName: "checkmark.circle.fill")
      }
      .font(.caption.weight(.medium)).foregroundStyle(accent.deep)
    case .during:
      Text(["em andamento", replaced].compactMap { $0 }.joined(separator: " · "))
        .font(.caption.weight(.medium)).foregroundStyle(accent.deep)
    case .before, .rest:
      if let replaced {
        Text(replaced).font(.caption.weight(.medium)).foregroundStyle(accent.deep)
      }
    }
  }

  private var isComplete: Bool { (workout?.completionPercent ?? 0) >= 100 }

  /// O resumo da sessão encerrada, o mesmo da folha de "encerrar".
  private var recap: WorkoutRecap? {
    guard moment == .after, let workout, let data = store.dashboard else { return nil }
    let date = store.selectedDate
    let timing = WorkoutSessionTiming(
      workout, anchor: store.startedAt(workout.id, on: date),
      finishedAt: store.finishedAt(workout.id, on: date))
    return WorkoutRecap(workout, timing: timing, records: data.records ?? [], on: date)
  }

  @ViewBuilder
  private var actions: some View {
    switch moment {
    case .rest:
      Button("ver o plano", systemImage: "list.clipboard", action: onPlan)
        .buttonStyle(.glassProminent).tint(accent.deep).foregroundStyle(.white).controlSize(.large)
        .accessibilityIdentifier("hoje.abrir")
    case .before, .during:
      Button(moment == .during ? "continuar" : "começar", systemImage: "play.fill", action: onWorkout)
        .buttonStyle(.glassProminent).tint(accent.deep).foregroundStyle(.white).controlSize(.large)
        .accessibilityIdentifier("hoje.abrir")
    case .after:
      HStack(spacing: Space.s) {
        Button("ver o treino", systemImage: "eye", action: onWorkout)
          .accessibilityIdentifier("hoje.abrir")
        if recap != nil {
          Button("resumo", systemImage: "list.bullet.rectangle") { showingRecap = true }
            .accessibilityIdentifier("hoje.resumo")
        }
      }
      .buttonStyle(.glass).controlSize(.regular)
      .foregroundStyle(accent.deep)
    }
  }
}

/// Nome, foco e contagens do treino do dia. É o bloco que troca inteiro quando o
/// dia troca de treino.
private struct DayCardTitle: View {
  @Environment(\.accent) private var accent
  @ScaledMetric(relativeTo: .largeTitle) private var nameSize = 34.0
  let workout: WorkoutSummary?
  let moment: HomeMoment
  let next: PlannedDay?
  /// A cor do treino no plano, a mesma da pasta e dos próximos dias.
  let tone: WorkoutTone?
  let recap: WorkoutRecap?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        if let tone {
          Circle().fill(tone.top).frame(width: 12, height: 12)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            .accessibilityHidden(true)
        }
        // Depois do treino o nome desce de tamanho: o cartão é resumo, não chamado.
        let size = moment == .after ? nameSize * 0.7 : nameSize
        Text(workout?.name.lowercased() ?? "descanso")
          .font(.system(size: size, weight: .medium)).tracking(size * -0.044)
          .lineLimit(2).truncationMode(.tail)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let workout {
        if !workout.focus.isEmpty, moment != .after {
          Text(workout.focus.lowercased()).font(.subheadline).foregroundStyle(accent.deep)
            // O foco é o detalhe; acima disso ele ficava maior que o nome.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        Text(counts(workout))
          .font(.footnote).monospacedDigit().foregroundStyle(Color.mutedInk)
          .accessibilityLabel(spokenCounts(workout))
      } else if let next, let item = next.workout {
        Label("\(item.name.lowercased()) · \(when(next.date))", systemImage: "arrow.turn.down.right")
          .font(.subheadline).foregroundStyle(accent.deep)
          .accessibilityLabel("próximo treino, \(item.name.lowercased()), \(when(next.date))")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func when(_ date: CalendarDate) -> String {
    date == CalendarDate.today.adding(days: 1) ? "amanhã" : Formatting.weekday(date)
  }

  private func counts(_ workout: WorkoutSummary) -> String {
    let exercises = "\(workout.exerciseCount) exercícios"
    switch moment {
    case .rest, .before:
      return [exercises, "\(workout.workSetCount) séries",
        Formatting.duration(minutes: workout.estimatedMinutes)].joined(separator: " · ")
    case .during:
      return [exercises, "\(workout.completedWorkSetCount) de \(workout.workSetCount) séries"]
        .joined(separator: " · ")
    case .after:
      guard let recap else { return exercises }
      return [
        took(recap), "\(recap.doneSets) de \(recap.totalSets) séries",
        "\(Formatting.trim(recap.workVolumeKg.rounded())) kg",
      ].compactMap { $0 }.joined(separator: " · ")
    }
  }

  /// Menos de um minuto é série marcada depois do treino, não duração, e some.
  private func took(_ recap: WorkoutRecap) -> String? {
    guard let seconds = recap.durationSeconds, seconds >= 60 else { return nil }
    return Formatting.duration(seconds: TimeInterval(seconds))
  }

  private func spokenCounts(_ workout: WorkoutSummary) -> String {
    let exercises = "\(workout.exerciseCount) exercícios"
    switch moment {
    case .rest, .before:
      return "\(exercises), \(workout.workSetCount) séries, uns \(workout.estimatedMinutes) minutos"
    case .during:
      return "\(exercises), \(workout.completedWorkSetCount) de \(workout.workSetCount) séries feitas"
    case .after:
      guard let recap else { return exercises }
      return [
        took(recap).map { "durou \($0)" }, "\(recap.doneSets) de \(recap.totalSets) séries",
        "\(Formatting.trim(recap.workVolumeKg.rounded())) quilos de volume",
      ].compactMap { $0 }.joined(separator: ", ")
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
          Button(option.title, systemImage: "dumbbell") { choose(option) }
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

/// Título de seção, com o ícone no acento.
struct SectionHeading: View {
  @Environment(\.accent) private var accent
  let title: String
  let systemImage: String
  var font: Font = .title3.weight(.medium)
  var tracking: CGFloat = -0.6

  var body: some View {
    Label {
      Text(title).tracking(tracking)
    } icon: {
      Image(systemName: systemImage).foregroundStyle(accent.base)
    }
    .font(font)
    .accessibilityAddTraits(.isHeader)
  }
}
