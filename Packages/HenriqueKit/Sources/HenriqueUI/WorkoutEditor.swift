import HenriqueCore
import SwiftUI

/// Os passos do editor, na ordem em que aparecem. A barra de baixo, o botão de
/// voltar e o de concluir leem daqui, então um passo novo entra só nesta lista.
enum EditorStep: Int, CaseIterable, Hashable {
  case identidade, cor, dias, exercicios

  var title: String {
    switch self {
    case .identidade: "nome"
    case .cor: "cor"
    case .dias: "dias"
    case .exercicios: "exercícios"
    }
  }

  var previous: EditorStep? { EditorStep(rawValue: rawValue - 1) }
  var next: EditorStep? { EditorStep(rawValue: rawValue + 1) }

  /// O que falta para o passo valer, na frase que a tela mostra. Nulo quando
  /// não falta nada. Cor e dias aceitam qualquer valor: a cor sempre existe e
  /// treino sem dia é permitido. O foco pode ficar vazio, porque o salvar
  /// preenche com os grupos dos exercícios.
  func missing(in draft: WorkoutDraft) -> String? {
    switch self {
    case .identidade:
      if !Limits.workoutNameLength.contains(draft.trimmedName.count) { return "nome com 2 letras ou mais" }
      if !draft.trimmedFocus.isEmpty, !Limits.workoutFocusLength.contains(draft.trimmedFocus.count) {
        return "foco com 2 letras ou mais"
      }
      return nil
    case .cor, .dias:
      return nil
    case .exercicios:
      if draft.exercises.isEmpty { return "adicione um exercício" }
      if !Limits.exerciseCount.contains(draft.exercises.count) {
        return "até \(Limits.exerciseCount.upperBound) exercícios"
      }
      if !draft.exercises.allSatisfy({ $0.repsMin <= $0.repsMax && $0.startingWeightKg >= 0 }) {
        return "confira as repetições"
      }
      return nil
    }
  }

  func isSatisfied(by draft: WorkoutDraft) -> Bool { missing(in: draft) == nil }
}

/// O treino em edição, antes de virar `SaveWorkoutInput`.
struct WorkoutDraft: Hashable {
  var name: String
  var focus: String
  var color: WorkoutColor
  var weekdays: Set<Int>
  var exercises: [PlanExercise]

  var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
  var trimmedFocus: String { focus.trimmingCharacters(in: .whitespaces) }
  /// O servidor exige o campo; ele sai das séries em vez de ser digitado.
  var estimatedMinutes: Int { WorkoutEstimate.minutes(plan: exercises) }
}

struct WorkoutEditor: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accent) private var accent
  @Environment(\.dynamicTypeSize) private var textSize
  @State private var draft: WorkoutDraft
  @State private var step: EditorStep
  @State private var forward = true
  @State private var isSaving = false
  @State private var saves = 0
  @State private var deletions = 0
  @State private var appliedRestOverrides = false
  /// O rascunho como abriu. Diferente do atual, fechar pede confirmação.
  @State private var original: WorkoutDraft?
  @State private var confirmDiscard = false
  /// Liga depois de um toque em "avançar" ou "concluir" que não pôde seguir.
  @State private var showsMissing = false
  @State private var blocked = 0
  @State private var saveError: String?
  #if os(iOS)
  /// Mora aqui, e não na lista, para o botão de organizar ficar fixo no topo
  /// enquanto a lista rola embaixo dele.
  @State private var editMode: EditMode = .inactive
  #endif
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
      color: tone.color, weekdays: weekdays, exercises: item?.exercises ?? [])
  }

  private var stepAnimation: Animation {
    Motion.resolve(Motion.confirm, reduceMotion)
  }

  /// O passo novo entra pelo lado para onde se anda. O que sai só apaga: ele
  /// guarda a transição do último desenho, e na volta deslizaria para o lado
  /// errado.
  private var stepTransition: AnyTransition {
    guard !reduceMotion else { return .opacity }
    return .asymmetric(
      insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
      removal: .opacity)
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
    .interactiveDismissDisabled(isSaving || isDirty)
    .sensoryFeedback(.error, trigger: blocked)
    .sensoryFeedback(.success, trigger: saves)
    .sensoryFeedback(.impact(weight: .medium), trigger: deletions)
    .onAppear(perform: applyRestOverrides)
  }

  private var isDirty: Bool { original.map { $0 != draft } ?? false }

  /// O descanso ajustado na sessão mora no aparelho até o próximo salvar. O
  /// editor mostra esse valor e manda ele junto.
  private func applyRestOverrides() {
    guard !appliedRestOverrides else { return }
    appliedRestOverrides = true
    for index in draft.exercises.indices {
      if let chosen = store.restOverride(for: draft.exercises[index].exerciseId) {
        draft.exercises[index].restSeconds = chosen
      }
    }
    original = draft
  }

  private var flow: some View {
    VStack(spacing: 0) {
      HStack {
        // Um x, e não uma seta: a seta de voltar o passo fica logo abaixo, e as
        // duas setas liam como dois botões de voltar.
        RoundButton(systemImage: "xmark", fill: Color.surfaceMuted, ink: Color.ink, label: "fechar") {
          if isDirty { confirmDiscard = true } else { dismiss() }
        }
        .disabled(isSaving)
        .confirmationDialog("descartar alterações?", isPresented: $confirmDiscard, titleVisibility: .visible) {
          Button("descartar", role: .destructive) { dismiss() }
          Button("continuar editando", role: .cancel) {}
        }
        Spacer()
        Button("concluir", systemImage: "checkmark", action: attemptSave)
          .buttonStyle(.glassProminent)
          .controlSize(.large)
          .tint(accent.deep)
          .disabled(isSaving)
      }
      .padding(.horizontal, Space.l)
      .padding(.top, Space.m)

      // No passo do nome o campo já mostra o nome sendo digitado; a prévia só
      // repetia. Nos tamanhos de acessibilidade a pasta desce para dentro da
      // rolagem do passo da cor, senão empurrava a barra para fora da folha.
      if step == .cor {
        if !textSize.isAccessibilitySize {
          folderPreview
            .padding(.top, Space.s)
            .transition(.opacity)
        }
      } else if step != .identidade {
        WorkoutPreviewRow(name: displayName, tone: draft.color.tone)
          .padding(.horizontal, Space.l)
          .padding(.top, Space.m)
          .transition(.opacity)
      }

      ZStack {
        RoundButton(systemImage: "arrow.left", fill: Color.ink, ink: .white, label: "voltar", nudge: 0.5) {
          go(to: step.previous)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(step.previous == nil ? 0 : 1)
        .disabled(step.previous == nil || isSaving)
        StepDots(current: step, go: go(to:))
        #if os(iOS)
        if step == .exercicios, draft.exercises.count > 1 || isOrganizing {
          RoundButton(
            systemImage: isOrganizing ? "checkmark" : "arrow.up.arrow.down",
            fill: isOrganizing ? Color.ink : Color.surfaceMuted,
            ink: isOrganizing ? .white : Color.ink,
            label: isOrganizing ? "concluir ordem" : "ordenar exercícios"
          ) {
            dismissKeyboard()
            withAnimation(Motion.resolve(Motion.expand, reduceMotion)) {
              editMode = isOrganizing ? .inactive : .active
            }
          }
          .accessibilityHint(isOrganizing
            ? "Voltar aos ajustes dos exercícios"
            : "Mostrar alças para arrastar os exercícios")
          .sensoryFeedback(.selection, trigger: isOrganizing)
          .frame(maxWidth: .infinity, alignment: .trailing)
          .disabled(isSaving)
          .transition(.opacity)
        }
        #endif
      }
      .padding(.horizontal, Space.l)
      .padding(.vertical, Space.m)

      if let saveError {
        Label(saveError, systemImage: "exclamationmark.triangle.fill")
          .font(.footnote)
          .foregroundStyle(Color.danger)
          .padding(.horizontal, Space.l)
          .padding(.bottom, Space.s)
          .transition(.opacity)
      } else if showsMissing, let missing = step.missing(in: draft) {
        Text(missing)
          .font(.footnote)
          .foregroundStyle(Color.mutedInk)
          .padding(.horizontal, Space.l)
          .padding(.bottom, Space.s)
          .transition(.opacity)
      }

      ZStack {
        switch step {
        case .identidade:
          IdentityStep(draft: $draft).transition(stepTransition)
        case .cor:
          ScrollView {
            VStack(spacing: Space.l) {
              if textSize.isAccessibilitySize { folderPreview }
              WorkoutColorPicker(color: $draft.color)
            }
            .padding(Space.l)
          }
          // Só rola quando o texto grande não deixa caber; no tamanho padrão o
          // arraste vertical do quadro de cor não disputa com a rolagem.
          .scrollDisabled(!textSize.isAccessibilitySize)
          .transition(stepTransition)
        case .dias:
          WorkoutDaysSection(selection: $draft.weekdays, workoutId: workoutId)
            .padding(Space.l).transition(stepTransition)
        case .exercicios:
          ScrollViewReader { proxy in
            ExercisesStep(
              exercises: $draft.exercises, exerciseInfo: $exerciseInfo, catalog: catalog,
              workoutId: workoutId, workoutName: draft.trimmedName, isSaving: isSaving,
              scroll: proxy, onDelete: remove
            )
          }
          #if os(iOS)
          .environment(\.editMode, $editMode)
          #endif
          .transition(stepTransition)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .clipped()
    }
    .background(Color.canvas)
    .safeAreaInset(edge: .bottom) {
      if let next = step.next {
        Button("avançar", systemImage: "arrow.right") {
          if step.isSatisfied(by: draft) { go(to: next) } else { block(at: step) }
        }
          .buttonStyle(.glass)
          .controlSize(.large)
          .frame(maxWidth: .infinity)
          .padding(Space.l)
          .disabled(isSaving)
      }
    }
  }

  private var folderPreview: some View {
    WorkoutFolderCard(
      name: displayName, tone: draft.color.tone, weekdays: draft.weekdays.sorted(),
      exerciseCount: draft.exercises.count
    )
    .dynamicTypeSize(.large)
    // A 62% a pasta, o seletor e o título passavam da altura da folha e
    // empurravam o "fechar" para cima só neste passo.
    .containerRelativeFrame(.horizontal) { width, _ in width * 0.54 }
    .accessibilityHidden(true)
  }

  private var isOrganizing: Bool {
    #if os(iOS)
    editMode.isEditing
    #else
    false
    #endif
  }

  private var displayName: String {
    draft.trimmedName.isEmpty ? "novo treino" : draft.trimmedName
  }

  private func go(to target: EditorStep?) {
    guard let target else { return }
    dismissKeyboard()
    forward = target.rawValue > step.rawValue
    withAnimation(stepAnimation) {
      step = target
      #if os(iOS)
      editMode = .inactive
      #endif
    }
  }

  /// "concluir" fica sempre ativo. Faltando algo, leva ao primeiro passo que
  /// não vale e diz o que falta, em vez de ficar apagado sem explicar.
  private func attemptSave() {
    if let target = EditorStep.allCases.first(where: { !$0.isSatisfied(by: draft) }) {
      block(at: target)
    } else {
      save()
    }
  }

  private func block(at target: EditorStep) {
    withAnimation(Motion.resolve(Motion.subtleEntrance, reduceMotion)) { showsMissing = true }
    blocked += 1
    if let missing = target.missing(in: draft) { AccessibilityNotification.Announcement(missing).post() }
    if target != step { go(to: target) }
  }

  private func save() {
    // O valor salvo passa a ser o do aparelho também. Com o servidor antigo,
    // que não guarda descanso, é ele que continua valendo.
    for exercise in draft.exercises {
      if let seconds = exercise.restSeconds { store.setRestSeconds(seconds, for: exercise.exerciseId) }
    }
    let input = SaveWorkoutInput(
      date: store.selectedDate, workoutTemplateId: workoutId, weekdays: draft.weekdays.sorted(),
      name: draft.trimmedName,
      focus: SaveWorkoutInput.focus(
        typed: draft.trimmedFocus,
        muscleGroups: draft.exercises.compactMap { exerciseInfo[$0.exerciseId]?.muscleGroup ?? $0.muscleGroup },
        name: draft.trimmedName),
      estimatedMinutes: draft.estimatedMinutes,
      color: draft.color.hex,
      exercises: draft.exercises.keepingCurrentLoads(untouchedSince: original?.exercises ?? []) {
        store.dashboard?.loadKg(exerciseId: $0)
      })
    isSaving = true
    saveError = nil
    Task {
      let saved = await store.saveWorkout(input)
      isSaving = false
      if saved {
        saves += 1
        dismiss()
        return
      }
      // O alerta do app fica embaixo da folha e não sobe enquanto ela está
      // aberta, então o erro aparece aqui e sai do banner.
      let message = store.banner ?? "não deu para salvar"
      store.banner = nil
      withAnimation(Motion.resolve(Motion.subtleEntrance, reduceMotion)) { saveError = message }
      blocked += 1
      AccessibilityNotification.Announcement(message).post()
    }
  }

  private func remove() {
    guard let workoutId else { return }
    withAnimation(Motion.resolve(Motion.confirm, reduceMotion)) {
      store.deleteWorkout(workoutTemplateId: workoutId)
    }
    deletions += 1
    dismiss()
  }
}

private struct RoundButton: View {
  /// O círculo cresce com o texto, e o ícone cresce junto dentro dele. Os dois
  /// param no primeiro tamanho de acessibilidade, que já é o dobro do padrão.
  @ScaledMetric(relativeTo: .body) private var side = 44.0
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
        .frame(width: side, height: side)
        .overlay {
          Image(systemName: systemImage)
            .font(.system(.body, weight: .semibold))
            .foregroundStyle(ink)
            .contentTransition(.symbolEffect(.replace))
            .offset(x: nudge)
        }
    }
    .buttonStyle(StudyPressStyle())
    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    .accessibilityLabel(label)
  }
}

/// Um ponto por passo, e o passo atual numa cápsula com o nome. Mostra quantos
/// faltam, e tocar num ponto pula direto para aquele passo.
private struct StepDots: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let current: EditorStep
  let go: (EditorStep) -> Void

  var body: some View {
    HStack(spacing: 2) {
      ForEach(EditorStep.allCases, id: \.self) { step in
        if step == current {
          Text(step.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, Space.m)
            .frame(minHeight: 28)
            .background(Color.ink, in: .capsule)
            .accessibilityAddTraits(.isHeader)
            .transition(.opacity)
        } else {
          Button { go(step) } label: {
            Circle()
              .fill(Color.mutedInk.opacity(0.3))
              .frame(width: 8, height: 8)
              .frame(width: 22, height: 44)
              .contentShape(.rect)
          }
          .buttonStyle(StudyPressStyle())
          .accessibilityLabel(step.title)
          .accessibilityHint("ir para o passo")
        }
      }
    }
    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    .animation(Motion.resolve(Motion.tap, reduceMotion), value: current)
  }
}

/// A prévia fora do passo da cor: a amostra e o nome numa linha de 56 pt, para
/// sobrar tela para os campos e a lista.
private struct WorkoutPreviewRow: View {
  let name: String
  let tone: WorkoutTone

  var body: some View {
    HStack(spacing: Space.m) {
      RoundedRectangle(cornerRadius: 10)
        .fill(tone.top)
        .frame(width: 32, height: 32)
      Text(name)
        .font(.headline.weight(.semibold))
        .foregroundStyle(Color.ink)
        .lineLimit(1)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, Space.m)
    .frame(height: 56)
    .fieldSurface()
    .accessibilityHidden(true)
  }
}

private struct IdentityStep: View {
  private enum Field { case name, focus }
  @Binding var draft: WorkoutDraft
  @FocusState private var focused: Field?

  var body: some View {
    VStack(spacing: Space.m) {
      EditorField(label: "nome", isFilled: !draft.name.isEmpty) {
        TextField("nome", text: $draft.name)
          .focused($focused, equals: .name)
          .submitLabel(.next)
          .onSubmit { focused = .focus }
      }
      EditorField(label: "foco", isFilled: !draft.focus.isEmpty) {
        // Cabem 140 letras; numa linha só o começo rolava para fora da vista.
        TextField("foco", text: $draft.focus, axis: .vertical)
          .lineLimit(1...3)
          .focused($focused, equals: .focus)
          .submitLabel(.done)
      }
    }
    .padding(Space.l)
    .onChange(of: draft.name) { _, new in
      let cut = new.cut(to: Limits.workoutNameLength)
      if cut != new { draft.name = cut }
    }
    .onChange(of: draft.focus) { _, new in
      // No campo de várias linhas o "concluído" do teclado vira quebra de
      // linha. Ela sai do texto e fecha o teclado, como no campo de uma linha.
      let typedReturn = new.contains("\n")
      let cut = new.replacingOccurrences(of: "\n", with: "").cut(to: Limits.workoutFocusLength)
      if cut != new { draft.focus = cut }
      if typedReturn { focused = nil }
    }
    .task { if draft.name.isEmpty { focused = .name } }
  }
}

/// O campo branco de canto redondo que o resto do app usa fora do `Form`.
/// Preenchido, o placeholder some, e o rótulo pequeno em cima diz qual é o
/// campo.
private struct EditorField<Content: View>: View {
  let label: String
  let isFilled: Bool
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      if isFilled {
        Text(label)
          .font(.caption)
          .foregroundStyle(Color.mutedInk)
          .accessibilityHidden(true)
      }
      content
    }
    .font(.body)
    .padding(.horizontal, Space.l)
    .padding(.vertical, isFilled ? 6 : 0)
    .frame(minHeight: 52, alignment: .leading)
    .fieldSurface()
  }
}

private struct ExercisesStep: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  #if os(iOS)
  @Environment(\.editMode) private var editMode
  #endif
  @State private var isPickingExercise = false
  /// Quantos exercícios havia ao abrir o seletor. O primeiro depois desse
  /// índice é o que abre e recebe a rolagem quando o seletor fecha.
  @State private var countBeforePick = 0
  @State private var drops = 0
  @State private var confirmDelete = false
  /// Só um exercício aberto por vez; os outros ficam na linha resumida.
  @State private var openExercise: String?
  @Binding var exercises: [PlanExercise]
  @Binding var exerciseInfo: [String: ExerciseCatalogItem]
  let catalog: [ExerciseCatalogItem]
  let workoutId: String?
  let workoutName: String
  let isSaving: Bool
  let scroll: ScrollViewProxy
  let onDelete: () -> Void

  private var isOrganizing: Bool {
    #if os(iOS)
    editMode?.wrappedValue.isEditing == true
    #else
    false
    #endif
  }

  private var editAnimation: Animation {
    Motion.resolve(Motion.confirm, reduceMotion)
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
            isExpanded: openExercise == exerciseId,
            onToggle: {
              withAnimation(editAnimation) {
                openExercise = openExercise == exerciseId ? nil : exerciseId
              }
            },
            onRemove: {
              withAnimation(editAnimation) {
                exercises.removeAll { $0.exerciseId == exerciseId }
              }
            },
            onFieldFocus: { reveal(exerciseId) })
            // Sem o modo organizar, a linha aberta levantada pelo toque longo
            // tem uns 500 pt e cobre as vizinhas. Só as fechadas arrastam.
            .deleteDisabled(isSaving || isOrganizing)
            .moveDisabled(isSaving || (!isOrganizing && openExercise == exerciseId))
        }
        .onDelete { offsets in
          withAnimation(editAnimation) { exercises.remove(atOffsets: offsets) }
        }
        .onMove { offsets, destination in
          withAnimation(editAnimation) {
            exercises.move(fromOffsets: offsets, toOffset: destination)
          }
          drops += 1
        }

        if exercises.isEmpty {
          ContentUnavailableView {
            Label("sem exercícios", systemImage: "dumbbell")
          } actions: {
            Button("adicionar", systemImage: "plus", action: pickExercises)
              .buttonStyle(.glassProminent)
          }
          .listRowBackground(Color.clear)
        } else if !isOrganizing {
          let isFull = exercises.count >= Limits.exerciseCount.upperBound
          Button("adicionar", systemImage: "plus", action: pickExercises)
            .disabled(isFull)
            .accessibilityHint(isFull ? "limite de \(Limits.exerciseCount.upperBound) exercícios" : "")
        }
      }

      if workoutId != nil, !isOrganizing {
        Section {
          Button("apagar treino", systemImage: "trash", role: .destructive) {
            confirmDelete = true
          }
          // O papel pinta o texto, e o ícone pegava o tint verde da lista.
          .tint(Color.danger)
          .disabled(isSaving)
          .deleteWorkoutConfirmation(isPresented: $confirmDelete, name: workoutName, onDelete: onDelete)
        }
      }
    }
    .scrollContentBackground(.hidden)
    // O recuo padrão da primeira seção deixava uns 45 pt vazios sob o título.
    .listSectionSpacing(.compact)
    .contentMargins(.top, Space.s, for: .scrollContent)
    .sensoryFeedback(.impact(weight: .light), trigger: drops)
    .sensoryFeedback(.impact(weight: .light), trigger: exercises.count) { old, new in new < old }
    .sheet(isPresented: $isPickingExercise, onDismiss: revealPicked) {
      ExercisePicker(
        catalog: catalog, chosen: Set(exercises.map(\.exerciseId)),
        onPick: { item in
        let known = catalog.contains(where: { $0.id == item.id })
        exerciseInfo[item.id] = item
        exercises.append(
          PlanExercise(
            exerciseId: item.id, prepSets: 2, workSets: 2, repsMin: 8, repsMax: 12,
            workToFailure: true, startingWeightKg: store.dashboard?.loadKg(exerciseId: item.id) ?? 0,
            name: known ? nil : item.name,
            muscleGroup: known ? nil : item.muscleGroup,
            equipment: known ? nil : item.equipment,
            imageUrl: known ? nil : item.imageUrl))
        },
        onUnpick: { id in exercises.removeAll { $0.exerciseId == id } })
    }
  }

  /// O teclado sobe e a barra dele ainda tira 48 pt do fim da lista depois
  /// que a lista já rolou até o campo. Rolar de novo, com tudo assentado, põe o
  /// fim da linha aberta rente à barra, e o campo de carga fica acima dela.
  private func reveal(_ exerciseId: String) {
    Task {
      try? await Task.sleep(for: .milliseconds(350))
      withAnimation(Motion.resolve(Motion.expand, reduceMotion)) {
        scroll.scrollTo(exerciseId, anchor: .bottom)
      }
    }
  }

  private func pickExercises() {
    countBeforePick = exercises.count
    isPickingExercise = true
  }

  /// O seletor fica aberto para escolher vários. Quando fecha, o primeiro da
  /// leva abre e a lista rola até ele, porque com cinco ou mais ele nasce fora
  /// da tela.
  ///
  /// Com mais de dois de uma vez, abrir e rolar animados passava por um quadro
  /// com a lista quase em branco, então a leva grande chega sem animação.
  private func revealPicked() {
    guard exercises.indices.contains(countBeforePick) else { return }
    let first = exercises[countBeforePick].exerciseId
    let isBatch = exercises.count - countBeforePick > 2
    withAnimation(isBatch ? nil : Motion.resolve(Motion.expand, reduceMotion)) {
      openExercise = first
      scroll.scrollTo(first, anchor: .top)
    }
  }
}

/// Os sete dias num toque cada, de segunda a domingo. O aviso embaixo
/// diz quando um dia marcado sai de outro treino, antes de salvar.
struct WorkoutDaysSection: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.dynamicTypeSize) private var textSize
  @Binding var selection: Set<Int>
  let workoutId: String?

  private var orderedWeekdays: [Int] {
    let first = Calendar.trainingWeek.firstWeekday - 1
    return (0..<7).map { (first + $0) % 7 }
  }

  var body: some View {
    let owners = WeekdayOwners(plan: store.weekPlan, excluding: workoutId)
    let handoffs = owners.handoffs(to: selection)
    VStack(alignment: .leading, spacing: Space.m) {
      // Nos tamanhos de acessibilidade sete círculos não cabem numa linha. Em
      // quatro colunas cada círculo cresce com o texto e a semana quebra em duas.
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: Space.xs),
                       count: textSize.isAccessibilitySize ? 4 : 7),
        spacing: 8
      ) {
        ForEach(orderedWeekdays, id: \.self) { day in
          WeekdayToggle(
            shortName: planWeekdaysShort[day], fullName: planWeekdays[day],
            isOn: selection.contains(day), owner: owners[day]
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
/// animação a cada toque deixa a fileira lenta. O ponto embaixo do dia livre
/// tem a cor do treino que já usa aquele dia.
private struct WeekdayToggle: View {
  @Environment(\.dynamicTypeSize) private var textSize
  let shortName: String
  let fullName: String
  let isOn: Bool
  let owner: WeekPlanItem?
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 4) {
        mark
        Circle()
          .fill(owner.map { $0.tone.top } ?? .clear)
          .frame(width: 6, height: 6)
          .opacity(isOn ? 0 : 1)
      }
      .contentShape(.rect)
    }
    .buttonStyle(StudyPressStyle())
    .accessibilityLabel(fullName)
    .accessibilityValue(owner.map { "de \($0.name)" } ?? "")
    .accessibilityAddTraits(isOn ? .isSelected : [])
  }

  /// Círculo no tamanho padrão. Nos de acessibilidade o texto não cabe num
  /// círculo da largura da coluna, e a marca vira cápsula.
  @ViewBuilder private var mark: some View {
    let label = Text(shortName)
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(isOn ? .white : Color.ink)
      .lineLimit(1)
      .minimumScaleFactor(0.5)
    if textSize.isAccessibilitySize {
      label
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.s)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(isOn ? Color.ink : Color.surfaceMuted, in: .capsule)
    } else {
      Circle()
        .fill(isOn ? Color.ink : Color.surfaceMuted)
        .overlay { label.offset(y: -1).padding(Space.xs) }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity, minHeight: 44)
    }
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
  #Preview("Editor, nome") { WorkoutEditorPreview(step: .identidade) }
  #Preview("Editor, cor") { WorkoutEditorPreview(step: .cor) }
  #Preview("Editor, dias") { WorkoutEditorPreview(step: .dias) }
  #Preview("Editor, exercícios") { WorkoutEditorPreview(step: .exercicios) }
  #Preview("Card de pasta") {
    HStack(spacing: Space.m) {
      WorkoutFolderCard(name: "peito e tríceps", tone: .at(0), weekdays: [1, 4], exerciseCount: 6)
      WorkoutFolderCard(name: "pernas", tone: .at(1), weekdays: [])
    }
    .padding(Space.l)
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
