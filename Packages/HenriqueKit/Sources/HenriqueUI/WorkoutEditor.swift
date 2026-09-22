import HenriqueCore
import SwiftUI

/// Os passos do editor, na ordem em que aparecem. A barra de baixo, o botão de
/// voltar e o de concluir leem daqui, então um passo novo entra só nesta lista.
enum EditorStep: Int, CaseIterable, Hashable {
  case identidade, cor, dias, exercicios

  var title: String {
    switch self {
    case .identidade: "nome e foco"
    case .cor: "escolha a cor"
    case .dias: "dias"
    case .exercicios: "exercícios"
    }
  }

  var previous: EditorStep? { EditorStep(rawValue: rawValue - 1) }
  var next: EditorStep? { EditorStep(rawValue: rawValue + 1) }

  /// O que o passo exige antes de salvar. Cor e dias aceitam qualquer valor:
  /// a cor sempre existe e treino sem dia é permitido.
  func isSatisfied(by draft: WorkoutDraft) -> Bool {
    switch self {
    case .identidade:
      Limits.workoutNameLength.contains(draft.trimmedName.count)
        && Limits.workoutFocusLength.contains(draft.trimmedFocus.count)
        && Limits.estimatedMinutes.contains(draft.estimatedMinutes)
    case .cor, .dias:
      true
    case .exercicios:
      Limits.exerciseCount.contains(draft.exercises.count)
        && draft.exercises.allSatisfy { $0.repsMin <= $0.repsMax && $0.startingWeightKg >= 0 }
    }
  }
}

/// O treino em edição, antes de virar `SaveWorkoutInput`.
struct WorkoutDraft: Hashable {
  var name: String
  var focus: String
  var estimatedMinutes: Int
  var color: WorkoutColor
  var weekdays: Set<Int>
  var exercises: [PlanExercise]

  var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
  var trimmedFocus: String { focus.trimmingCharacters(in: .whitespaces) }
  var canSave: Bool { EditorStep.allCases.allSatisfy { $0.isSatisfied(by: self) } }
}

struct WorkoutEditor: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var draft: WorkoutDraft
  @State private var step: EditorStep
  /// Para onde o fluxo andou por último. O passo novo entra por esse lado.
  @State private var enteringEdge: Edge = .trailing
  @State private var isSaving = false
  /// O catálogo por id, montado uma vez. Cada tecla no nome roda o body de novo
  /// e cada linha de exercício lê daqui, então a busca não pode varrer a lista.
  @State private var exerciseInfo: [String: ExerciseCatalogItem]

  private let catalog: [ExerciseCatalogItem]
  private let workoutId: String?

  init(
    item: WeekPlanItem?, weekdays: Set<Int>, tone: WorkoutTone, catalog: [ExerciseCatalogItem],
    startingAt step: EditorStep = .identidade
  ) {
    workoutId = item?.id
    _step = State(initialValue: step)
    self.catalog = catalog
    exerciseInfo = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    draft = WorkoutDraft(
      name: item?.name ?? "", focus: item?.focus ?? "",
      estimatedMinutes: item?.estimatedMinutes ?? 55,
      color: tone.color, weekdays: weekdays, exercises: item?.exercises ?? [])
  }

  private var stepAnimation: Animation {
    reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.35)
  }

  private var stepTransition: AnyTransition {
    guard !reduceMotion else { return .opacity }
    let leaving: Edge = enteringEdge == .trailing ? .leading : .trailing
    return .asymmetric(
      insertion: .move(edge: enteringEdge).combined(with: .opacity),
      removal: .move(edge: leaving).combined(with: .opacity))
  }

  var body: some View {
    // A barra do teclado com "concluído" só aparece dentro de uma pilha de
    // navegação; a barra de navegação em si fica escondida.
    NavigationStack {
      flow
        .toolbar(.hidden, for: .navigationBar)
        .keyboardDone()
    }
    .disabled(isSaving)
    .interactiveDismissDisabled(isSaving)
  }

  private var flow: some View {
    VStack(spacing: 0) {
      HStack {
        RoundButton(systemImage: "chevron.left", fill: Color.surfaceMuted, ink: Color.ink, label: "fechar", nudge: 1) {
          dismiss()
        }
        .disabled(isSaving)
        Spacer()
        Button("concluir") { save() }
          .buttonStyle(.glassProminent)
          .controlSize(.large)
          .tint(.blue)
          .disabled(!draft.canSave || isSaving)
      }
      .padding(.horizontal, Space.l)
      .padding(.top, Space.m)

      WorkoutFolderCard(
        name: draft.name.isEmpty ? "novo treino" : draft.name,
        tone: draft.color.tone, hasDays: !draft.weekdays.isEmpty
      )
      .dynamicTypeSize(.large)
      .containerRelativeFrame(.horizontal) { width, _ in width * 0.62 }
      .padding(.top, 8)
      .accessibilityHidden(true)

      ZStack {
        RoundButton(systemImage: "arrow.left", fill: Color.ink, ink: .white, label: "voltar", nudge: 0.5) {
          go(to: step.previous)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(step.previous == nil ? 0 : 1)
        .disabled(step.previous == nil || isSaving)
        Text(step.title)
          .font(.headline.weight(.semibold))
          .foregroundStyle(Color.ink)
          .accessibilityAddTraits(.isHeader)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)

      ZStack {
        switch step {
        case .identidade:
          IdentityStep(draft: $draft).transition(stepTransition)
        case .cor:
          WorkoutColorPicker(color: $draft.color).padding(16).transition(stepTransition)
        case .dias:
          WorkoutDaysSection(selection: $draft.weekdays, workoutId: workoutId)
            .padding(16).transition(stepTransition)
        case .exercicios:
          ExercisesStep(
            exercises: $draft.exercises, exerciseInfo: $exerciseInfo, catalog: catalog,
            workoutId: workoutId, workoutName: draft.trimmedName, isSaving: isSaving, onDelete: remove
          )
          .transition(stepTransition)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .clipped()
    }
    .background(Color.canvas)
    .safeAreaInset(edge: .bottom) {
      if let next = step.next {
        Button("avançar") { go(to: next) }
          .buttonStyle(.glass)
          .controlSize(.large)
          .frame(maxWidth: .infinity)
          .padding(16)
          .disabled(!step.isSatisfied(by: draft) || isSaving)
      }
    }
  }

  private func go(to target: EditorStep?) {
    guard let target else { return }
    dismissKeyboard()
    enteringEdge = target.rawValue > step.rawValue ? .trailing : .leading
    withAnimation(stepAnimation) { step = target }
  }

  private func save() {
    let input = SaveWorkoutInput(
      date: store.selectedDate, workoutTemplateId: workoutId, weekdays: draft.weekdays.sorted(),
      name: draft.trimmedName, focus: draft.trimmedFocus, estimatedMinutes: draft.estimatedMinutes,
      color: draft.color.hex, exercises: draft.exercises)
    isSaving = true
    Task {
      let saved = await store.saveWorkout(input)
      isSaving = false
      if saved { dismiss() }
    }
  }

  private func remove() {
    guard let workoutId else { return }
    store.deleteWorkout(workoutTemplateId: workoutId)
    dismiss()
  }
}

private struct RoundButton: View {
  let systemImage: String
  let fill: Color
  let ink: Color
  let label: String
  var nudge: CGFloat = 0
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Circle()
        .fill(fill)
        .frame(width: 44, height: 44)
        .overlay {
          Image(systemName: systemImage)
            .font(.system(.body, weight: .semibold))
            .foregroundStyle(ink)
            .offset(x: nudge)
        }
    }
    .buttonStyle(StudyPressStyle())
    .accessibilityLabel(label)
  }
}

private struct IdentityStep: View {
  @Binding var draft: WorkoutDraft

  var body: some View {
    VStack(spacing: 12) {
      EditorField {
        TextField("nome", text: $draft.name).submitLabel(.done)
      }
      EditorField {
        TextField("foco", text: $draft.focus).submitLabel(.done)
      }
      EditorField {
        HStack {
          TextField("minutos", value: $draft.estimatedMinutes, format: .number)
            .submitLabel(.done)
            .decimalInput()
          Text("min").font(.subheadline).foregroundStyle(Color.mutedInk)
        }
      }
    }
    .padding(16)
  }
}

/// O campo branco de canto redondo que o resto do app usa fora do `Form`.
private struct EditorField<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    content
      .font(.body)
      .padding(.horizontal, 16)
      .frame(minHeight: 52)
      .background(.white, in: .rect(cornerRadius: 18))
      .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.ink.opacity(0.08)))
  }
}

private struct ExercisesStep: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  #if os(iOS)
  @State private var editMode: EditMode = .inactive
  #endif
  @State private var isPickingExercise = false
  @State private var confirmDelete = false
  @Binding var exercises: [PlanExercise]
  @Binding var exerciseInfo: [String: ExerciseCatalogItem]
  let catalog: [ExerciseCatalogItem]
  let workoutId: String?
  let workoutName: String
  let isSaving: Bool
  let onDelete: () -> Void

  private var isOrganizing: Bool {
    #if os(iOS)
    editMode.isEditing
    #else
    false
    #endif
  }

  private var editAnimation: Animation? {
    reduceMotion ? nil : .spring(duration: 0.25, bounce: 0)
  }

  var body: some View {
    List {
      Section {
        ForEach($exercises) { $exercise in
          let exerciseId = exercise.exerciseId
          let info = exerciseInfo[exerciseId]
          PlanExerciseRow(
            exercise: $exercise, name: info?.name ?? exercise.exerciseId,
            subtitle: info.map { "\($0.muscleGroup.lowercased()) · \($0.equipment.lowercased())" },
            imageUrl: info?.imageUrl, isOrganizing: isOrganizing,
            onRemove: {
              withAnimation(editAnimation) {
                exercises.removeAll { $0.exerciseId == exerciseId }
              }
            })
            .deleteDisabled(isSaving)
            .moveDisabled(isSaving)
        }
        .onDelete { offsets in
          withAnimation(editAnimation) { exercises.remove(atOffsets: offsets) }
        }
        .onMove { offsets, destination in
          withAnimation(editAnimation) {
            exercises.move(fromOffsets: offsets, toOffset: destination)
          }
        }

        Button("adicionar", systemImage: "plus") {
          isPickingExercise = true
        }
        .disabled(exercises.count >= Limits.exerciseCount.upperBound)
      } header: {
        #if os(iOS)
        if !exercises.isEmpty || isOrganizing {
          HStack {
            Spacer()
            Button {
              withAnimation(editAnimation) {
                editMode = isOrganizing ? .inactive : .active
              }
            } label: {
              Text(isOrganizing ? "ok" : "ordenar")
                .font(.subheadline.weight(.semibold))
                .textCase(nil)
                .foregroundStyle(.tint)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(StudyPressStyle())
            .accessibilityHint(isOrganizing
              ? "Voltar aos ajustes dos exercícios"
              : "Mostrar alças para arrastar os exercícios")
          }
        }
        #endif
      }

      if workoutId != nil {
        Section {
          Button("apagar treino", systemImage: "trash", role: .destructive) {
            confirmDelete = true
          }
          .disabled(isSaving)
          .deleteWorkoutConfirmation(isPresented: $confirmDelete, name: workoutName, onDelete: onDelete)
        }
      }
    }
    .scrollContentBackground(.hidden)
    #if os(iOS)
    .environment(\.editMode, $editMode)
    #endif
    .sheet(isPresented: $isPickingExercise) {
      ExercisePicker(catalog: catalog, chosen: Set(exercises.map(\.exerciseId))) { item in
        let known = catalog.contains(where: { $0.id == item.id })
        exerciseInfo[item.id] = item
        exercises.append(
          PlanExercise(
            exerciseId: item.id, prepSets: 2, workSets: 2, repsMin: 8, repsMax: 12,
            workToFailure: true, startingWeightKg: 0, name: known ? nil : item.name,
            muscleGroup: known ? nil : item.muscleGroup,
            equipment: known ? nil : item.equipment,
            imageUrl: known ? nil : item.imageUrl))
      }
    }
  }
}

/// Os sete dias num toque cada, na ordem da semana do aparelho. O aviso embaixo
/// diz quando um dia marcado sai de outro treino, antes de salvar.
struct WorkoutDaysSection: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.dynamicTypeSize) private var textSize
  @Binding var selection: Set<Int>
  let workoutId: String?

  private var orderedWeekdays: [Int] {
    let first = Calendar.autoupdatingCurrent.firstWeekday - 1
    return (0..<7).map { (first + $0) % 7 }
  }

  var body: some View {
    let handoffs = WeekdayOwners(plan: store.weekPlan, excluding: workoutId).handoffs(to: selection)
    VStack(alignment: .leading, spacing: 12) {
      // Nos tamanhos de acessibilidade sete círculos não cabem numa linha. Em
      // quatro colunas cada círculo cresce com o texto e a semana quebra em duas.
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: 4),
                       count: textSize.isAccessibilitySize ? 4 : 7),
        spacing: 8
      ) {
        ForEach(orderedWeekdays, id: \.self) { day in
          WeekdayToggle(
            shortName: planWeekdaysShort[day], fullName: planWeekdays[day],
            isOn: selection.contains(day)
          ) {
            if selection.contains(day) { selection.remove(day) } else { selection.insert(day) }
          }
        }
      }
      .sensoryFeedback(.selection, trigger: selection)
      if !handoffs.isEmpty {
        Text(handoffs.map(Self.note).joined(separator: " "))
          .font(.footnote)
          .foregroundStyle(Color.mutedInk)
      }
    }
  }

  private static func note(_ handoff: WeekdayHandoff) -> String {
    let days = spokenWeekdays(handoff.weekdays)
    let verb = handoff.weekdays.count == 1 ? "sai" : "saem"
    guard handoff.becomesUnscheduled else { return "\(days) \(verb) de \(handoff.workoutName)" }
    return "\(handoff.workoutName) continua sem dia"
  }
}

/// A troca de cor é imediata. Marcar dia é toque repetido, e esperar uma
/// animação a cada toque deixa a fileira lenta.
private struct WeekdayToggle: View {
  let shortName: String
  let fullName: String
  let isOn: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Circle()
        .fill(isOn ? Color.ink : Color.surfaceMuted)
        .overlay {
          Text(shortName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isOn ? .white : Color.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .offset(y: -1)
            .padding(4)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(.rect)
    }
    .buttonStyle(StudyPressStyle())
    .accessibilityLabel(fullName)
    .accessibilityAddTraits(isOn ? .isSelected : [])
  }
}

extension View {
  /// O treino leva junto as sessões e as séries registradas nele, então o
  /// diálogo diz o nome e o que se perde.
  func deleteWorkoutConfirmation(
    isPresented: Binding<Bool>, name: String, onDelete: @escaping () -> Void
  ) -> some View {
    confirmationDialog("apagar \(name)?", isPresented: isPresented, titleVisibility: .visible) {
      Button("apagar", role: .destructive, action: onDelete)
      Button("cancelar", role: .cancel) {}
    } message: {
      Text("as séries somem junto")
    }
  }
}

#if DEBUG
  #Preview("Editor, nome e foco") { WorkoutEditorPreview(step: .identidade) }
  #Preview("Editor, cor") { WorkoutEditorPreview(step: .cor) }
  #Preview("Editor, dias") { WorkoutEditorPreview(step: .dias) }
  #Preview("Editor, exercícios") { WorkoutEditorPreview(step: .exercicios) }
  #Preview("Card de pasta") {
    HStack(spacing: 12) {
      WorkoutFolderCard(name: "peito e tríceps", tone: .at(0), hasDays: true)
      WorkoutFolderCard(name: "pernas", tone: .at(1), hasDays: false)
    }
    .padding(16)
    .background(Color.canvas)
  }

  private struct WorkoutEditorPreview: View {
    @State private var store = AcademiaStore(
      client: APIClient(baseURL: URL(string: "http://localhost:3000")!, tokenStore: KeychainTokenStore()))
    let step: EditorStep

    var body: some View {
      WorkoutEditor(item: nil, weekdays: [1, 4], tone: .at(step.rawValue), catalog: [], startingAt: step)
        .environment(store)
    }
  }
#endif
