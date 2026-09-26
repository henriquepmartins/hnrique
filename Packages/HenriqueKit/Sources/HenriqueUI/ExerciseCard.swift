import HenriqueCore
import SwiftUI
#if canImport(UIKit)
  import UIKit
#endif

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
              .frame(width: 48, height: 48).background(accent.pale.opacity(0.4), in: .rect(cornerRadius: 48 * 0.32))
          }
          VStack(alignment: .leading, spacing: 6) {
            Text(exercise.name.lowercased()).font(.headline.weight(.medium))
            prescription.font(.caption).foregroundStyle(Color.mutedInk)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityLabel(spokenPrescription)
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
            Text("kg").frame(maxWidth: .infinity)
            Text("reps").frame(maxWidth: .infinity)
            Color.clear.frame(width: 44, height: 1)
          }.font(.caption2).foregroundStyle(Color.mutedInk)
          .accessibilityHidden(true)
          if !exercise.sets.prep.isEmpty {
            group("aquecimento", color: .mutedInk)
            ForEach(exercise.sets.prep) { set in
              TrainingSetRow(key: SetKey(date: date, templateId: templateId, exerciseId: exercise.id, kind: .prep, index: set.index),
                weight: set.weightKg, repetitions: set.reps, done: set.isDone, failure: false,
                reference: setReference(exercise, kind: .prep, index: set.index))
            }
          }
          group("valendo", color: accent.base, toFailure: exercise.prescription.workToFailure)
          ForEach(exercise.sets.work) { set in
            TrainingSetRow(key: SetKey(date: date, templateId: templateId, exerciseId: exercise.id, kind: .work, index: set.index),
              weight: set.weightKg, repetitions: set.reps, done: set.isDone, failure: set.toFailure,
              reference: setReference(exercise, kind: .work, index: set.index))
          }
        }.padding(Space.s).background(.white, in: .rect(cornerRadius: Radius.concentric(SetRowScale.list.radius, padding: Space.s))).padding(6)
          .transition(.opacity)
      }
    }
    .paperCard(radius: Radius.concentric(24, padding: 6), fill: .surfaceMuted)
  }

  /// "2 × 6–10" e o raio quando as séries valendo vão à falha.
  private var prescription: some View {
    let p = exercise.prescription
    return HStack(spacing: 4) {
      Text("\(p.workSets) × \(p.repsMin)–\(p.repsMax)")
      if p.workToFailure { FailureMark() }
      Text("· \(weightLabel(p.startingWeightKg))")
    }
  }
  private var spokenPrescription: String {
    let p = exercise.prescription
    let failure = p.workToFailure ? ", até a falha" : ""
    return "\(p.workSets) séries de \(p.repsMin) a \(p.repsMax)\(failure), \(weightLabel(p.startingWeightKg))"
  }
  private func group(_ title: String, color: Color, toFailure: Bool = false) -> some View {
    HStack(spacing: 6) {
      Circle().fill(color).frame(width: 5, height: 5).offset(y: 1)
      Text(title).font(.caption)
      if toFailure { FailureMark() }
      Spacer()
    }
    .foregroundStyle(color).padding(.top, 8)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(toFailure ? "\(title), até a falha" : title)
  }
}

/// O raio das séries que vão à falha. O modelo tem um booleano por exercício, então
/// ele marca todas as séries valendo, não só a última.
struct FailureMark: View {
  @Environment(\.accent) private var accent
  @ScaledMetric(relativeTo: .caption2) private var size = 9.0

  var body: some View {
    Image(systemName: "bolt.fill")
      .font(.system(size: size, weight: .semibold)).foregroundStyle(accent.base)
      .accessibilityLabel("até a falha")
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
  @State private var weightDraft: Double?
  @State private var repsDraft: Int?
  @FocusState private var focused: Field?
  @State private var submitted: SetDraft?
  @State private var tapCount = 0
  private enum Field: Hashable { case weight, reps }
  let key: SetKey
  private var kind: SetKind { key.kind }
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
  /// A carga com que o campo compara o número digitado, para estranhar um 250
  /// onde a última vez foi 25.
  var reference: WeightReference? = nil

  private var fieldID: String { "set.\(key.exerciseId).\(kind == .prep ? "prep" : "work").\(index)" }
  /// "aquecimento 1" ou "série 1". O leitor de tela lia as duas linhas iguais.
  private var spokenName: String { kind == .prep ? "aquecimento \(index)" : "série \(index)" }
  private var waiting: Bool { store.isWaiting(key) }
  private var currentDone: Bool {
    guard store.dashboard?.date == key.date, store.dashboard?.workout?.id == key.templateId,
      let current = store.dashboard?.workout?.exercises.first(where: { $0.id == key.exerciseId }) else { return done }
    return kind == .prep ? current.sets.prep.first(where: { $0.index == index })?.isDone ?? done
      : current.sets.work.first(where: { $0.index == index })?.isDone ?? done
  }

  var body: some View {
    // O aviso vai em cima da linha: embaixo, o teclado cobre ele enquanto se digita.
    VStack(spacing: 4) {
      if let warning = weightWarning(weightDraft, reference: reference) {
        Label(warning, systemImage: "exclamationmark.triangle.fill")
          .font(.caption).foregroundStyle(Color.orange)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 6)
          .accessibilityIdentifier(fieldID + ".aviso")
      }
      fields
    }
    .font(.subheadline).monospacedDigit().multilineTextAlignment(.center)
    .modifier(RowChrome(scale: scale, kind: kind, done: done, isNext: isNext, accent: accent))
    .animation(reduceMotion ? nil : Motion.crossfade, value: isNext)
    .onChange(of: weight, initial: true) { if focused == nil { weightDraft = weight } }
    .onChange(of: repetitions, initial: true) { if focused == nil { repsDraft = repetitions } }
    .onChange(of: focused) { old, new in
      if old != nil { commit(completed: currentDone) }
      if new == nil { submitted = nil }
      if new != nil { selectAllInFocusedField() }
    }
    .onSubmit { commit(completed: currentDone); focused = nil }
  }

  private var fields: some View {
    HStack(spacing: 8) {
      switch scale {
      case .list:
        Text(kind == .prep ? "A" : "\(index)").font(.caption).frame(width: 26)
          .accessibilityLabel(spokenName)
      case .session:
        HStack(spacing: 2) {
          Text(kind == .prep ? "A" : "\(index)")
            .font(.system(size: indexSize, weight: isNext ? .medium : .regular, design: .monospaced))
            .foregroundStyle(kind == .prep ? Color.orange : Color.ink)
          if failure { FailureMark() }
        }
        .frame(width: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(failure ? "\(spokenName), até a falha" : spokenName)
        Text(previous ?? "–")
          .font(.system(size: indexSize)).monospacedDigit()
          .foregroundStyle(done ? accent.deep.opacity(0.6) : Color.mutedInk)
          .lineLimit(1).minimumScaleFactor(0.8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityLabel(previous.map { "anterior \($0)" } ?? "sem registro anterior")
      }
      cell {
        TextField("0", value: $weightDraft, format: .number.precision(.fractionLength(0...2)))
          #if os(iOS)
          .keyboardType(.decimalPad)
          #endif
          .focused($focused, equals: .weight)
          .submitLabel(.done)
          .font(scale.value)
          .accessibilityIdentifier(fieldID + ".weight")
          .accessibilityLabel("Peso \(kind == .prep ? "do" : "da") \(spokenName)")
      }
      cell {
        TextField("0", value: $repsDraft, format: .number)
          #if os(iOS)
          .keyboardType(.numberPad)
          #endif
          .focused($focused, equals: .reps)
          .submitLabel(.done)
          .font(scale.value)
          .accessibilityIdentifier(fieldID + ".reps")
          .accessibilityLabel("Repetições \(kind == .prep ? "do" : "da") \(spokenName)")
          .onChange(of: repsDraft) { _, new in
            if let new, new > Limits.reps.upperBound { repsDraft = Limits.reps.upperBound }
          }
      }
      Button {
        commit(completed: !currentDone)
        focused = nil
        tapCount += 1
      } label: {
        // O visto só aparece na série feita: desenhado cinza em toda linha, ele
        // lia como já marcado. A próxima ganha a borda verde, que convida ao
        // toque. Enquanto a marcação não chegou ao servidor o visto fica vazado,
        // com borda tracejada e um relógio no canto.
        Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold))
          .foregroundStyle(waiting ? accent.base : Color.white)
          .opacity(done ? 1 : 0)
          .offset(y: -0.5)
          .frame(width: scale.check, height: scale.check)
          .background(done && !waiting ? accent.base : .white, in: .circle)
          .overlay {
            if waiting {
              Circle().strokeBorder(accent.base, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            } else if !done {
              Circle().strokeBorder(
                isNext ? accent.base : Color.ink.opacity(0.16), lineWidth: isNext ? 2 : 1.5)
            }
          }
          .overlay(alignment: .topTrailing) {
            if waiting {
              Image(systemName: "clock.fill")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.orange)
                .background(Circle().fill(.white).padding(-1))
                .offset(x: 3, y: -3)
            }
          }
      }
      // O check encolhe mais que os outros botões, como no board.
      .buttonStyle(PressScaleStyle(scale: 0.92))
      .disabled(!Limits.setWeightKg.contains(weightDraft ?? -1) || !Limits.reps.contains(repsDraft ?? 0))
        .accessibilityIdentifier(fieldID + ".completion")
        .animation(reduceMotion ? nil : Motion.confirm, value: done)
        .accessibilityLabel(done ? "Desmarcar \(spokenName)" : "Concluir \(spokenName)")
        .accessibilityValue(waiting ? "esperando enviar" : "")
        // O VoiceOver lia "Selecionado" em todo visto, feito ou não.
        .accessibilityRemoveTraits(done ? [] : .isSelected)
        .accessibilityAddTraits(done ? .isSelected : [])
        .sensoryFeedback(currentDone ? .success : .impact(weight: .light), trigger: tapCount)
    }
  }

  /// O número inteiro selecionado ao entrar no campo, para digitar "10" trocar o
  /// valor em vez de virar "4010". O campo de valor do SwiftUI não expõe a
  /// seleção, então o pedido vai pela cadeia de respostas do UIKit.
  private func selectAllInFocusedField() {
    #if canImport(UIKit)
      DispatchQueue.main.async {
        UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
      }
    #endif
  }

  /// O ladrilho de kg ou reps. A unidade fica no cabeçalho das colunas. Na lista
  /// é uma pílula branca; na sessão, um ladrilho que muda de fundo com o estado
  /// da linha.
  @ViewBuilder
  private func cell<Field: View>(@ViewBuilder field: () -> Field) -> some View {
    switch scale {
    case .list:
      field()
        .padding(8).background(.white, in: .rect(cornerRadius: Radius.field))
    case .session:
      field()
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
  let kind: SetKind
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

/// O aviso de carga estranha, ou nulo quando o número parece certo. Acima do
/// limite do servidor o visto fica desligado; abaixo dele o aviso só pergunta,
/// porque um recorde de verdade também sai do padrão.
/// De onde vem a carga que o campo usa para estranhar um número. O aviso só
/// fala em "última vez" quando a carga veio mesmo da última sessão.
enum WeightReference: Equatable {
  case lastTime(Double)
  case plan(Double)

  var kilograms: Double {
    switch self {
    case .lastTime(let value), .plan(let value): value
    }
  }
}

/// A carga da última vez, senão a do plano. O aquecimento só se compara com
/// aquecimento: a carga de trabalho num aquecimento sem histórico dava aviso falso.
func setReference(_ exercise: DashboardExercise, kind: SetKind, index: Int) -> WeightReference? {
  switch kind {
  case .prep:
    if let last = exercise.previousPrep?.set(index)?.weightKg { return .lastTime(last) }
    return exercise.prepWeightKg.map { .plan($0) }
  case .work:
    if let previous = exercise.previous {
      return .lastTime(previous.set(index)?.weightKg ?? previous.weightKg)
    }
    return .plan(exercise.prescription.startingWeightKg)
  }
}

func weightWarning(_ kilograms: Double?, reference: WeightReference?) -> String? {
  guard let kilograms, kilograms.isFinite else { return nil }
  let ceiling = Limits.setWeightKg.upperBound
  if kilograms > ceiling { return "o limite é \(Formatting.trim(ceiling)) kg" }
  if let reference, reference.kilograms > 0, kilograms > reference.kilograms * 2.5 {
    let base = Formatting.trim(reference.kilograms)
    return switch reference {
    case .lastTime: "\(Formatting.trim(kilograms)) kg? da última vez foi \(base)"
    case .plan: "\(Formatting.trim(kilograms)) kg? o plano é \(base)"
    }
  }
  if kilograms > 400 { return "\(Formatting.trim(kilograms)) kg? confere o número" }
  return nil
}

func weightLabel(_ kilograms: Double) -> String {
  kilograms.formatted(.number.precision(.fractionLength(0...1))) + " kg"
}
