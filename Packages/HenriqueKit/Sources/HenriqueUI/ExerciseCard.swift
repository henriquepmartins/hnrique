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
/// do dedo crescem e a linha vira a grade de cinco colunas do board, com o
/// índice e o "anterior" dentro dela.
enum SetRowScale {
  case list, session

  var check: CGFloat { self == .list ? 44 : 46 }
  var value: Font { self == .list ? .subheadline : .system(size: 19, weight: .medium) }
  var padding: CGFloat { self == .list ? 6 : 8 }
  var radius: CGFloat { Radius.concentric(Radius.field, padding: padding) }
}

struct TrainingSetRow: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.accent) private var accent
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .body) private var tileHeight = 46.0
  @ScaledMetric(relativeTo: .footnote) private var indexSize = 13.0
  @ScaledMetric(relativeTo: .caption2) private var unitSize = 10.0
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
  /// A próxima série a marcar. Só a sessão pinta isso; a lista de hoje não
  /// guia a mão.
  var isNext: Bool = false
  /// O que a série tem a bater, na coluna "anterior" da sessão.
  var previous: String? = nil

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
      switch scale {
      case .list:
        Text(kind == .prep ? "P\(index)" : "\(index)").font(.caption).frame(width: 26)
      case .session:
        Text(kind == .prep ? "A" : "\(index)")
          .font(.system(size: indexSize, weight: isNext ? .medium : .regular, design: .monospaced))
          .foregroundStyle(kind == .prep ? Color.orange : Color.ink)
          .frame(width: 30)
        Text(kind == .prep ? "aquecimento" : previous ?? "estreia")
          .font(.system(size: indexSize)).monospacedDigit()
          .foregroundStyle(done ? accent.deep.opacity(0.6) : Color.mutedInk)
          .lineLimit(1).minimumScaleFactor(0.8)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      cell(unit: unit("kg")) {
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
      }
      cell(unit: repsUnit) {
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
      }
      Button {
        commit(completed: !currentDone)
        focused = nil
        tapCount += 1
      } label: {
        // O visto está sempre desenhado e só muda de cor. É o cinza dele que
        // diz "ainda não", e o verde na próxima série que convida ao toque.
        Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold))
          .foregroundStyle(done ? Color.white : isNext ? accent.base : Color.ink.opacity(0.28))
          .frame(width: scale.check, height: scale.check)
          .background(done ? accent.base : .white, in: .circle)
          .overlay(Circle().strokeBorder(
            done ? .clear : isNext ? accent.base : Color.ink.opacity(0.16), lineWidth: 1.5))
          // Borda tracejada enquanto a marcação não chegou ao servidor. O visto
          // cheio sozinho prometia coisa que às vezes não tinha acontecido.
          .overlay {
            if waiting {
              Circle().strokeBorder(
                accent.deep.opacity(0.55),
                style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }
          }
      }
      // O check encolhe mais que os outros botões, como no board.
      .buttonStyle(PressScaleStyle(scale: 0.92))
      .disabled(!Limits.setWeightKg.contains(weightDraft ?? -1) || !Limits.reps.contains(repsDraft ?? 0))
        .accessibilityIdentifier(fieldID + ".completion")
        .animation(reduceMotion ? nil : Motion.confirm, value: done)
        .accessibilityLabel(done ? "Desmarcar série \(index)" : "Concluir série \(index)")
        .accessibilityValue(waiting ? "esperando enviar" : "")
        .sensoryFeedback(currentDone ? .success : .impact(weight: .light), trigger: tapCount)
    }
    .font(.subheadline).monospacedDigit().multilineTextAlignment(.center)
    .modifier(RowChrome(scale: scale, kind: kind, done: done, isNext: isNext, accent: accent))
    .animation(reduceMotion ? nil : Motion.crossfade, value: isNext)
    .onChange(of: weight, initial: true) { if focused == nil { weightDraft = weight } }
    .onChange(of: repetitions, initial: true) { if focused == nil { repsDraft = repetitions } }
    .onChange(of: focused) { old, new in
      if old != nil { commit(completed: currentDone) }
      if new == nil { submitted = nil }
    }
    .onSubmit { commit(completed: currentDone); focused = nil }
  }

  /// A unidade de reps. A lista de hoje tem cabeçalho e só escreve "falha"; a
  /// sessão escreve a unidade embaixo do número.
  private var repsUnit: Text? {
    if failure { return unit("falha", toFailure: true) }
    return scale == .session ? unit("reps") : nil
  }

  /// A unidade já sai daqui com fonte e cor. Quem pinta é a própria unidade,
  /// não o ladrilho, senão a série à falha esverdeia o quilo junto com o reps.
  private func unit(_ text: String, toFailure: Bool = false) -> Text {
    Text(text)
      .font(scale == .session
        ? .system(size: unitSize)
        : toFailure ? .system(size: 9) : .caption2)
      .foregroundStyle(toFailure ? accent.base : Color.mutedInk)
  }

  /// O ladrilho de kg ou reps. Na lista o número e a unidade ficam lado a lado
  /// numa pílula branca; na sessão a unidade vai embaixo, num ladrilho que muda
  /// de fundo com o estado da linha.
  @ViewBuilder
  private func cell<Field: View>(unit: Text?, @ViewBuilder field: () -> Field) -> some View {
    switch scale {
    case .list:
      HStack(spacing: 2) {
        field()
        unit
      }
      .padding(8).background(.white, in: .rect(cornerRadius: Radius.field))
    case .session:
      VStack(spacing: 0) {
        field()
        unit
      }
      .frame(minWidth: 56, maxWidth: 66).frame(height: tileHeight)
      .background(done ? .clear : isNext ? .white : Color.surfaceMuted, in: .rect(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.ink.opacity(isNext && !done ? 0.08 : 0)))
    }
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

/// O fundo da linha. Na lista de hoje é a cor do tipo de série; na sessão é o
/// estado (parada, próxima, feita), que é o que diz ao dedo onde ir.
private struct RowChrome: ViewModifier {
  let scale: SetRowScale
  let kind: SetKey.Kind
  let done: Bool
  let isNext: Bool
  let accent: Accent

  func body(content: Content) -> some View {
    switch scale {
    case .list:
      content.padding(scale.padding)
        .background(kind == .prep ? Color.surfaceMuted : accent.pale.opacity(0.5), in: .rect(cornerRadius: scale.radius))
    case .session:
      content.padding(.vertical, 7).padding(.horizontal, 2)
        .background(done ? accent.base.opacity(0.06) : isNext ? Color.surfaceMuted : .clear, in: .rect(cornerRadius: 18))
    }
  }
}

func weightLabel(_ kilograms: Double) -> String {
  kilograms.formatted(.number.precision(.fractionLength(0...1))) + " kg"
}
