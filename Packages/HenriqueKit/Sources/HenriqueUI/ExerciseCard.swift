import HenriqueCore
import SwiftUI

struct ExerciseCard: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.accent) private var accent
  let exercise: DashboardExercise
  let date: CalendarDate
  let templateId: String
  let isOpen: Bool
  let onToggle: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      Button(action: onToggle) {
        HStack(spacing: 12) {
          if exercise.imageUrl != nil {
            ExerciseThumb(imageUrl: exercise.imageUrl, size: 48)
          } else {
            Image(systemName: "dumbbell").font(.title3).foregroundStyle(accent.base)
              .frame(width: 48, height: 48).background(accent.pale.opacity(0.4), in: .circle)
          }
          VStack(alignment: .leading, spacing: 6) {
            Text(exercise.name.lowercased()).font(.headline.weight(.medium))
            Text(prescription).font(.caption).foregroundStyle(Color.mutedInk)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 0)
          Text("\(exercise.sets.completedWorkCount)/\(exercise.prescription.workSets)")
            .font(.caption).monospacedDigit().foregroundStyle(Color.mutedInk)
          Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.caption2)
        }.padding(16).frame(minHeight: 92).contentShape(.rect)
      }.buttonStyle(StudyPressStyle()).accessibilityValue(isOpen ? "expandido" : "recolhido")
      if isOpen {
        VStack(spacing: 8) {
          HStack {
            Color.clear.frame(width: 34, height: 1)
            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
            Text("reps").frame(maxWidth: .infinity)
            Color.clear.frame(width: 44, height: 1)
          }.font(.caption2).foregroundStyle(Color.mutedInk)
          if !exercise.sets.prep.isEmpty {
            group("aquecimento", color: .mutedInk)
            ForEach(exercise.sets.prep) { set in
              TrainingSetRow(key: SetKey(date: date, templateId: templateId, exerciseId: exercise.id, kind: .prep, index: set.index),
                weight: set.weightKg, repetitions: set.reps, done: set.isDone, failure: false)
            }
          }
          group(exercise.prescription.workToFailure ? "valendo · falha" : "valendo", color: accent.base)
          ForEach(exercise.sets.work) { set in
            TrainingSetRow(key: SetKey(date: date, templateId: templateId, exerciseId: exercise.id, kind: .work, index: set.index),
              weight: set.weightKg, repetitions: set.reps, done: set.isDone, failure: set.toFailure)
          }
          if let previous {
            Text(previous).font(.caption).foregroundStyle(Color.mutedInk)
              .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
          }
        }.padding(Space.s).background(.white, in: .rect(cornerRadius: Radius.concentric(SetRowScale.list.radius, padding: Space.s))).padding(6)
          .transition(.opacity)
      }
    }
    .paperCard(radius: Radius.concentric(24, padding: 6), fill: .surfaceMuted)
  }

  private var prescription: String {
    let p = exercise.prescription
    let reps = p.workToFailure ? "falha" : "\(p.repsMin)-\(p.repsMax)"
    return "\(p.workSets) × \(reps) · \(weightLabel(p.startingWeightKg))"
  }
  private var previous: String? {
    guard let previous = exercise.previous else { return nil }
    return "última: \(previous.reps.map(String.init).joined(separator: ", ")) × \(weightLabel(previous.weightKg))"
  }
  private func group(_ title: String, color: Color) -> some View {
    HStack(spacing: 6) {
      Circle().fill(color).frame(width: 5, height: 5)
      Text(title).font(.caption)
      Spacer()
    }.foregroundStyle(color).padding(.top, 8)
  }
}

/// O tamanho da linha de série. A tela de hoje lista para conferir, com a mão
/// livre; a sessão é para marcar com o peso na mão, então lá o número e o alvo
/// do dedo crescem.
enum SetRowScale {
  case list, session

  var check: CGFloat { self == .list ? 44 : 46 }
  var value: Font { self == .list ? .subheadline : .system(size: 19, weight: .medium) }
  var padding: CGFloat { self == .list ? 6 : 8 }
  var radius: CGFloat { Radius.concentric(Radius.field, padding: padding) }
  /// A lista tem uma linha de cabeçalho dizendo qual coluna é qual. A sessão
  /// mostra um exercício só e não tem cabeçalho, então a unidade vai na linha.
  var showsUnits: Bool { self == .session }
}

struct TrainingSetRow: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.accent) private var accent
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var weightDraft: Double?
  @State private var repsDraft: Int?
  @FocusState private var focused: Field?
  @State private var submitted: SetDraft?
  @State private var tapCount = 0
  private enum Field: Hashable { case weight, reps }
  let key: SetKey
  private var kind: SetKey.Kind { key.kind }
  private var index: Int { key.index }
  let weight: Double
  let repetitions: Int
  let done: Bool
  let failure: Bool
  var scale: SetRowScale = .list
  /// A sessão desenha o número da série junto da coluna "anterior", então a linha
  /// não repete o número ao lado dos campos.
  var showsIndex: Bool = true

  private var fieldID: String { "set.\(key.exerciseId).\(kind == .prep ? "prep" : "work").\(index)" }
  private var waiting: Bool { store.isWaiting(key) }
  private var currentDone: Bool {
    guard store.dashboard?.date == key.date, store.dashboard?.workout?.id == key.templateId,
      let current = store.dashboard?.workout?.exercises.first(where: { $0.id == key.exerciseId }) else { return done }
    return kind == .prep ? current.sets.prep.first(where: { $0.index == index })?.isDone ?? done
      : current.sets.work.first(where: { $0.index == index })?.isDone ?? done
  }

  var body: some View {
    HStack(spacing: 8) {
      if showsIndex {
        Text(kind == .prep ? "P\(index)" : "\(index)").font(.caption).frame(width: 26)
      }
      HStack(spacing: 2) {
        TextField("0", value: $weightDraft, format: .number.precision(.fractionLength(0...2)))
          #if os(iOS)
          .keyboardType(.decimalPad)
          #endif
          .focused($focused, equals: .weight)
          .submitLabel(.done)
          .font(scale.value)
          .accessibilityIdentifier(fieldID + ".weight")
          .accessibilityLabel("Peso da série \(index)")
          .onChange(of: weightDraft) { _, new in
            if let new, new.isFinite, !Limits.setWeightKg.contains(new) { weightDraft = new.clamped(to: Limits.setWeightKg) }
          }
        Text("kg").font(.caption2).foregroundStyle(Color.mutedInk)
      }.padding(8).background(.white, in: .rect(cornerRadius: Radius.field))
      HStack(spacing: 2) {
        TextField("0", value: $repsDraft, format: .number)
          #if os(iOS)
          .keyboardType(.numberPad)
          #endif
          .focused($focused, equals: .reps)
          .submitLabel(.done)
          .font(scale.value)
          .accessibilityIdentifier(fieldID + ".reps")
          .accessibilityLabel("Repetições da série \(index)")
          .onChange(of: repsDraft) { _, new in
            if let new, new > Limits.reps.upperBound { repsDraft = Limits.reps.upperBound }
          }
        if failure {
          Text("falha").font(.system(size: 9)).foregroundStyle(accent.base)
        } else if scale.showsUnits {
          Text("reps").font(.caption2).foregroundStyle(Color.mutedInk)
        }
      }.padding(8).background(.white, in: .rect(cornerRadius: Radius.field))
      Button {
        commit(completed: !currentDone)
        focused = nil
        tapCount += 1
      } label: {
        // O círculo vazio com a borda é o estado não marcado, e o visto entra
        // por cima dele. Um visto fantasma parado no lugar não deixava espaço
        // para a entrada, e era o que fazia a confirmação passar em branco.
        ZStack {
          if done {
            Image(systemName: "checkmark").font(.body.weight(.semibold))
              .foregroundStyle(accent.deep)
              .transition(.iconAppear)
          }
        }
        .frame(width: scale.check, height: scale.check)
        .background(done ? accent.acid : .white, in: .circle)
        // A borda carrega sozinha o estado não marcado agora que o visto
        // fantasma saiu, então ela ganhou o peso que ele tinha.
        .overlay(Circle().strokeBorder(Color.ink.opacity(done ? 0 : 0.18), lineWidth: 1.5))
        // Borda tracejada enquanto a marcação não chegou ao servidor. O visto
        // cheio sozinho prometia coisa que às vezes não tinha acontecido.
        .overlay {
          if waiting {
            Circle().strokeBorder(
              accent.deep.opacity(0.55),
              style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
          }
        }
        .scaleEffect(done ? 1 : 0.94)
      }.buttonStyle(SetCompletionStyle()).disabled(!Limits.setWeightKg.contains(weightDraft ?? -1) || !Limits.reps.contains(repsDraft ?? 0))
        .accessibilityIdentifier(fieldID + ".completion")
        .animation(reduceMotion ? nil : Motion.confirm, value: done)
        .accessibilityLabel(done ? "Desmarcar série \(index)" : "Concluir série \(index)")
        .accessibilityValue(waiting ? "esperando enviar" : "")
        .sensoryFeedback(currentDone ? .success : .impact(weight: .light), trigger: tapCount)
    }
    .font(.subheadline).monospacedDigit().multilineTextAlignment(.center)
    .padding(scale.padding).background(kind == .prep ? Color.surfaceMuted : accent.pale.opacity(0.5), in: .rect(cornerRadius: scale.radius))
    .onChange(of: weight, initial: true) { if focused == nil { weightDraft = weight } }
    .onChange(of: repetitions, initial: true) { if focused == nil { repsDraft = repetitions } }
    .onChange(of: focused) { old, new in
      if old != nil { commit(completed: currentDone) }
      if new == nil { submitted = nil }
    }
    .onSubmit { commit(completed: currentDone); focused = nil }
  }

  private func commit(completed: Bool) {
    let draft = SetDraft(weightKg: weightDraft ?? weight, reps: repsDraft ?? repetitions,
      completed: completed, toFailure: failure)
    guard draft != submitted, draft.weightKg.isFinite, Limits.setWeightKg.contains(draft.weightKg),
      Limits.reps.contains(draft.reps) else { return }
    let current = SetDraft(weightKg: weight, reps: repetitions, completed: currentDone, toFailure: failure)
    guard draft != current else { return }
    submitted = draft
    store.record(key: key,
      weightKg: draft.weightKg, reps: draft.reps, completed: completed, toFailure: failure)
  }
}

private struct SetCompletionStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed && !reduceMotion ? Motion.press : 1)
      .opacity(configuration.isPressed ? 0.8 : 1)
      .animation(configuration.isPressed || reduceMotion ? nil : Motion.tap, value: configuration.isPressed)
  }
}

func weightLabel(_ kilograms: Double) -> String {
  kilograms.formatted(.number.precision(.fractionLength(0...1))) + " kg"
}
