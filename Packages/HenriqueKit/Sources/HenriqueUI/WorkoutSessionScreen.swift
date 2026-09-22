import HenriqueCore
import SwiftUI

/// Quanto do treino já foi. Derivado do painel a cada pintura, então a sessão e
/// a tela de hoje nunca mostram contagens diferentes.
struct SessionProgress: Equatable {
  let done: Int
  let total: Int
  /// O peso levantado nas séries já marcadas, aquecimento incluído: o que saiu do
  /// chão saiu do chão.
  let volumeKg: Double

  init(_ workout: WorkoutSummary) {
    done = workout.completedWorkSetCount
    total = workout.workSetCount
    volumeKg = workout.exercises.reduce(into: 0.0) { sum, exercise in
      sum += exercise.sets.prep.filter(\.isDone).reduce(0) { $0 + $1.weightKg * Double($1.reps) }
      sum += exercise.sets.work.filter(\.isDone).reduce(0) { $0 + $1.weightKg * Double($1.reps) }
    }
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
func previousLabel(_ previous: PreviousWorkSets?, index: Int) -> String? {
  guard let previous, let reps = previous.reps.indices.contains(index - 1) ? previous.reps[index - 1] : nil
  else { return nil }
  return "\(Formatting.trim(previous.weightKg)) × \(reps)"
}

/// Modo treino: o treino inteiro numa lista, com um exercício aberto por vez. Pular
/// o aparelho ocupado e voltar depois é o caso normal na academia, e a lista deixa
/// fazer isso sem sair da tela.
struct WorkoutSessionScreen: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.accent) private var accent
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .title) private var nameSize = 27.0
  @ScaledMetric(relativeTo: .body) private var collapsedNameSize = 17.0
  @State private var open: String?
  @State private var entered = false
  @State private var rest: RestState?
  @State private var restSeconds: [String: TimeInterval] = [:]
  @State private var adding = false
  /// O texto em edição por exercício. Só existe enquanto o campo está sendo
  /// digitado; salvo, a fonte volta a ser o painel.
  @State private var noteDrafts: [String: String] = [:]
  @FocusState private var noteFocus: String?

  private var hairline: Color { Color.ink.opacity(0.08) }
  private var glide: Animation? { reduceMotion ? nil : Motion.glide }

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
        ScrollView {
          LazyVStack(spacing: Space.m) {
            ForEach(workout.exercises) { exercise in
              if openId == exercise.id {
                card(exercise: exercise, date: data.date, templateId: workout.id)
                  .transition(.opacity)
              } else {
                collapsed(exercise: exercise)
                  .transition(.opacity)
              }
            }
            addExerciseButton
          }
          .padding(.horizontal, Space.l).padding(.top, Space.l)
          // A barra de descanso flutua sobre a lista, então o fim dela ganha o
          // respiro que a barra cobre, e a linha seguinte continua alcançável.
          .padding(.bottom, rest == nil ? Space.page : 230)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
          top(workout: workout, progress: progress).revealEntrance(index: 0, shown: entered)
        }
        .overlay(alignment: .bottom) {
          if let rest {
            RestTimerBar(rest: rest, onAdjust: adjustRest) { self.rest = nil }
              .padding(.horizontal, 12).padding(.bottom, 12)
              .transition(.move(edge: .bottom).combined(with: .opacity))
          }
        }
        .revealEntrance(index: 1, shown: entered)
        .animation(glide, value: rest == nil)
        .animation(reduceMotion ? nil : Motion.subtleEntrance, value: openId)
        .onChange(of: progress.done) { old, new in
          rest = new > old ? startRest(workout: workout) : nil
        }
        .task(id: rest?.endsAt) {
          guard let endsAt = rest?.endsAt else { return }
          try? await Task.sleep(for: .seconds(max(0, endsAt.timeIntervalSinceNow) + 6))
          guard !Task.isCancelled else { return }
          rest = nil
        }
        .onAppear { entered = true }
        .onChange(of: noteFocus) { old, _ in
          guard let old, let exercise = workout.exercises.first(where: { $0.id == old }) else { return }
          saveNote(exercise: exercise, date: data.date, templateId: workout.id)
        }
        .sheet(isPresented: $adding) {
          SessionExercisePicker(
            catalog: data.exerciseCatalog, chosen: Set(workout.exercises.map(\.id))
          ) { item in
            Task {
              await store.addExercise(
                .init(date: data.date, workoutTemplateId: workout.id, exerciseId: item.id))
              open = item.id
            }
          }
        }
      }
    }
    .task { if store.dashboard?.workout == nil { dismiss() } }
  }

  private func top(workout: WorkoutSummary, progress: SessionProgress) -> some View {
    VStack(spacing: 14) {
      HStack(spacing: Space.m) {
        Button { dismiss() } label: {
          Image(systemName: "chevron.down")
            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.ink)
            .frame(width: 40, height: 40)
            .background(.white, in: .circle)
            .overlay(Circle().strokeBorder(hairline))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("fechar")
        .accessibilityIdentifier("sessao.fechar")
        SessionClock(timing: WorkoutSessionTiming(workout), name: workout.name)
          .frame(maxWidth: .infinity, alignment: .leading)
        Button { dismiss() } label: {
          Text("encerrar")
            .font(.system(size: 14, weight: .medium)).foregroundStyle(Color.ink)
            .padding(.top, 10).padding(.bottom, 12).padding(.horizontal, 16)
            .background(.white, in: .capsule)
            .overlay(Capsule().strokeBorder(hairline))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityIdentifier("sessao.encerrar")
      }
      VStack(spacing: 6) {
        HStack(spacing: 0) {
          Text("\(progress.done)")
            .contentTransition(.numericText(value: Double(progress.done)))
            .animation(reduceMotion ? nil : Motion.roll, value: progress.done)
          Text(" ")
          Text("de \(progress.total) séries")
          Spacer()
          Text(progress.volumeKg.formatted(.number.precision(.fractionLength(0))))
            .contentTransition(.numericText(value: progress.volumeKg))
            .animation(reduceMotion ? nil : Motion.roll, value: progress.volumeKg)
          Text(" kg até agora")
        }
        .font(.system(size: 12.5)).monospacedDigit().foregroundStyle(Color.mutedInk)
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
          Text(subtitle(exercise))
            .font(.system(size: 13)).monospacedDigit().foregroundStyle(Color.mutedInk).lineLimit(1)
        }
        Spacer(minLength: Space.s)
        Text("\(exercise.sets.completedWorkCount)/\(exercise.prescription.workSets)")
          .font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.mutedInk)
          .padding(.horizontal, 10).padding(.vertical, 5)
          .background(Color.surfaceMuted, in: .capsule)
      }
      .padding(.horizontal, 18).padding(.vertical, 16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .paperCard(radius: Radius.tile)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("sessao.exercicio.\(exercise.id)")
  }

  private func subtitle(_ exercise: DashboardExercise) -> String {
    let count = "\(exercise.prescription.workSets) séries"
    guard let previous = exercise.previous, let reps = previous.reps.first else { return count }
    return "\(count) · \(Formatting.trim(previous.weightKg)) kg × \(reps) da última vez"
  }

  private func card(exercise: DashboardExercise, date: CalendarDate, templateId: String) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: Space.s) {
        Text(exercise.muscleGroup.lowercased())
          .font(.system(size: 12, weight: .medium)).foregroundStyle(accent.deep)
          .padding(.horizontal, 11).padding(.vertical, 5)
          .background(accent.pale, in: .capsule)
        if exercise.isFromSession {
          onlyTodayChip(exercise: exercise, date: date, templateId: templateId)
        }
      }
      Text(exercise.name.lowercased())
        .font(.system(size: nameSize, weight: .semibold)).tracking(nameSize * -0.045)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 12)
      meta(exercise).padding(.top, 8)
      header.padding(.top, 18).padding(.bottom, 8)
      VStack(spacing: 2) {
        ForEach(exercise.sets.prep) { set in
          row(exercise: exercise, date: date, templateId: templateId, kind: .prep,
            index: set.index, weight: set.weightKg, reps: set.reps, done: set.isDone, failure: false)
        }
        ForEach(exercise.sets.work) { set in
          row(exercise: exercise, date: date, templateId: templateId, kind: .work,
            index: set.index, weight: set.weightKg, reps: set.reps, done: set.isDone,
            failure: set.toFailure)
        }
      }
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

  /// O botão de descanso segue a meta na mesma linha. Em tela estreita a linha
  /// quebra em duas em vez de cortar.
  private func meta(_ exercise: DashboardExercise) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) {
        metaText(exercise)
        Text("·")
        restPicker(exercise)
      }
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) { metaText(exercise) }
        restPicker(exercise)
      }
    }
    .font(.system(size: 13)).monospacedDigit().foregroundStyle(Color.mutedInk)
  }

  @ViewBuilder
  private func metaText(_ exercise: DashboardExercise) -> some View {
    Text("\(exercise.prescription.workSets) séries valendo")
    if exercise.prescription.workToFailure {
      Text("·")
      Text("última à falha")
    }
  }

  private func restPicker(_ exercise: DashboardExercise) -> some View {
    Menu {
      Picker("descanso", selection: restBinding(exercise.id)) {
        ForEach(restOptions, id: \.self) { seconds in
          Text(clock(seconds)).tag(seconds)
        }
      }
    } label: {
      HStack(spacing: 5) {
        Image(systemName: "clock").font(.system(size: 12))
        Text("descanso \(clock(restSeconds[exercise.id] ?? defaultRestSeconds))")
      }
      .font(.system(size: 12.5)).monospacedDigit().foregroundStyle(Color.ink)
      .padding(.horizontal, 11).padding(.vertical, 5)
      .background(Color.surfaceMuted, in: .capsule)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("sessao.descanso.\(exercise.id)")
  }

  /// As mesmas cinco colunas da linha, com as mesmas larguras, para o título
  /// cair em cima do que nomeia.
  private var header: some View {
    HStack(spacing: 8) {
      Text("#").frame(width: 30)
      Text("anterior").frame(maxWidth: .infinity, alignment: .leading)
      Text("kg").frame(minWidth: 56, maxWidth: 66)
      Text("reps").frame(minWidth: 56, maxWidth: 66)
      Color.clear.frame(width: SetRowScale.session.check, height: 1)
    }
    .padding(.horizontal, 2)
    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.mutedInk)
    .accessibilityHidden(true)
  }

  private func row(
    exercise: DashboardExercise, date: CalendarDate, templateId: String, kind: SetKey.Kind,
    index: Int, weight: Double, reps: Int, done: Bool, failure: Bool
  ) -> some View {
    let isNext = kind == .work && !done && exercise.sets.work.first(where: { !$0.isDone })?.index == index
    return TrainingSetRow(
      key: SetKey(date: date, templateId: templateId, exerciseId: exercise.id, kind: kind, index: index),
      weight: weight, repetitions: reps, done: done, failure: failure, scale: .session,
      isNext: isNext, previous: previousLabel(exercise.previous, index: index))
  }

  /// Mais ou menos uma série valendo. Tirar só aparece enquanto a última ainda
  /// está em aberto, porque o servidor não esconde série feita, e o botão sumir
  /// é mais honesto do que pedir e receber a mesma contagem de volta.
  private func setCountRow(exercise: DashboardExercise, date: CalendarDate, templateId: String) -> some View {
    let count = exercise.sets.work.count
    let canRemove = count > Limits.workSets.lowerBound && exercise.sets.work.last?.isDone == false
    return HStack(spacing: Space.s) {
      ghostButton("+ adicionar série", color: accent.base) {
        Task { await store.setCount(.init(date: date, workoutTemplateId: templateId,
          exerciseId: exercise.id, kind: .work, count: count + 1)) }
      }
      .disabled(count >= Limits.workSets.upperBound)
      .accessibilityIdentifier("sessao.adicionar-serie.\(exercise.id)")
      if canRemove {
        ghostButton("− série", color: Color.mutedInk) {
          Task { await store.setCount(.init(date: date, workoutTemplateId: templateId,
            exerciseId: exercise.id, kind: .work, count: count - 1)) }
        }
        .accessibilityIdentifier("sessao.remover-serie.\(exercise.id)")
      }
    }
  }

  private func ghostButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 14.5, weight: .medium)).foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .padding(11)
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(hairline))
    }
    .buttonStyle(PressScaleStyle())
  }

  private func noteField(exercise: DashboardExercise, date: CalendarDate, templateId: String) -> some View {
    HStack(alignment: .top, spacing: 9) {
      Image(systemName: "text.alignleft")
        .font(.system(size: 15)).foregroundStyle(Color.mutedInk)
        .padding(.top, 2)
      TextField("anotação", text: noteBinding(exercise), axis: .vertical)
        .lineLimit(1...2)
        .font(.system(size: 13.5)).foregroundStyle(Color.mutedInk)
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
        .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.mutedInk)
        .padding(.horizontal, 11).padding(.vertical, 5)
        .background(Color.surfaceMuted, in: .capsule)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("sessao.so-hoje.\(exercise.id)")
  }

  private var addExerciseButton: some View {
    Button {
      adding = true
    } label: {
      Text("+ adicionar exercício")
        .font(.system(size: 15)).foregroundStyle(Color.mutedInk)
        .frame(maxWidth: .infinity)
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: Radius.row).strokeBorder(hairline))
    }
    .buttonStyle(PressScaleStyle())
    .accessibilityIdentifier("sessao.adicionar-exercicio")
  }

  private var restOptions: [TimeInterval] { [30, 45, 60, 75, 90, 120, 150, 180, 240, 300] }

  private func restBinding(_ exerciseId: String) -> Binding<TimeInterval> {
    Binding(
      get: { restSeconds[exerciseId] ?? defaultRestSeconds },
      set: { restSeconds[exerciseId] = $0 })
  }

  private func clock(_ seconds: TimeInterval) -> String {
    let total = Int(seconds)
    return String(format: "%d:%02d", total / 60, total % 60)
  }

  /// Qual exercício está aberto. `open` guarda só a escolha explícita, e o resto sai do
  /// treino a cada pintura: amarrar isso a `onAppear` deixava a lista toda fechada
  /// quando o painel ainda não tinha chegado na primeira vez que a tela apareceu.
  private func openExercise(in workout: WorkoutSummary) -> String? {
    if let open, workout.exercises.contains(where: { $0.id == open }) { return open }
    return workout.exercises[safe: firstOpenExercise(in: workout)]?.id
  }

  /// O descanso nasce da série marcada, e a duração é a do exercício, porque um
  /// agachamento pesado não pede a mesma pausa que uma rosca.
  private func startRest(workout: WorkoutSummary) -> RestState {
    let id = openExercise(in: workout)
    let index = workout.exercises.firstIndex { $0.id == id } ?? 0
    let seconds = restSeconds[id ?? ""] ?? defaultRestSeconds
    return RestState(total: seconds, endsAt: .now + seconds, next: NextSet(from: index, in: workout))
  }

  private func adjustRest(by delta: TimeInterval) {
    guard let current = rest else { return }
    let total = min(600, max(15, current.total + delta))
    if let id = store.dashboard?.workout.flatMap({ openExercise(in: $0) }) {
      restSeconds[id] = total
    }
    rest = RestState(total: total, endsAt: max(.now, current.endsAt + delta), next: current.next)
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
      TimelineView(.periodic(from: .now, by: 1)) { context in
        readout(at: context.date, timing: timing, live: true)
      }
    } else if let timing {
      readout(at: .now, timing: timing, live: false)
    } else {
      VStack(alignment: .leading, spacing: 1) {
        Text(name.lowercased()).font(.headline.weight(.semibold))
        Text("nenhuma série marcada ainda").font(.system(size: 13)).foregroundStyle(Color.mutedInk)
      }
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
            .modifier(Pulse(active: !reduceMotion))
        }
        Text(time)
          .font(.system(size: clockSize, weight: .semibold)).monospacedDigit()
          .tracking(clockSize * -0.05)
          .contentTransition(.numericText(value: Double(seconds)))
          .animation(reduceMotion ? nil : Motion.roll, value: seconds)
      }
      Text("\(name.lowercased()) · começou \(start)")
        .font(.system(size: 13)).foregroundStyle(Color.mutedInk).lineLimit(1)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("tempo de treino")
    .accessibilityValue(time)
    .accessibilityIdentifier("sessao.tempo")
  }
}

/// O batimento do ponto verde. Dois segundos por ciclo, que é devagar o bastante
/// para ler como "está rodando" e não como um alerta.
private struct Pulse: ViewModifier {
  let active: Bool
  @State private var on = false

  func body(content: Content) -> some View {
    content
      .opacity(active && on ? 0.35 : 1)
      .scaleEffect(active && on ? 0.8 : 1)
      .animation(active ? .easeInOut(duration: 1).repeatForever(autoreverses: true) : nil, value: on)
      .onAppear { on = active }
  }
}
