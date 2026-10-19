import HenriqueCore
import SwiftUI

struct WeightStepper: View {
  @Binding var weightKg: Double
  var range: ClosedRange<Double> = Limits.setWeightKg
  /// Sobe só pelo stepper. O campo digitado não vibra a cada tecla.
  @State private var steps = 0

  var body: some View {
    AdjustRow(label: "carga") {
      DecimalField(
        placeholder: "0",
        value: Binding(get: { weightKg }, set: { weightKg = ($0 ?? 0).clamped(to: range) }))
        .submitLabel(.done)
        .multilineTextAlignment(.trailing)
        .font(.body.weight(.semibold)).monospacedDigit()
        .frame(width: 72)
        .accessibilityLabel("Carga em kg")
      Text("kg").font(.callout).foregroundStyle(Color.mutedInk)
      Stepper(
        "Ajustar carga",
        value: Binding(get: { weightKg }, set: { weightKg = $0; steps += 1 }),
        in: range, step: 2.5)
        .labelsHidden()
        .accessibilityLabel("Ajustar carga em kg")
    }
    .sensoryFeedback(.selection, trigger: steps)
    .onChange(of: weightKg) { _, new in
      let clamped = new.isFinite ? new.clamped(to: range) : range.lowerBound
      if clamped != new { weightKg = clamped }
    }
  }
}

/// Número com vírgula ou ponto, gravado a cada tecla.
struct DecimalField: View {
  let placeholder: String
  @Binding var value: Double?
  @FocusState private var focused: Bool?

  var body: some View {
    TypedNumberField(
      placeholder: placeholder, value: $value, focus: $focused, field: true,
      parse: parseDecimal, format: formatPrepWeight
    )
    .decimalInput()
  }
}

/// Um número digitado como texto e lido a cada tecla. Com `value:format:` o
/// número só chegava ao valor quando o campo perdia o foco, e tocar em
/// "concluir", "feito" ou no visto com o teclado aberto saía sem ele.
struct TypedNumberField<Value: Equatable, Focus: Hashable>: View {
  let placeholder: String
  @Binding var value: Value?
  let focus: FocusState<Focus?>.Binding
  let field: Focus
  let parse: (String) -> Value?
  let format: (Value) -> String
  @State private var text = ""

  private var focused: Bool { focus.wrappedValue == field }

  var body: some View {
    TextField(placeholder, text: $text)
      .focused(focus, equals: field)
      // Com o campo em foco o texto só segue o valor quando ele mudou por
      // fora, pelo stepper ao lado ou pelo teto da faixa. Senão apagar o
      // campo para digitar de novo faria o "0" voltar.
      .onChange(of: value, initial: true) { _, new in
        let typed = parse(text)
        if !focused || (new != nil && typed != nil && typed != new) {
          text = new.map(format) ?? ""
        }
      }
      .onChange(of: text) { _, new in value = parse(new) }
      .onChange(of: focused) { _, isFocused in
        if !isFocused { text = value.map(format) ?? "" }
      }
  }
}

/// Vírgula ou ponto, porque o teclado decimal em português dá vírgula. Vazio
/// ou ilegível é nulo.
func parseDecimal(_ text: String) -> Double? {
  let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
  guard let value = Double(trimmed), value.isFinite else { return nil }
  return value
}
