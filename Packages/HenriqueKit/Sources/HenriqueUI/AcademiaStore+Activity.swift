import Foundation
import HenriqueCore

// MARK: - A Live Activity da sessão

extension AcademiaStore {
  static func makeSessionActivity() -> any SessionActivity {
    #if canImport(ActivityKit) && os(iOS)
      AcademiaSessionActivity()
    #else
      NoSessionActivity()
    #endif
  }

  /// Marca pelo botão da atividade, com o app talvez fechado. A chave é a da
  /// série que estava na tela, não "a próxima": dois toques no mesmo botão não
  /// marcam duas séries.
  public func completeFromActivity(_ target: SetKey) async {
    if !sessionChecked { await start() }
    guard isSignedIn else { return }
    guard target.date == .today || hasOpenSession(on: target.date) else {
      activity.end(nil, immediately: false)
      await activity.flush()
      return
    }
    if selectedDate != target.date { selectedDate = target.date }
    if dashboard?.date != target.date { await fetchDay(target.date) }
    guard let dashboard, dashboard.date == target.date, let workout = dashboard.workout,
      workout.id == target.templateId,
      let exercise = workout.exercises.first(where: { $0.id == target.exerciseId })
    else { return }
    let set: (weightKg: Double, reps: Int, toFailure: Bool, isDone: Bool)? =
      switch target.kind {
      case .prep:
        exercise.sets.prep.first { $0.index == target.index }
          .map { ($0.weightKg, $0.reps, false, $0.isDone) }
      case .work:
        exercise.sets.work.first { $0.index == target.index }
          .map { ($0.weightKg, $0.reps, $0.toFailure, $0.isDone) }
      }
    guard let set else { return }
    if !set.isDone {
      _ = await record(
        key: target, weightKg: set.weightKg, reps: set.reps, completed: true,
        toFailure: set.toFailure)?.value
    }
    refreshActivity()
    await activity.flush()
  }

  /// Chamada na primeira série marcada do treino de hoje, com o app na frente,
  /// que é quando o sistema aceita pedir uma atividade nova.
  func startActivity(for key: SetKey) {
    guard key.date == .today, let dashboard, dashboard.date == key.date,
      let workout = dashboard.workout, workout.id == key.templateId
    else { return }
    let tone = dashboard.tone(forWorkout: workout.id)
    let attributes = SetActivityAttributes(
      date: dashboard.date, templateId: workout.id, workoutName: workout.name.lowercased(),
      toneHex: tone?.hex)
    let state = activityState(workout, on: dashboard.date)
    guard state.up != nil else { return }
    activity.start(attributes, state)
  }

  /// Leva o painel e o descanso para a atividade no ar, se ela for deste
  /// treino. Acabadas as séries valendo, a atividade sai sozinha.
  func refreshActivity() {
    guard let current = activity.current, let dashboard, dashboard.date == current.date,
      let workout = dashboard.workout, workout.id == current.templateId
    else { return }
    let state = activityState(workout, on: dashboard.date)
    if state.up == nil {
      activity.end(state, immediately: false)
    } else {
      activity.update(state)
    }
  }

  func endActivity(immediately: Bool) {
    guard let current = activity.current else { return }
    let state = dashboard.flatMap { dashboard in
      dashboard.date == current.date && dashboard.workout?.id == current.templateId
        ? dashboard.workout.map { activityState($0, on: dashboard.date) } : nil
    }
    activity.end(state, immediately: immediately)
  }

  /// A série seguinte sai do exercício do descanso em curso, senão do exercício
  /// da última série marcada. Começar do primeiro exercício voltaria para uma
  /// série que ficou para trás.
  private func activityState(_ workout: WorkoutSummary, on date: CalendarDate) -> SetActivityState {
    let resting = rest.flatMap { $0.key.date == date && !$0.isExpired(at: .now) ? $0 : nil }
    let anchor = resting?.exerciseId ?? lastMarkedExercise(in: workout)
    let index = anchor.flatMap { id in workout.exercises.firstIndex { $0.id == id } } ?? 0
    return SetActivityState(
      workout: workout, date: date, next: NextSet(from: index, in: workout),
      rest: resting.map { $0.startedAt...$0.endsAt })
  }

  private func lastMarkedExercise(in workout: WorkoutSummary) -> String? {
    workout.exercises.compactMap { exercise -> (String, Date)? in
      let dates = exercise.sets.prep.compactMap(\.completedAt) + exercise.sets.work.compactMap(\.completedAt)
      return dates.max().map { (exercise.id, $0) }
    }.max { $0.1 < $1.1 }?.0
  }
}
