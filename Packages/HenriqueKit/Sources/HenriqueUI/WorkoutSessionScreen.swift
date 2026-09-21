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
  @State private var open: String?
  @State private var entered = false
  @State private var rest: RestState?
  @State private var restSeconds: [String: TimeInterval] = [:]
  @State private var adding = false
  /// O texto em edição por exercício. Só existe enquanto o campo está sendo
  /// digitado; salvo, a fonte volta a ser o painel.
  @State private var noteDrafts: [String: String] = [:]
  @FocusState private var noteFocus: String?

  private static let grow = Animation.spring(response: 0.46, dampingFraction: 0.66)
  private static let settle = Animation.spring(response: 0.34, dampingFraction: 0.74)
  private var grow: Animation? { reduceMotion ? nil : Self.grow }
  private var settle: Animation? { reduceMotion ? nil : Self.settle }

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
        VStack(spacing: 0) {
          top(workout: workout, progress: progress).revealEntrance(index: 0, shown: entered)
          ScrollView {
            LazyVStack(spacing: Space.m) {
              ForEach(workout.exercises) { exercise in
                if openId == exercise.id {
                  card(exercise: exercise, date: data.date, templateId: workout.id)
                } else {
                  collapsed(exercise: exercise)
                }
              }
              addExerciseButton
            }
            .padding(.horizontal, Space.l).padding(.top, Space.s).padding(.bottom, Space.page)
          }
          .scrollDismissesKeyboard(.interactively)
          .revealEntrance(index: 1, shown: entered)
          // A barra entra no fluxo, não por cima: sobreposta ela cobria a linha
          // da série seguinte, que é justamente o que o dedo procura depois.
          if let rest {
            RestTimerBar(rest: rest, onAdjust: adjustRest) { self.rest = nil }
              .padding(.horizontal, 16).padding(.bottom, Space.s)
              .transition(.move(edge: .bottom).combined(with: .opacity))
          }
        }
        .animation(grow, value: rest)
        .animation(grow, value: openId)
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
    VStack(spacing: Space.m) {
      HStack(spacing: Space.m) {
        Button("fechar", systemImage: "chevron.down") { dismiss() }
          .labelStyle(.iconOnly).buttonStyle(.glass).controlSize(.large)
          .accessibilityIdentifier("sessao.fechar")
        VStack(alignment: .leading, spacing: 1) {
          SessionClock(timing: WorkoutSessionTiming(workout), name: workout.name)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Button("encerrar") { dismiss() }
          .buttonStyle(.glass).controlSize(.regular)
          .accessibilityIdentifier("sessao.encerrar")
      }
      VStack(spacing: 6) {
        HStack {
          Text("\(progress.done)").contentTransition(.numericText(value: Double(progress.done)))
          Text("de \(progress.total) séries")
          Spacer()
          Text("\(progress.volumeKg.formatted(.number.precision(.fractionLength(0)))) kg até agora")
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
    }
    .padding(.horizontal, Space.l).padding(.top, Space.s).padding(.bottom, Space.m)
    .background(Color.canvas.opacity(0.94))
    .overlay(alignment: .bottom) { Divider().opacity(0.5) }
  }

  /// O exercício fechado. Diz o que falta nele sem abrir, que é o que decide se o
  /// próximo aparelho vale a caminhada.
  private func collapsed(exercise: DashboardExercise) -> some View {
    Button {
      open = exercise.id
    } label: {
      HStack(spacing: Space.m) {
        Capsule().fill(exercise.isComplete ? accent.base : Color.ink.opacity(0.12))
          .frame(width: 4, height: 36)
        VStack(alignment: .leading, spacing: 2) {
          Text(exercise.name.lowercased())
            .font(.callout.weight(.medium)).foregroundStyle(Color.ink).lineLimit(1)
          Text(subtitle(exercise))
            .font(.footnote).monospacedDigit().foregroundStyle(Color.mutedInk).lineLimit(1)
        }
        Spacer(minLength: Space.s)
        Text("\(exercise.sets.completedWorkCount)/\(exercise.prescription.workSets)")
          .font(.caption).monospacedDigit().foregroundStyle(Color.mutedInk)
          .padding(.horizontal, 10).padding(.vertical, 5)
          .background(Color.surfaceMuted, in: .capsule)
      }
      .padding(.horizontal, Space.l).padding(.vertical, Space.m)
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
    VStack(alignment: .leading, spacing: Space.l) {
      HStack(spacing: Space.s) {
        Text(exercise.muscleGroup.lowercased())
          .font(.caption2.weight(.medium)).foregroundStyle(accent.base)
          .padding(.horizontal, 9).padding(.vertical, 4)
          .background(accent.base.opacity(0.12), in: .capsule)
        if exercise.isFromSession {
          onlyTodayChip(exercise: exercise, date: date, templateId: templateId)
        }
      }
      Text(exercise.name.lowercased())
        .font(.system(size: 30, weight: .medium)).tracking(-1.3)
        .fixedSize(horizontal: false, vertical: true)
      meta(exercise)
      VStack(spacing: Space.s) {
        header
        ForEach(exercise.sets.prep) { set in
          row(exercise: exercise, date: date, templateId: templateId, kind: .prep,
            index: set.index, weight: set.weightKg, reps: set.reps, done: set.isDone, failure: false)
        }
        ForEach(exercise.sets.work) { set in
          row(exercise: exercise, date: date, templateId: templateId, kind: .work,
            index: set.index, weight: set.weightKg, reps: set.reps, done: set.isDone,
            failure: set.toFailure)
        }
        setCountRow(exercise: exercise, date: date, templateId: templateId)
      }
      noteField(exercise: exercise, date: date, templateId: templateId)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Space.xl)
    // As linhas de série da sessão têm raio 20 a 20 de respiro.
    .paperCard(radius: Radius.concentric(SetRowScale.session.radius, padding: Space.xl))
  }

  private func meta(_ exercise: DashboardExercise) -> some View {
    HStack(spacing: Space.s) {
      Text("\(exercise.prescription.workSets) séries valendo")
      if exercise.prescription.workToFailure {
        Text("·")
        Text("última à falha")
      }
      Spacer(minLength: 0)
      Menu {
        Picker("descanso", selection: restBinding(exercise.id)) {
          ForEach(restOptions, id: \.self) { seconds in
            Text(clock(seconds)).tag(seconds)
          }
        }
      } label: {
        Label(
          "descanso \(clock(restSeconds[exercise.id] ?? defaultRestSeconds))",
          systemImage: "timer")
          .font(.caption).monospacedDigit()
          .padding(.horizontal, 10).padding(.vertical, 6)
          .background(Color.surfaceMuted, in: .capsule)
      }
      .buttonStyle(.plain).foregroundStyle(Color.ink)
      .accessibilityIdentifier("sessao.descanso.\(exercise.id)")
    }
    .font(.footnote).foregroundStyle(Color.mutedInk)
  }

  private var header: some View {
    HStack(spacing: 8) {
      Text("#").frame(width: 22)
      Text("anterior").frame(width: 72, alignment: .leading)
      Spacer()
      Text("kg e reps")
    }
    .font(.caption2).foregroundStyle(Color.mutedInk)
    .accessibilityHidden(true)
  }

  @ViewBuilder
  private func row(
    exercise: DashboardExercise, date: CalendarDate, templateId: String, kind: SetKey.Kind,
    index: Int, weight: Double, reps: Int, done: Bool, failure: Bool
  ) -> some View {
    let isNext = kind == .work && !done && exercise.sets.work.first(where: { !$0.isDone })?.index == index
    HStack(spacing: 8) {
      Text(kind == .prep ? "A" : "\(index)")
        .font(.caption.weight(isNext ? .semibold : .regular))
        .foregroundStyle(kind == .prep ? Color.orange : Color.ink)
        .frame(width: 22)
      Text(kind == .prep ? "aquecimento" : previousLabel(exercise.previous, index: index) ?? "estreia")
        .font(.caption).monospacedDigit()
        .foregroundStyle(Color.mutedInk)
        .lineLimit(1).minimumScaleFactor(0.75)
        .frame(width: 72, alignment: .leading)
      TrainingSetRow(
        key: SetKey(date: date, templateId: templateId, exerciseId: exercise.id, kind: kind, index: index),
        weight: weight, repetitions: reps, done: done, failure: failure, scale: .session,
        showsIndex: false)
    }
    .padding(.vertical, 2).padding(.horizontal, isNext ? 6 : 0)
    // A próxima série ganha o fundo. Com a mão no peso, achar a linha certa não
    // pode depender de contar de cima para baixo.
    .background(isNext ? Color.surfaceMuted : .clear, in: .rect(cornerRadius: SetRowScale.session.radius))
  }

  /// Mais ou menos uma série valendo. Tirar só aparece enquanto a última ainda
  /// está em aberto: o servidor não esconde série feita, então o botão sumir é
  /// mais honesto do que pedir e receber a mesma contagem de volta.
  private func setCountRow(exercise: DashboardExercise, date: CalendarDate, templateId: String) -> some View {
    let count = exercise.sets.work.count
    let canRemove = count > Limits.workSets.lowerBound && exercise.sets.work.last?.isDone == false
    return HStack(spacing: Space.s) {
      Button("+ série") {
        Task { await store.setCount(.init(date: date, workoutTemplateId: templateId,
          exerciseId: exercise.id, kind: .work, count: count + 1)) }
      }
      .disabled(count >= Limits.workSets.upperBound)
      .accessibilityIdentifier("sessao.adicionar-serie.\(exercise.id)")
      if canRemove {
        Button("− série") {
          Task { await store.setCount(.init(date: date, workoutTemplateId: templateId,
            exerciseId: exercise.id, kind: .work, count: count - 1)) }
        }
        .accessibilityIdentifier("sessao.remover-serie.\(exercise.id)")
      }
      Spacer(minLength: 0)
    }
    .font(.footnote.weight(.medium)).foregroundStyle(Color.ink)
    .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
    .tint(Color.ink.opacity(0.7))
    .padding(.top, Space.xs)
  }

  private func noteField(exercise: DashboardExercise, date: CalendarDate, templateId: String) -> some View {
    TextField("anotação para esse exercício", text: noteBinding(exercise), axis: .vertical)
      .lineLimit(1...2)
      .font(.footnote).foregroundStyle(Color.ink)
      .focused($noteFocus, equals: exercise.id)
      .submitLabel(.done)
      .onSubmit { noteFocus = nil }
      #if os(iOS)
      .textInputAutocapitalization(.never)
      #endif
      .padding(.horizontal, Space.m).padding(.vertical, Space.s)
      .background(Color.surfaceMuted, in: .rect(cornerRadius: Radius.field))
      .accessibilityLabel("anotação")
      .accessibilityIdentifier("sessao.nota.\(exercise.id)")
      // Num campo de mais de uma linha o retorno quebra linha em vez de encerrar,
      // então sem a barra a anotação prende o teclado aberto.
      .keyboardDone()
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
        .font(.caption2.weight(.medium)).foregroundStyle(Color.mutedInk)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Color.surfaceMuted, in: .capsule)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("sessao.so-hoje.\(exercise.id)")
  }

  private var addExerciseButton: some View {
    Button {
      adding = true
    } label: {
      Text("+ exercício")
        .font(.callout.weight(.medium)).foregroundStyle(Color.ink)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.m)
        .background(Color.surfaceMuted, in: .rect(cornerRadius: Radius.tile))
    }
    .buttonStyle(.plain)
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

  /// O descanso nasce da série marcada, e a duração é a do exercício: um agachamento
  /// pesado não pede a mesma pausa que uma rosca.
  /// Qual exercício está aberto. `open` guarda só a escolha explícita, e o resto sai do
  /// treino a cada pintura: amarrar isso a `onAppear` deixava a lista toda fechada
  /// quando o painel ainda não tinha chegado na primeira vez que a tela apareceu.
  private func openExercise(in workout: WorkoutSummary) -> String? {
    if let open, workout.exercises.contains(where: { $0.id == open }) { return open }
    return workout.exercises[safe: firstOpenExercise(in: workout)]?.id
  }

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
        Text("nenhuma série marcada ainda").font(.caption2).foregroundStyle(Color.mutedInk)
      }
    }
  }

  private func readout(at now: Date, timing: WorkoutSessionTiming, live: Bool) -> some View {
    let seconds = Int(timing.elapsed(at: now))
    let time = Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3600
      ? .hourMinuteSecond : .minuteSecond(padMinuteToLength: 2)))
    let start = timing.startedAt.formatted(.dateTime.hour().minute())
    return VStack(alignment: .leading, spacing: 1) {
      HStack(spacing: 7) {
        if live {
          Circle().fill(accent.signal).frame(width: 8, height: 8)
            .modifier(Pulse(active: !reduceMotion))
        }
        Text(time)
          .font(.system(size: 28, weight: .semibold)).monospacedDigit().tracking(-1.2)
      }
      Text("\(name.lowercased()) · começou \(start)")
        .font(.caption2).foregroundStyle(Color.mutedInk).lineLimit(1)
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
