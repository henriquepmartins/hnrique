import HenriqueCore
import SwiftUI

struct WeightStepper: View {
  @Binding var weightKg: Double
  var range: ClosedRange<Double> = Limits.setWeightKg

  var body: some View {
    HStack(spacing: 8) {
      Text("carga").font(.body)
      Spacer(minLength: 8)
      DecimalField(
        placeholder: "0",
        value: Binding(get: { weightKg }, set: { weightKg = ($0 ?? 0).clamped(to: range) }))
        .submitLabel(.done)
        .multilineTextAlignment(.trailing)
        .font(.body.weight(.semibold)).monospacedDigit()
        .frame(minWidth: 64)
        .accessibilityLabel("Carga em kg")
      Text("kg").font(.callout).foregroundStyle(Color.mutedInk)
      Stepper("Ajustar carga", value: $weightKg, in: range, step: 2.5)
        .labelsHidden()
        .accessibilityLabel("Ajustar carga em kg")
    }
    .frame(minHeight: 48)
    .onChange(of: weightKg) { _, new in
      let clamped = new.isFinite ? new.clamped(to: range) : range.lowerBound
      if clamped != new { weightKg = clamped }
    }
  }
}

/// Número com vírgula ou ponto, gravado a cada tecla. Com `value:format:` o
/// número só chegava ao valor quando o campo perdia o foco, e tocar em
/// "concluir" ou "continuar" com o teclado aberto saía sem ele.
struct DecimalField: View {
  let placeholder: String
  @Binding var value: Double?
  @State private var text = ""
  @FocusState private var focused: Bool

  var body: some View {
    TextField(placeholder, text: $text)
      .focused($focused)
      .decimalInput()
      // Com o campo em foco o texto só segue o valor quando ele mudou por
      // fora, pelo stepper ao lado ou pelo teto da faixa. Senão apagar o
      // campo para digitar de novo faria o "0" voltar.
      .onChange(of: value, initial: true) { _, new in
        let typed = parseDecimal(text)
        if !focused || (new != nil && typed != nil && typed != new) {
          text = new.map(formatPrepWeight) ?? ""
        }
      }
      .onChange(of: text) { _, new in value = parseDecimal(new) }
      .onChange(of: focused) { _, isFocused in
        if !isFocused { text = value.map(formatPrepWeight) ?? "" }
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
