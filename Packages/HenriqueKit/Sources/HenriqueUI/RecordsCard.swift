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
    let badge = record.kind.badge(delta: record.delta)
    // Pilha sem espaçamento próprio porque ele valeria dos dois lados do Spacer e
    // daria 36 pontos de folga mínima antes do chip, comendo a largura do nome.
    return HStack(spacing: 0) {
      Text(badge)
        .font(.system(size: badgeSize, weight: .semibold, design: .monospaced))
        .tracking(badgeSize * 0.02)
        .multilineTextAlignment(.center)
        .foregroundStyle(accent.deep)
        .frame(width: medalSize, height: medalSize)
        .background(Color.surfaceMuted, in: .rect(cornerRadius: medalSize / 3))
        .accessibilityLabel(badge.replacingOccurrences(of: "\n", with: " "))
        .padding(.trailing, 14)
      VStack(alignment: .leading, spacing: 2) {
        Text(record.exerciseName.lowercased())
          .font(.callout.weight(.medium)).lineLimit(1)
        Text(record.summary(today: today))
          .font(.footnote).monospacedDigit().foregroundStyle(Color.mutedInk)
      }
      Spacer(minLength: 14)
      Text(record.kind.label)
        .font(.footnote.weight(.semibold)).foregroundStyle(accent.base)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(accent.pale, in: .capsule)
    }
    .padding(.horizontal, Space.l).padding(.vertical, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .paperCard(radius: Radius.row)
    .accessibilityElement(children: .combine)
  }
}
