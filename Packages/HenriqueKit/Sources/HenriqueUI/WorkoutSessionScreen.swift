import HenriqueCore
import SwiftUI

/// Quanto do treino já foi. Derivado do painel a cada pintura, então a sessão e
/// a tela de hoje nunca mostram contagens diferentes.
struct SessionProgress: Equatable {
  let done: Int
  let total: Int

  init(_ workout: WorkoutSummary) {
    done = workout.completedWorkSetCount
    total = workout.workSetCount
  }

  var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
  var percent: Int { Int((fraction * 100).rounded()) }
}

/// O primeiro exercício com série valendo em aberto. Continuar um treino pela
/// metade deve cair onde ele parou, não no começo.
func firstOpenExercise(in workout: WorkoutSummary) -> Int {
  workout.exercises.firstIndex { !$0.isComplete } ?? max(0, workout.exercises.count - 1)
}

/// Modo treino: um exercício por vez, com a linha de série no tamanho de marcar
/// com o peso na mão. Lê e escreve o mesmo store da tela de hoje.
struct WorkoutSessionScreen: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.accent) private var accent
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var index = 0
  @State private var entered = false
  @State private var rest: RestState?
  @State private var restSeconds: [String: TimeInterval] = [:]

  private static let grow = Animation.spring(response: 0.46, dampingFraction: 0.66)
  private static let settle = Animation.spring(response: 0.34, dampingFraction: 0.74)
  private var grow: Animation? { reduceMotion ? nil : Self.grow }
  private var settle: Animation? { reduceMotion ? nil : Self.settle }

  var body: some View {
    ZStack {
      Color.canvas.ignoresSafeArea()
      if let data = store.dashboard, let workout = data.workout {
        let progress = SessionProgress(workout)
        let last = workout.exercises.count - 1
        VStack(spacing: 0) {
          top(workout: workout, progress: progress).springEntrance(index: 0, shown: entered)
          TabView(selection: $index) {
            ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { i, exercise in
              ScrollView {
                card(exercise: exercise, date: data.date, templateId: workout.id)
                  .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
              }
              .scrollBounceBehavior(.basedOnSize)
              .tag(i)
            }
          }
          #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
          #endif
          .springEntrance(index: 1, shown: entered)
          // A barra entra no fluxo, não por cima: sobreposta ela cobria a linha
          // da série seguinte, que é justamente o que o dedo procura depois.
          if let rest {
            RestTimerBar(rest: rest, onAdjust: adjustRest) { self.rest = nil }
              .padding(.horizontal, 16).padding(.bottom, Space.s)
              .transition(.move(edge: .bottom).combined(with: .opacity))
          }
          footer(last: last).springEntrance(index: 2, shown: entered)
        }
        .animation(grow, value: rest)
        .onChange(of: progress.done) { old, new in
          rest = new > old ? startRest(workout: workout) : nil
        }
        .onChange(of: index) { rest = nil }
        .task(id: rest?.endsAt) {
          guard let endsAt = rest?.endsAt else { return }
          try? await Task.sleep(for: .seconds(max(0, endsAt.timeIntervalSinceNow) + 6))
          guard !Task.isCancelled else { return }
          rest = nil
        }
        .onAppear {
          index = firstOpenExercise(in: workout)
          entered = true
        }
      }
    }
    .task { if store.dashboard?.workout == nil { dismiss() } }
  }

  private func top(workout: WorkoutSummary, progress: SessionProgress) -> some View {
    VStack(spacing: 12) {
      HStack {
        Button("fechar", systemImage: "chevron.down") { dismiss() }
          .labelStyle(.iconOnly).buttonStyle(.glass).controlSize(.large)
          .accessibilityIdentifier("sessao.fechar")
        Spacer()
        VStack(spacing: 1) {
          Text(workout.name.lowercased()).font(.headline.weight(.semibold))
          Text("exercício \(index + 1) de \(workout.exercises.count)")
            .font(.caption2).foregroundStyle(Color.mutedInk).monospacedDigit()
        }
        Spacer()
        // mesmo tamanho do botão de fechar, senão o título fica descentrado
        Button("fechar", systemImage: "chevron.down") {}
          .labelStyle(.iconOnly).buttonStyle(.glass).controlSize(.large).hidden()
      }
      VStack(spacing: 6) {
        HStack {
          Text("\(progress.done)").contentTransition(.numericText(value: Double(progress.done)))
          Text("de \(progress.total) séries")
          Spacer()
          Text("\(progress.percent)%")
        }
        .font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(Color.mutedInk)
        GeometryReader { geo in
          Capsule().fill(Color.ink.opacity(0.07))
            .overlay(alignment: .leading) {
              Capsule().fill(accent.signal)
                // Zero séries é barra vazia. A ponta mínima existe para uma
                // série feita não sumir, não para fingir progresso que não há.
                .frame(width: progress.done == 0 ? 0 : max(6, geo.size.width * progress.fraction))
            }
        }
        .frame(height: 8)
      }
      .animation(settle, value: progress.done)
      if let timing = WorkoutSessionTiming(workout) {
        WorkoutSessionClock(timing: timing)
      }
    }
    .padding(.horizontal, Space.l).padding(.top, Space.s).padding(.bottom, Space.m)
  }

  private func card(exercise: DashboardExercise, date: CalendarDate, templateId: String) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(exercise.muscleGroup.lowercased())
        .font(.caption2.weight(.medium)).foregroundStyle(accent.base)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(accent.base.opacity(0.12), in: .capsule)
      Text(exercise.name.lowercased())
        .font(.system(size: 34, weight: .medium)).tracking(-1.4)
        .fixedSize(horizontal: false, vertical: true)
      if let previous = exercise.previous {
        Text("última vez: \(previous.reps.map(String.init).joined(separator: ", ")) × \(weightLabel(previous.weightKg))")
          .font(.footnote).foregroundStyle(Color.mutedInk)
      }
      VStack(spacing: 8) {
        ForEach(exercise.sets.prep) { set in
          TrainingSetRow(key: SetKey(date: date, templateId: templateId, exerciseId: exercise.id, kind: .prep, index: set.index),
            weight: set.weightKg, repetitions: set.reps, done: set.isDone, failure: false, scale: .session)
        }
        ForEach(exercise.sets.work) { set in
          TrainingSetRow(key: SetKey(date: date, templateId: templateId, exerciseId: exercise.id, kind: .work, index: set.index),
            weight: set.weightKg, repetitions: set.reps, done: set.isDone, failure: set.toFailure, scale: .session)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Space.xl)
    // As linhas de série da sessão têm raio 20 a 20 de respiro.
    .paperCard(radius: Radius.concentric(SetRowScale.session.radius, padding: Space.xl))
  }

  private func footer(last: Int) -> some View {
    HStack(spacing: 10) {
      Button("anterior", systemImage: "chevron.left") {
        withAnimation(grow) { index = max(0, index - 1) }
      }
      .labelStyle(.iconOnly).buttonStyle(.glass).controlSize(.large)
      .disabled(index == 0)
      Button {
        if index >= last { dismiss() } else { withAnimation(grow) { index += 1 } }
      } label: {
        Label(index >= last ? "encerrar treino" : "próximo exercício",
          systemImage: index >= last ? "flag.checkered" : "arrow.right")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.glassProminent).tint(accent.deep).foregroundStyle(.white).controlSize(.large)
      .accessibilityIdentifier("sessao.proximo")
    }
    .padding(.horizontal, 16).padding(.bottom, 10)
  }

  /// O descanso nasce da série marcada, e a duração é a do exercício: um agachamento
  /// pesado não pede a mesma pausa que uma rosca.
  private func startRest(workout: WorkoutSummary) -> RestState {
    let id = workout.exercises.indices.contains(index) ? workout.exercises[index].id : ""
    let seconds = restSeconds[id] ?? defaultRestSeconds
    return RestState(total: seconds, endsAt: .now + seconds, next: NextSet(from: index, in: workout))
  }

  private func adjustRest(by delta: TimeInterval) {
    guard let current = rest else { return }
    let total = min(600, max(15, current.total + delta))
    if let exercises = store.dashboard?.workout?.exercises, exercises.indices.contains(index) {
      restSeconds[exercises[index].id] = total
    }
    rest = RestState(total: total, endsAt: max(.now, current.endsAt + delta), next: current.next)
  }
}

private struct WorkoutSessionClock: View {
  let timing: WorkoutSessionTiming

  var body: some View {
    if timing.finishedAt == nil {
      TimelineView(.periodic(from: .now, by: 1)) { context in
        readout(at: context.date)
      }
    } else {
      readout(at: .now)
    }
  }

  private func readout(at now: Date) -> some View {
    let seconds = Int(timing.elapsed(at: now))
    let time = Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3600
      ? .hourMinuteSecond : .minuteSecond(padMinuteToLength: 2)))
    return Text("tempo \(time)")
      .font(.subheadline.weight(.medium)).monospacedDigit()
      .foregroundStyle(Color.ink)
      .accessibilityLabel("tempo de treino")
      .accessibilityValue(time)
      .accessibilityIdentifier("sessao.tempo")
  }
}
