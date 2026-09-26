import HenriqueCore
import SwiftUI

/// Os recordes recentes. O app já guardava peso e repetição de cada série e nunca
/// tinha dito que alguma delas foi a melhor até hoje.
struct RecordsCard: View {
  @Environment(\.accent) private var accent
  // O selo e a caixa dele crescem juntos, na mesma proporção, senão o texto
  // maior transborda um quadrado que ficou do tamanho de antes.
  @ScaledMetric(relativeTo: .caption) private var badgeSize = 12.0
  @ScaledMetric(relativeTo: .caption) private var medalSize = 42.0
  let records: [PersonalRecord]
  let today: CalendarDate

  var body: some View {
    VStack(alignment: .leading, spacing: Space.m) {
      Text("recordes").font(.title3.weight(.medium)).tracking(-0.6)
      VStack(spacing: Space.s) {
        ForEach(records) { record in row(record) }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func row(_ record: PersonalRecord) -> some View {
    // Pilha sem espaçamento próprio porque ele valeria dos dois lados do Spacer e
    // daria 36 pontos de folga mínima, comendo a largura do nome.
    HStack(spacing: 0) {
      medal(record)
        .foregroundStyle(accent.deep)
        .frame(width: medalSize, height: medalSize)
        .background(Color.surfaceMuted, in: .rect(cornerRadius: medalSize / 3))
        .accessibilityHidden(true)
        .padding(.trailing, 14)
      VStack(alignment: .leading, spacing: 2) {
        Text(record.exerciseName.lowercased())
          .font(.callout.weight(.medium)).lineLimit(1)
        Text(record.summary(today: today))
          .font(.footnote).monospacedDigit().foregroundStyle(Color.mutedInk)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, Space.l).padding(.vertical, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .paperCard(radius: Radius.row)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(spoken(record))
  }

  /// O selo diz o tipo sozinho: "+2,5 kg", "+1 rep" ou a estrela da estreia.
  @ViewBuilder
  private func medal(_ record: PersonalRecord) -> some View {
    if let symbol = record.kind.badgeSymbol {
      Image(systemName: symbol).font(.system(size: badgeSize * 1.5, weight: .semibold))
    } else if let badge = record.kind.badge(delta: record.delta) {
      Text(badge)
        .font(.system(size: badgeSize, weight: .semibold, design: .monospaced))
        .tracking(badgeSize * 0.02)
        .multilineTextAlignment(.center)
    }
  }

  private func spoken(_ record: PersonalRecord) -> String {
    let kind =
      switch record.kind {
      case .carga: "recorde de carga, \(Formatting.trim(record.delta)) kg a mais"
      case .reps: "recorde de repetições, \(Int(record.delta)) a mais"
      case .estreia: "estreia"
      }
    return "\(record.exerciseName.lowercased()), \(kind), \(record.summary(today: today))"
  }
}
