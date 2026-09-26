import HenriqueCore
import SwiftUI

private enum SetupStep: Int, CaseIterable {
  case welcome, body, workout, exercises, goal, done

  var title: String {
    switch self {
    case .welcome: "começar"
    case .body: "medidas"
    case .workout: "treino"
    case .exercises: "exercícios"
    case .goal: "meta"
    case .done: "pronto"
    }
  }
}

struct SetupScreen: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accent) private var accent
  @State private var step = SetupStep.welcome
  @State private var weight: Double?
  @State private var fat: Double?
  @State private var waist: Double?
  @State private var chest: Double?
  @State private var arm: Double?
  @State private var thigh: Double?
  @State private var weekday = CalendarDate.today.weekday()
  @State private var name = ""
  @State private var focus = ""
  @State private var exercises: [PlanExercise] = []
  @State private var goalExercise = ""
  @State private var target: Double?
  @State private var picking = false
  @State private var saving = false
  @State private var initialized = false
  @State private var workoutDrafts: [Int: SetupWorkoutDraft] = [:]
  @State private var error: String?
  @State private var savedBody: AddMeasurementInput?
  @State private var savedWorkout: SaveWorkoutInput?
  @State private var savedGoal: SetStrengthGoalInput?
  private let days = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"]

  private func catalogItem(_ id: String) -> ExerciseCatalogItem? {
    store.dashboard?.exerciseCatalog.first { $0.id == id }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Space.xxl) {
          PageHeading(title: step.title)
          fields
          if let error { Text(error).font(.subheadline).foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently) }
          HStack {
            if step != .welcome {
              Button("voltar") { step = SetupStep(rawValue: step.rawValue - 1) ?? .welcome; error = nil }
                .buttonStyle(.glass).controlSize(.large)
            }
            Spacer()
            Button(saving ? "salvando" : step == .done ? "abrir treino" : "continuar") {
              Task { await advance() }
            }.buttonStyle(.glassProminent).controlSize(.large)
          }
          if step != .welcome && step != .done {
            Button {
              step = step == .body ? .workout : step == .workout || step == .exercises ? .goal : .done
              error = nil
            } label: {
              Text("pular").font(.subheadline).foregroundStyle(.tint)
                .frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
            }.buttonStyle(StudyPressStyle())
          }
          ProgressView(value: Double(step.rawValue + 1), total: 6).tint(accent.base)
            .accessibilityLabel("Etapa \(step.rawValue + 1) de 6")
        }.padding(Space.l).disabled(saving)
      }
      .background(Color.canvas.ignoresSafeArea())
      .navigationTitle("h&")
      .toolbarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("fechar") { dismiss() }.disabled(saving) }
      }
      .keyboardDone()
      .interactiveDismissDisabled(saving)
      .sheet(isPresented: $picking) {
        ExercisePicker(catalog: store.dashboard?.exerciseCatalog ?? [], chosen: Set(exercises.map(\.exerciseId))) { item in
          let known = (store.dashboard?.exerciseCatalog ?? []).contains(where: { $0.id == item.id })
          exercises.append(PlanExercise(exerciseId: item.id, prepSets: 2, workSets: 2,
            repsMin: 8, repsMax: 12, workToFailure: true, startingWeightKg: 0,
            name: known ? nil : item.name, muscleGroup: known ? nil : item.muscleGroup,
            equipment: known ? nil : item.equipment, imageUrl: known ? nil : item.imageUrl))
        }
      }
      .onAppear {
        guard !initialized else { return }
        initialized = true
        weight = store.dashboard?.measurements.first?.weightKg
        fat = store.dashboard?.measurements.first?.bodyFatPercent
        waist = store.dashboard?.measurements.first?.waistCm
        goalExercise = store.dashboard?.strengthGoal?.exerciseId ?? store.dashboard?.exerciseCatalog.first?.id ?? ""
        target = store.dashboard?.strengthGoal?.targetValue
        loadWorkout()
      }
    }
  }

  @ViewBuilder private var fields: some View {
    switch step {
    case .welcome:
      Image(systemName: "dumbbell").font(.system(size: 56)).foregroundStyle(accent.deep)
        .frame(maxWidth: .infinity, minHeight: 180).background(accent.acid, in: .rect(cornerRadius: Radius.card))
    case .body:
      VStack(spacing: Space.l) {
        measurement("peso", unit: "kg", value: $weight)
        measurement("gordura", unit: "%", value: $fat)
        measurement("cintura", unit: "cm", value: $waist)
        measurement("peito", unit: "cm", value: $chest)
        measurement("braço", unit: "cm", value: $arm)
        measurement("coxa", unit: "cm", value: $thigh)
      }.padding(Space.xl).paperCard()
    case .workout:
      VStack(alignment: .leading, spacing: Space.l) {
        Picker("dia", selection: $weekday) {
          ForEach(0..<7, id: \.self) { Text(days[$0]).tag($0) }
        }.onChange(of: weekday) { oldDay, _ in
          workoutDrafts[oldDay] = SetupWorkoutDraft(name: name, focus: focus, exercises: exercises)
          loadWorkout()
        }
        TextField("nome", text: $name).textFieldStyle(.roundedBorder)
          .submitLabel(.done)
        TextField("foco", text: $focus).textFieldStyle(.roundedBorder)
          .submitLabel(.done)
      }.padding(Space.xl).paperCard()
    case .exercises:
      VStack(spacing: Space.l) {
        ForEach($exercises) { $exercise in
          PlanExerciseRow(exercise: $exercise,
            name: catalogItem(exercise.exerciseId)?.name ?? exercise.exerciseId,
            subtitle: catalogItem(exercise.exerciseId).map {
              "\($0.muscleGroup.lowercased()) · \($0.equipment.lowercased())"
            },
            imageUrl: catalogItem(exercise.exerciseId)?.imageUrl,
            onRemove: { exercises.removeAll { $0.exerciseId == exercise.exerciseId } })
            .padding(Space.xl).paperCard()
        }
        Button("adicionar", systemImage: "plus") { picking = true }
          .buttonStyle(.glass).controlSize(.large)
          .disabled(exercises.count >= Limits.exerciseCount.upperBound)
      }
    case .goal:
      VStack(alignment: .leading, spacing: Space.l) {
        Picker("exercício", selection: $goalExercise) {
          ForEach(store.dashboard?.exerciseCatalog ?? []) { Text($0.name).tag($0.id) }
        }
        measurement("meta", unit: "kg", value: $target)
      }.padding(Space.xl).paperCard()
    case .done:
      VStack(alignment: .leading, spacing: 16) {
        if savedBody != nil { Label("medidas", systemImage: "checkmark.circle") }
        if savedWorkout != nil { Label("treino", systemImage: "checkmark.circle") }
        if savedGoal != nil { Label("meta", systemImage: "checkmark.circle") }
      }.foregroundStyle(accent.base)
    }
  }

  private func measurement(_ title: String, unit: String, value: Binding<Double?>) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.caption).foregroundStyle(Color.mutedInk)
      HStack {
        TextField("", value: value, format: .number.precision(.fractionLength(0...2)))
          .submitLabel(.done)
          .decimalInput().accessibilityLabel(title)
        Text(unit).foregroundStyle(Color.mutedInk)
      }
    }
  }

  /// O treino que já cai no dia escolhido. Salvar por ele mantém os outros dias
  /// desse treino em vez de criar um treino novo só para esse dia.
  private var plannedWorkout: WeekPlanItem? {
    store.dashboard?.weekPlan.first { $0.weekdays.contains(weekday) }
  }

  /// O foco digitado, ou os grupos musculares dos exercícios escolhidos. Um
  /// exercício vindo da wger não está no catálogo, então o grupo sai do próprio
  /// item. Sem grupo nenhum, vai o nome do treino, porque o servidor pede pelo
  /// menos dois caracteres.
  private var resolvedFocus: String {
    let typed = focus.trimmingCharacters(in: .whitespaces)
    if !typed.isEmpty { return typed }
    let groups = exercises.compactMap { exercise in
      catalogItem(exercise.exerciseId)?.muscleGroup ?? exercise.muscleGroup
    }
    let joined = Array(Set(groups)).sorted().joined(separator: ", ")
    return Limits.workoutFocusLength.contains(joined.count) ? joined : name.trimmingCharacters(in: .whitespaces)
  }

  private func loadWorkout() {
    if let draft = workoutDrafts[weekday] {
      name = draft.name
      focus = draft.focus
      exercises = draft.exercises
      return
    }
    let item = plannedWorkout
    name = item?.name ?? ""
    focus = item?.focus ?? ""
    exercises = item?.exercises ?? []
  }

  private func advance() async {
    guard !saving else { return }
    saving = true
    error = nil
    defer { saving = false }
    switch step {
    case .welcome: step = .body
    case .body:
      guard let weight, Limits.bodyWeightKg.contains(weight) else {
        error = "peso entre \(Int(Limits.bodyWeightKg.lowerBound)) e \(Int(Limits.bodyWeightKg.upperBound)) kg"; return
      }
      let input = AddMeasurementInput(date: .today, weightKg: weight, bodyFatPercent: fat, waistCm: waist, chestCm: chest, armCm: arm, thighCm: thigh)
      if input != savedBody {
        guard await store.addMeasurement(input) else { error = store.banner; return }
        savedBody = input
      }
      step = .workout
    case .workout:
      let trimmedFocus = focus.trimmingCharacters(in: .whitespaces)
      guard Limits.workoutNameLength.contains(name.trimmingCharacters(in: .whitespaces).count),
        trimmedFocus.isEmpty || Limits.workoutFocusLength.contains(trimmedFocus.count) else {
        error = "nome de 2 a 80 letras e foco até 140"; return
      }
      step = .exercises
    case .exercises:
      guard Limits.exerciseCount.contains(exercises.count),
        exercises.allSatisfy({ $0.repsMin <= $0.repsMax && $0.startingWeightKg >= 0 }) else {
        error = "confira os exercícios"; return
      }
      let planned = plannedWorkout
      let input = SaveWorkoutInput(date: store.selectedDate, workoutTemplateId: planned?.id,
        weekdays: planned?.weekdays ?? [weekday], name: name,
        focus: resolvedFocus, estimatedMinutes: WorkoutEstimate.minutes(plan: exercises), exercises: exercises)
      if input != savedWorkout {
        guard await store.saveWorkout(input) else { error = store.banner; return }
        savedWorkout = input
      }
      step = .goal
    case .goal:
      guard let target, Limits.strengthTarget.contains(target), !goalExercise.isEmpty else {
        error = "meta entre \(Int(Limits.strengthTarget.lowerBound)) e \(Int(Limits.strengthTarget.upperBound)) kg"; return
      }
      let input = SetStrengthGoalInput(date: store.selectedDate, exerciseId: goalExercise, targetValue: target)
      if input != savedGoal {
        guard await store.setStrengthGoal(input) else { error = store.banner; return }
        savedGoal = input
      }
      step = .done
    case .done:
      if await store.completeSetup() { dismiss() } else { error = store.banner }
    }
  }
}

private struct SetupWorkoutDraft {
  let name: String
  let focus: String
  let exercises: [PlanExercise]
}
