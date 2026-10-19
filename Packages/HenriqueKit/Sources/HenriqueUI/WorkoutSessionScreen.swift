import HenriqueCore
import SwiftUI
#if canImport(UIKit)
  import UIKit
#endif

/// Quanto do treino já foi. Derivado do painel a cada pintura, então a sessão e
/// a tela de hoje nunca mostram contagens diferentes.
struct SessionProgress: Equatable {
  let done: Int
  let total: Int
  /// O peso das séries valendo já marcadas. O aquecimento fica fora, como no
  /// volume do servidor, senão o número da sessão nunca bate com o do progresso.
  let volumeKg: Double

  init(_ workout: WorkoutSummary) {
    done = workout.completedWorkSetCount
    total = workout.workSetCount
    volumeKg = workout.exercises.reduce(0) { $0 + workVolumeKg($1.sets.work) }
  }

  var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
  var percent: Int { Int((fraction * 100).rounded()) }
}

/// O primeiro exercício com série valendo em aberto. Continuar um treino pela
/// metade deve cair onde ele parou, não no começo.
func firstOpenExercise(in workout: WorkoutSummary) -> Int {
  workout.exercises.firstIndex { !$0.isComplete } ?? max(0, workout.exercises.count - 1)
}

/// O que a série de hoje tem a bater. Vem do último treino deste exercício, casada
/// pelo índice, porque comparar a terceira com a terceira é o que diz se progrediu.
/// O servidor antigo não manda `sets`: aí a carga é a maior e as repetições vão
/// pela posição.
func previousLabel(_ previous: PreviousWorkSets?, index: Int) -> String? {
  guard let previous else { return nil }
  if previous.sets != nil {
    return previous.set(index).map { "\(Formatting.trim($0.weightKg)) × \($0.reps)" }
  }
  guard previous.reps.indices.contains(index - 1) else { return nil }
  return "\(Formatting.trim(previous.weightKg)) × \(previous.reps[index - 1])"
}

/// A melhor série da última vez, a mais pesada e no empate a de mais repetições.
func previousTop(_ previous: PreviousWorkSets?) -> (weightKg: Double, reps: Int)? {
  guard let previous else { return nil }
  if let top = previous.sets?.max(by: { ($0.weightKg, $0.reps) < ($1.weightKg, $1.reps) }) {
    return (top.weightKg, top.reps)
  }
  return previous.reps.first.map { (previous.weightKg, $0) }
}

/// O mesmo para o aquecimento, que guarda carga por série.
func previousLabel(_ previous: PreviousPrepSets?, index: Int) -> String? {
  guard let set = previous?.set(index) else { return nil }
  return "\(Formatting.trim(set.weightKg)) × \(set.reps)"
}

/// Modo treino: o treino inteiro numa lista, com um exercício aberto por vez. Pular
/// o aparelho ocupado e voltar depois é o caso normal na academia, e a lista deixa
/// fazer isso sem sair da tela.
struct WorkoutSessionScreen: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.accent) private var accent
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var typeSize
  @ScaledMetric(relativeTo: .title) private var nameSize = 27.0
  @ScaledMetric(relativeTo: .body) private var collapsedNameSize = 17.0
  @ScaledMetric(relativeTo: .footnote) private var metaSize = 12.5
  @ScaledMetric(relativeTo: .footnote) private var noteSize = 13.5
  @ScaledMetric(relativeTo: .subheadline) private var actionSize = 14.0
  @ScaledMetric(relativeTo: .subheadline) private var addSetSize = 14.5
  @ScaledMetric(relativeTo: .subheadline) private var addExerciseSize = 15.0
  @State private var open: String?
  /// O exercício que acabou de fechar, ainda aberto para o visto da última série
  /// aparecer antes de o próximo tomar o lugar.
  @State private var holding: String?
  @State private var entered = false
  @State private var adding = false
  /// O exercício cuja contagem de séries espera o servidor.
  @State private var changingCount: String?
  @State private var addingExercise = false
  /// Com o teclado aberto o cartão do descanso subia junto e comia a lista.
  @State private var keyboardUp = false
  @State private var confirmingFinish = false
  @State private var recap: RecapPresentation?
  /// O resumo veio do "encerrar": fechar ele fecha a sessão junto, porque o
  /// treino acabou. O resumo reaberto depois só fecha a si mesmo.
  @State private var closesAfterRecap = false
  /// O texto em edição por exercício. Só existe enquanto o campo está sendo
  /// digitado; salvo, a fonte volta a ser o painel.
  @State private var noteDrafts: [String: String] = [:]
  @FocusState private var noteFocus: String?
  @State private var history: ExerciseHistoryTarget?
  let onClose: () -> Void

  private var hairline: Color { Color.ink.opacity(0.08) }
  private var glide: Animation { Motion.resolve(Motion.glide, reduceMotion) }

  var body: some View {
    // A tela abre em tela cheia, e sem uma pilha de navegação o iOS não desenha a
    // barra de teclado. Sem ela o teclado numérico da carga não tinha como fechar,
    // porque ele não tem tecla de retorno. A barra de navegação fica escondida.
    NavigationStack {
      screen
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }
  }

  private var screen: some View {
    ZStack {
      Color.canvas.ignoresSafeArea()
      if let data = store.dashboard, let workout = data.workout {
        let progress = SessionProgress(workout)
        let openId = openExercise(in: workout)
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(spacing: Space.m) {
              ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { index, exercise in
                Group {
                  if openId == exercise.id {
                    card(exercise: exercise, date: data.date, templateId: workout.id)
                      .transition(.opacity)
                  } else {
                    collapsed(exercise: exercise)
                      .transition(.opacity)
                  }
                }
                .revealEntrance(index: index + 1, shown: entered)
              }
              addExerciseButton
                .revealEntrance(index: workout.exercises.count + 1, shown: entered)
            }
            .padding(.horizontal, Space.l).padding(.top, Space.l)
            .padding(.bottom, Space.page)
          }
          .scrollDismissesKeyboard(.interactively)
          .safeAreaInset(edge: .top, spacing: 0) {
            top(workout: workout, progress: progress, date: data.date)
              .revealEntrance(index: 0, shown: entered)
          }
          // Inset, e não overlay: a lista encolhe junto com a barra e a última
          // série continua alcançável com o descanso aberto.
          .safeAreaInset(edge: .bottom, spacing: 0) {
            if let rest = store.rest, rest.key.date == data.date, !keyboardUp {
              RestTimerBar(
                rest: rest, next: store.nextSet(after: rest),
                onAdjust: { store.adjustRest(by: $0) }, onDismiss: { store.endRest() }
              )
              .padding(.horizontal, 12).padding(.bottom, 12)
              .transition(.move(edge: .bottom).combined(with: .opacity))
            }
          }
          .animation(glide, value: store.rest == nil)
          // O cartão do descanso encolhe a área da lista. Sem rolar, o "+ série" e
          // o próximo exercício ficavam atrás dele.
          .onChange(of: store.rest?.startedAt) { _, started in
            guard started != nil, let rest = store.rest, let openId else { return }
            let next = store.nextSet(after: rest)
            // O exercício acabou e o próximo abre depois da espera, que rola até ele.
            if let next, next.exerciseId != openId { return }
            Task {
              try? await Task.sleep(for: .milliseconds(120))
              withAnimation(glide) {
                if let next {
                  proxy.scrollTo(setRowID(next.exerciseId, next.kind, next.index), anchor: .center)
                } else {
                  proxy.scrollTo(openId, anchor: .bottom)
                }
              }
            }
          }
          .onChange(of: OpenExerciseState(openId, in: workout)) { old, new in
            guard let id = new.id, old.id == id, !old.complete, new.complete else { return }
            hold(id, proxy: proxy)
          }
        }
        .animation(Motion.resolve(Motion.subtleEntrance, reduceMotion), value: openId)
        // As peças só começam a aparecer quando o cartão já cresceu o bastante
        // para elas caberem dentro dele.
        .task {
          if !reduceMotion { try? await Task.sleep(for: .milliseconds(180)) }
          entered = true
        }
        .onChange(of: noteFocus) { old, _ in
          guard let old, let exercise = workout.exercises.first(where: { $0.id == old }) else { return }
          saveNote(exercise: exercise, date: data.date, templateId: workout.id)
        }
        .confirmationDialog(
          openSetsQuestion(progress.total - progress.done),
          isPresented: $confirmingFinish, titleVisibility: .visible
        ) {
          Button("encerrar treino", role: .destructive) { finish() }
          Button("continuar treinando", role: .cancel) {}
        }
        .sheet(item: $recap, onDismiss: { if closesAfterRecap { onClose() } }) { presentation in
          LiveWorkoutRecap(date: presentation.date, opened: presentation.recap)
        }
        .sheet(isPresented: $adding) {
          SessionExercisePicker(
            catalog: data.exerciseCatalog, chosen: Set(workout.exercises.map(\.id))
          ) { item in
            addingExercise = true
            Task {
              await store.addExercise(
                .init(date: data.date, workoutTemplateId: workout.id, exerciseId: item.id))
              addingExercise = false
              open = item.id
            }
          }
        }
      }
    }
    .onChange(of: store.dashboard?.workout == nil, initial: true) { _, gone in
      if gone { onClose() }
    }
    #if canImport(UIKit)
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
      keyboardUp = true
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
      keyboardUp = false
    }
    #endif
    .onAppear { RestAlarmPresenter.shared.sessionOnScreen = true }
    .onDisappear { RestAlarmPresenter.shared.sessionOnScreen = false }
    .exerciseHistorySheet(item: $history)
  }

  private func top(workout: WorkoutSummary, progress: SessionProgress, date: CalendarDate) -> some View {
    let closedAt = store.finishedAt(workout.id, on: date)
    let complete = progress.total > 0 && progress.done >= progress.total
    return VStack(spacing: 14) {
      HStack(spacing: Space.m) {
        Button(action: onClose) {
          Image(systemName: "chevron.down")
            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.ink)
            .frame(width: 44, height: 44)
            .background(.white, in: .circle)
            .overlay(Circle().strokeBorder(hairline))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("minimizar treino")
        .accessibilityIdentifier("sessao.fechar")
        SessionClock(
          timing: WorkoutSessionTiming(
            workout, anchor: store.startedAt(workout.id, on: date), finishedAt: closedAt),
          name: workout.name)
          .frame(maxWidth: .infinity, alignment: .leading)
        Button {
          if closedAt != nil || complete {
            finish()
          } else {
            confirmingFinish = true
          }
        } label: {
          Label(
            closedAt == nil ? "encerrar" : "resumo",
            systemImage: closedAt == nil ? "flag.checkered" : "list.bullet.rectangle"
          )
            .labelStyle(.titleAndIcon)
            .font(.system(size: actionSize, weight: .medium))
            .foregroundStyle(complete ? Color.white : Color.ink)
            .padding(.horizontal, 16).frame(minHeight: 44)
            .background(complete ? accent.base : .white, in: .capsule)
            .overlay(Capsule().strokeBorder(complete ? .clear : hairline))
            .animation(glide, value: complete)
        }
        .buttonStyle(PressScaleStyle())
        .sensoryFeedback(.success, trigger: complete) { old, new in !old && new }
        .accessibilityIdentifier("sessao.encerrar")
      }
      VStack(spacing: 6) {
        HStack(spacing: 0) {
          Text("\(progress.done)")
            .contentTransition(.numericText(value: Double(progress.done)))
            .animation(reduceMotion ? nil : Motion.roll, value: progress.done)
          Text(" de \(progress.total)")
          Spacer()
          if progress.volumeKg > 0 {
            Text("\(Formatting.trim(progress.volumeKg.rounded())) kg")
              .contentTransition(.numericText(value: progress.volumeKg))
              .animation(reduceMotion ? nil : Motion.roll, value: progress.volumeKg)
          }
        }
        .font(.system(size: metaSize)).monospacedDigit().foregroundStyle(Color.mutedInk)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(progress.done) de \(progress.total) séries valendo")
        .accessibilityValue(progress.volumeKg > 0
          ? "\(Formatting.trim(progress.volumeKg.rounded())) quilos de volume" : "")
        SyncStatusLine()
        GeometryReader { geo in
          Capsule().fill(Color.surfaceMuted)
            .overlay(alignment: .leading) {
              Capsule().fill(accent.signal)
                // Zero séries é barra vazia. A ponta mínima existe para uma
                // série feita não sumir, não para fingir progresso que não há.
                .frame(width: progress.done == 0 ? 0 : max(6, geo.size.width * progress.fraction))
                .animation(glide, value: progress.done)
            }
        }
        .frame(height: 8)
      }
    }
    .padding(.top, 4).padding(.horizontal, 16).padding(.bottom, 12)
    .background {
      // A versão possível do `backdrop-filter: blur(20px)` do board. O material
      // desfoca o que rola por baixo e a tinta do papel devolve a cor.
      ZStack {
        Rectangle().fill(.ultraThinMaterial)
        Color.canvas.opacity(0.86)
      }
      .ignoresSafeArea(edges: .top)
    }
    .overlay(alignment: .bottom) { Divider() }
  }

  /// O exercício fechado. Diz o que falta nele sem abrir, que é o que decide se o
  /// próximo aparelho vale a caminhada.
  private func collapsed(exercise: DashboardExercise) -> some View {
    Button {
      holding = nil
      open = exercise.id
    } label: {
      HStack(spacing: 14) {
        // O board pinta a barra com a cor do treino. O modelo não tem cor por
        // exercício, então ela continua dizendo só se o exercício acabou.
        Capsule().fill(exercise.isComplete ? accent.base : Color.ink.opacity(0.12))
          .frame(width: 4, height: 36)
        VStack(alignment: .leading, spacing: 2) {
          Text(exercise.name.lowercased())
            .font(.system(size: collapsedNameSize, weight: .medium)).tracking(collapsedNameSize * -0.015)
            .foregroundStyle(Color.ink).lineLimit(1)
          // A carga de hoje, a mesma do cartão de hoje. A última vez fica na
          // coluna "anterior" do cartão aberto e no VoiceOver.
          if exercise.prescription.startingWeightKg > 0 {
            Text(weightLabel(exercise.prescription.startingWeightKg))
              .font(.system(size: 13)).monospacedDigit().foregroundStyle(Color.mutedInk).lineLimit(1)
          }
        }
        Spacer(minLength: Space.s)
        if exercise.isComplete {
          Image(systemName: "checkmark.circle.fill")
            .font(.title3).foregroundStyle(accent.base)
        } else {
          Text("\(exercise.sets.completedWorkCount)/\(exercise.prescription.workSets)")
            .font(.system(.caption, design: .monospaced)).foregroundStyle(Color.mutedInk)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.surfaceMuted, in: .capsule)
        }
      }
      .padding(.horizontal, 18).padding(.vertical, 16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .paperCard(radius: Radius.tile)
      .contentShape(.rect)
    }
    .buttonStyle(PressScaleStyle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(exercise.name.lowercased())
    .accessibilityValue(spokenSummary(exercise))
    .accessibilityAddTraits(.isButton)
    .accessibilityIdentifier("sessao.exercicio.\(exercise.id)")
  }

  private func spokenSummary(_ exercise: DashboardExercise) -> String {
    let load = exercise.prescription.startingWeightKg
    let count = "\(exercise.sets.completedWorkCount) de \(exercise.prescription.workSets) séries"
      + (load > 0 ? ", \(Formatting.trim(load)) quilos" : "")
    guard let top = previousTop(exercise.previous) else { return count }
    return "\(count), \(Formatting.trim(top.weightKg)) quilos por \(top.reps) da última vez"
  }

  private func card(exercise: DashboardExercise, date: CalendarDate, templateId: String) -> some View {
    let next = NextSet.next(in: exercise)
    return VStack(alignment: .leading, spacing: 0) {
      if exercise.isFromSession {
        onlyTodayChip(exercise: exercise, date: date, templateId: templateId)
          .padding(.bottom, 12)
      }
      HStack(alignment: .top, spacing: Space.s) {
        Text(exercise.name.lowercased())
          .font(.system(size: nameSize, weight: .semibold)).tracking(nameSize * -0.045)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
        IconButton(title: "histórico", systemImage: "chart.line.uptrend.xyaxis") {
          history = ExerciseHistoryTarget(id: exercise.id, name: exercise.name)
        }
        .tint(Color.mutedInk)
        .padding(.top, -6).padding(.trailing, -10)
        .accessibilityIdentifier("sessao.historico.\(exercise.id)")
      }
      restPicker(exercise).padding(.top, 8)
      header.padding(.top, 18).padding(.bottom, 8)
      VStack(spacing: 2) {
        ForEach(exercise.sets.prep) { set in
          row(exercise: exercise, date: date, templateId: templateId, kind: .prep,
            index: set.index, weight: set.weightKg, reps: set.reps, done: set.isDone, failure: false,
            next: next)
        }
        ForEach(exercise.sets.work) { set in
          row(exercise: exercise, date: date, templateId: templateId, kind: .work,
            index: set.index, weight: set.weightKg, reps: set.reps, done: set.isDone,
            failure: set.toFailure, next: next)
        }
      }
      .animation(Motion.resolve(Motion.expand, reduceMotion), value: exercise.sets.work.count)
      setCountRow(exercise: exercise, date: date, templateId: templateId).padding(.top, 10)
      noteField(exercise: exercise, date: date, templateId: templateId).padding(.top, 12)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
    // Sem `Radius.concentric` aqui. As linhas de série não são ladrilhos
    // embutidos, são fatias rentes à coluna de texto, então o raio de fora não
    // sai do de dentro.
    .paperCard(radius: 28)
  }

  private func restPicker(_ exercise: DashboardExercise) -> some View {
    Menu {
      Picker("descanso", selection: restBinding(exercise.id)) {
        ForEach(restOptions, id: \.self) { seconds in
          Text(restClock(TimeInterval(seconds))).tag(seconds)
        }
      }
    } label: {
      HStack(spacing: 5) {
        Image(systemName: "clock").font(.caption)
        Text("descanso \(restClock(TimeInterval(store.restSeconds(for: exercise.id))))")
      }
      .font(.system(size: metaSize)).monospacedDigit().foregroundStyle(Color.ink)
      .padding(.horizontal, 11).padding(.vertical, 5)
      .background(Color.surfaceMuted, in: .capsule)
      .touchTarget()
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("sessao.descanso.\(exercise.id)")
  }

  /// As mesmas cinco colunas da linha, com as mesmas larguras, para o título
  /// cair em cima do que nomeia.
  private var header: some View {
    HStack(spacing: 8) {
      Text("#").frame(width: 30)
      if typeSize.isAccessibilitySize {
        Spacer(minLength: 0)
      } else {
        Text("anterior").frame(maxWidth: .infinity, alignment: .leading)
      }
      Text("kg").frame(minWidth: 56, maxWidth: 66)
      Text("reps").frame(minWidth: 56, maxWidth: 66)
      Color.clear.frame(width: SetRowScale.session.check, height: 1)
    }
    .padding(.horizontal, 2)
    .font(.system(.caption2, design: .monospaced)).foregroundStyle(Color.mutedInk)
    .accessibilityHidden(true)
  }

  private func row(
    exercise: DashboardExercise, date: CalendarDate, templateId: String, kind: SetKind,
    index: Int, weight: Double, reps: Int, done: Bool, failure: Bool, next: NextSet?
  ) -> some View {
    let isNext = next?.kind == kind && next?.index == index
    return TrainingSetRow(
      key: SetKey(date: date, templateId: templateId, exerciseId: exercise.id, kind: kind, index: index),
      weight: weight, repetitions: reps, done: done, failure: failure, scale: .session,
      isNext: isNext,
      previous: kind == .prep
        ? previousLabel(exercise.previousPrep, index: index)
        : previousLabel(exercise.previous, index: index),
      reference: setReference(exercise, kind: kind, index: index))
  }

  /// Mais ou menos uma série valendo. Tirar só aparece enquanto a última ainda
  /// está em aberto, porque o servidor não esconde série feita, e o botão sumir
  /// é mais honesto do que pedir e receber a mesma contagem de volta.
  private func setCountRow(exercise: DashboardExercise, date: CalendarDate, templateId: String) -> some View {
    let count = exercise.sets.work.count
    let canRemove = count > Limits.workSets.lowerBound && exercise.sets.work.last?.isDone == false
    let changing = changingCount == exercise.id
    return HStack(spacing: Space.s) {
      Button {
        changeCount(.init(date: date, workoutTemplateId: templateId,
          exerciseId: exercise.id, kind: .work, count: count + 1))
      } label: {
        Group {
          if changing {
            ProgressView().controlSize(.small)
          } else {
            Label("série", systemImage: "plus").labelStyle(.titleAndIcon)
          }
        }
          .font(.system(size: addSetSize, weight: .medium)).foregroundStyle(accent.base)
          .frame(maxWidth: .infinity, minHeight: 22)
          .padding(11)
          .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(hairline))
      }
      .buttonStyle(PressScaleStyle())
      .disabled(count >= Limits.workSets.upperBound || changing)
      .accessibilityLabel("adicionar série")
      .accessibilityIdentifier("sessao.adicionar-serie.\(exercise.id)")
      if canRemove {
        Button {
          changeCount(.init(date: date, workoutTemplateId: templateId,
            exerciseId: exercise.id, kind: .work, count: count - 1))
        } label: {
          Image(systemName: "minus")
            .font(.system(size: 15, weight: .medium)).foregroundStyle(Color.mutedInk)
            .frame(width: 44, height: 44)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(changing)
        .accessibilityLabel("tirar uma série")
        .accessibilityIdentifier("sessao.remover-serie.\(exercise.id)")
      }
    }
    .sensoryFeedback(.impact(weight: .light), trigger: count)
  }

  /// A contagem só muda quando o servidor responde, que no wi-fi da academia
  /// leva segundos; o botão fica girando até lá.
  private func changeCount(_ input: SetCountInput) {
    changingCount = input.exerciseId
    Task {
      await store.setCount(input)
      if changingCount == input.exerciseId { changingCount = nil }
    }
  }

  private func noteField(exercise: DashboardExercise, date: CalendarDate, templateId: String) -> some View {
    HStack(alignment: .top, spacing: 9) {
      Image(systemName: "text.alignleft")
        .font(.system(size: 15)).foregroundStyle(Color.mutedInk)
        .padding(.top, 2)
      TextField("anotação", text: noteBinding(exercise), axis: .vertical)
        .lineLimit(1...2)
        .font(.system(size: noteSize)).foregroundStyle(Color.mutedInk)
        .focused($noteFocus, equals: exercise.id)
        .submitLabel(.done)
        .onSubmit { noteFocus = nil }
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #endif
        .accessibilityLabel("anotação")
        .accessibilityIdentifier("sessao.nota.\(exercise.id)")
        // Num campo de mais de uma linha o retorno quebra linha em vez de encerrar,
        // então sem a barra a anotação prende o teclado aberto.
        .keyboardDone()
    }
  }

  private func noteBinding(_ exercise: DashboardExercise) -> Binding<String> {
    Binding(
      get: { noteDrafts[exercise.id] ?? exercise.note ?? "" },
      set: { noteDrafts[exercise.id] = $0 })
  }

  private func saveNote(exercise: DashboardExercise, date: CalendarDate, templateId: String) {
    guard let draft = noteDrafts.removeValue(forKey: exercise.id) else { return }
    let input = SetExerciseNoteInput(
      date: date, workoutTemplateId: templateId, exerciseId: exercise.id, note: draft)
    guard input.note != exercise.note else { return }
    Task { await store.setNote(input) }
  }

  /// A marca de "só hoje" é também o menu para tirar o exercício. O servidor
  /// recusa se já houver série feita, e a recusa chega pelo banner da store.
  private func onlyTodayChip(exercise: DashboardExercise, date: CalendarDate, templateId: String) -> some View {
    Menu {
      Button("tirar de hoje", systemImage: "minus.circle", role: .destructive) {
        Task {
          await store.removeExercise(
            .init(date: date, workoutTemplateId: templateId, exerciseId: exercise.id))
        }
      }
      .accessibilityIdentifier("sessao.remover-exercicio.\(exercise.id)")
    } label: {
      Label("só hoje", systemImage: "chevron.down")
        .labelStyle(.titleAndIcon)
        .font(.caption.weight(.medium)).foregroundStyle(Color.mutedInk)
        .padding(.horizontal, 11).padding(.vertical, 5)
        .background(Color.surfaceMuted, in: .capsule)
        .touchTarget()
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("sessao.so-hoje.\(exercise.id)")
  }

  private var addExerciseButton: some View {
    Button {
      adding = true
    } label: {
      Group {
        if addingExercise {
          ProgressView().controlSize(.small)
        } else {
          Label("adicionar exercício", systemImage: "plus.circle").labelStyle(.titleAndIcon)
        }
      }
        .font(.system(size: addExerciseSize)).foregroundStyle(Color.mutedInk)
        .frame(maxWidth: .infinity, minHeight: 22)
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: Radius.row).strokeBorder(hairline))
    }
    .buttonStyle(PressScaleStyle())
    .disabled(addingExercise)
    .accessibilityIdentifier("sessao.adicionar-exercicio")
  }

  private var restOptions: [Int] { [30, 45, 60, 75, 90, 120, 150, 180, 240, 300] }

  private func restBinding(_ exerciseId: String) -> Binding<Int> {
    Binding(
      get: { store.restSeconds(for: exerciseId) },
      set: { store.setRestSeconds($0, for: exerciseId) })
  }

  /// Qual exercício está aberto. `open` guarda só a escolha explícita, e o resto sai do
  /// treino a cada pintura: amarrar isso a `onAppear` deixava a lista toda fechada
  /// quando o painel ainda não tinha chegado na primeira vez que a tela apareceu.
  private func openExercise(in workout: WorkoutSummary) -> String? {
    if let holding, workout.exercises.contains(where: { $0.id == holding }) { return holding }
    if let open, workout.exercises.contains(where: { $0.id == open }) { return open }
    return workout.exercises[safe: firstOpenExercise(in: workout)]?.id
  }

  /// O exercício aberto acabou. A escolha explícita sai junto, senão o cartão
  /// terminado ficava preso aberto pelo resto do treino, e o próximo em aberto
  /// assume depois de o visto aparecer.
  private func hold(_ id: String, proxy: ScrollViewProxy) {
    holding = id
    open = nil
    Task {
      try? await Task.sleep(for: .milliseconds(700))
      guard holding == id else { return }
      holding = nil
      guard let workout = store.dashboard?.workout, let next = openExercise(in: workout), next != id
      else { return }
      try? await Task.sleep(for: .milliseconds(120))
      withAnimation(glide) { proxy.scrollTo(next, anchor: .top) }
    }
  }

  private func openSetsQuestion(_ open: Int) -> String {
    open == 1 ? "encerrar com 1 série em aberto?" : "encerrar com \(open) séries em aberto?"
  }

  /// Encerrar para o relógio e o descanso e mostra o resumo. Já encerrado, o
  /// mesmo botão só reabre o resumo.
  private func finish() {
    guard let data = store.dashboard, let workout = data.workout else { return }
    let wasClosed = store.finishedAt(workout.id, on: data.date) != nil
    if !wasClosed { store.finishWorkout() }
    closesAfterRecap = !wasClosed
    guard let opened = sessionRecap(store, on: data.date) else { return }
    recap = RecapPresentation(date: data.date, recap: opened)
  }
}

/// O exercício aberto e se ele acabou, para notar a última série marcada nele
/// sem confundir com a troca para um exercício que já estava completo.
private struct OpenExerciseState: Equatable {
  let id: String?
  let complete: Bool

  init(_ id: String?, in workout: WorkoutSummary) {
    self.id = id
    complete = workout.exercises.first { $0.id == id }?.isComplete ?? false
  }
}

extension View {
  /// Alvo de toque de 44 pontos em volta de uma pílula baixa, sem empurrar o
  /// que está em volta.
  func touchTarget() -> some View {
    padding(.vertical, 10).contentShape(.rect).padding(.vertical, -10)
  }
}

private struct RecapPresentation: Identifiable {
  let id = UUID()
  let date: CalendarDate
  let recap: WorkoutRecap
}

@MainActor
private func sessionRecap(_ store: AcademiaStore, on date: CalendarDate) -> WorkoutRecap? {
  guard let data = store.dashboard, data.date == date, let workout = data.workout else { return nil }
  let timing = WorkoutSessionTiming(
    workout, anchor: store.startedAt(workout.id, on: date),
    finishedAt: store.finishedAt(workout.id, on: date))
  return WorkoutRecap(workout, timing: timing, records: data.records ?? [], on: date)
}

/// O resumo refeito do painel a cada pintura. O recorde da última série chega
/// com a resposta do servidor, que pode vir depois de a folha abrir.
private struct LiveWorkoutRecap: View {
  @Environment(AcademiaStore.self) private var store
  let date: CalendarDate
  let opened: WorkoutRecap

  var body: some View {
    WorkoutRecapSheet(recap: sessionRecap(store, on: date) ?? opened)
  }
}

extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

/// O relógio do treino, com o ponto que pulsa enquanto a sessão está aberta. Um
/// treino encerrado mostra o tempo parado, sem o ponto.
private struct SessionClock: View {
  @Environment(\.accent) private var accent
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .largeTitle) private var clockSize = 30.0
  let timing: WorkoutSessionTiming?
  let name: String

  var body: some View {
    if let timing, timing.finishedAt == nil {
      // Ancorado no começo, o tick cai quando o segundo vira. A leitura vem 10 ms
      // depois para o arredondamento para baixo não cair em cima da virada.
      TimelineView(.periodic(from: timing.startedAt, by: 1)) { context in
        readout(at: context.date + 0.01, timing: timing, live: true)
      }
    } else if let timing {
      readout(at: .now, timing: timing, live: false)
    } else {
      Text(name.lowercased()).font(.headline.weight(.semibold))
        .accessibilityValue("nenhuma série marcada")
    }
  }

  private func readout(at now: Date, timing: WorkoutSessionTiming, live: Bool) -> some View {
    let seconds = Int(timing.elapsed(at: now))
    let time = Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3600
      ? .hourMinuteSecond : .minuteSecond(padMinuteToLength: 2)))
    let start = timing.startedAt.formatted(.dateTime.hour().minute())
    return VStack(alignment: .leading, spacing: 1) {
      HStack(spacing: 8) {
        if live {
          Circle().fill(accent.signal).frame(width: 8, height: 8)
            .offset(y: 1)
            .modifier(Pulse(active: live))
        }
        Text(time)
          .font(.system(size: clockSize, weight: .semibold)).monospacedDigit()
          .tracking(clockSize * -0.05)
          .contentTransition(.numericText(value: Double(seconds)))
          .animation(reduceMotion ? nil : Motion.roll, value: seconds)
      }
      Text(name.lowercased())
        .font(.system(size: 13)).foregroundStyle(Color.mutedInk).lineLimit(1)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("tempo de treino")
    .accessibilityValue("\(time), começou \(start)")
    .accessibilityIdentifier("sessao.tempo")
  }
}

/// O batimento do ponto verde. Dois segundos por ciclo, que é devagar o bastante
/// para ler como "está rodando" e não como um alerta. Com movimento reduzido o
/// ponto só esmaece, sem encolher.
private struct Pulse: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let active: Bool
  @State private var on = false

  func body(content: Content) -> some View {
    content
      .opacity(on ? 0.35 : 1)
      .scaleEffect(on && !reduceMotion ? 0.8 : 1)
      .animation(on ? .easeInOut(duration: 1).repeatForever(autoreverses: true) : nil, value: on)
      .onChange(of: active, initial: true) { _, active in on = active }
  }
}
