import HenriqueCore
import SwiftUI

/// Os recordes recentes. O app já guardava peso e repetição de cada série e nunca
/// tinha dito que alguma delas foi a melhor até hoje.
struct RecordsCard: View {
  @Environment(\.accent) private var accent
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
    HStack(spacing: Space.m) {
      Text(record.kind.badge(delta: record.delta))
        .font(.caption.weight(.semibold)).monospacedDigit()
        .multilineTextAlignment(.center)
        .foregroundStyle(accent.deep)
        .frame(width: 46, height: 46)
        .background(accent.base.opacity(0.14), in: .rect(cornerRadius: Radius.field + 4))
      VStack(alignment: .leading, spacing: 2) {
        Text(record.exerciseName.lowercased())
          .font(.callout).lineLimit(1)
        Text(record.summary(today: today))
          .font(.footnote).monospacedDigit().foregroundStyle(Color.mutedInk)
      }
      Spacer(minLength: Space.s)
      Text(record.kind.label)
        .font(.caption.weight(.medium)).foregroundStyle(accent.deep)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(accent.base.opacity(0.14), in: .capsule)
    }
    .padding(.horizontal, Space.l).padding(.vertical, Space.m)
    .frame(maxWidth: .infinity, alignment: .leading)
    .paperCard(radius: Radius.tile)
    .accessibilityElement(children: .combine)
  }
}
