import HenriqueCore
import SwiftUI

/// Quantos dos treinos que o plano marca para esta semana já foram feitos. Quilos
/// somados não dizem nada a quem levanta; "4 de 5 treinos" diz se a semana está
/// em dia.
struct WeeklyAdherenceCard: View {
  @Environment(\.accent) private var accent
  @ScaledMetric(relativeTo: .largeTitle) private var numberSize = 40.0
  @ScaledMetric(relativeTo: .title3) private var unitSize = 19.0
  @ScaledMetric(relativeTo: .caption2) private var daySize = 11.0
  let plan: [WeekPlanItem]
  let done: Set<CalendarDate>
  let today: CalendarDate

  var body: some View {
    VStack(alignment: .leading, spacing: Space.m) {
      Text("esta semana").font(.title3.weight(.medium)).tracking(-0.6)
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
          Text("\(doneCount)")
            .font(.system(size: numberSize, weight: .semibold)).monospacedDigit()
            .tracking(numberSize * -0.055)
          Text("de \(slots.count) \(slots.count == 1 ? "treino" : "treinos")")
            .font(.system(size: unitSize, weight: .semibold))
            .foregroundStyle(Color.mutedInk)
        }
        HStack(spacing: 10) {
          ForEach(slots) { slot in
            VStack(spacing: 6) {
              Circle()
                .fill(slot.isDone ? accent.base : Color.ink.opacity(0.14))
                .frame(width: 10, height: 10)
                .overlay {
                  if slot.date == today {
                    Circle().strokeBorder(accent.deep, lineWidth: 1.5).padding(-3)
                  }
                }
              Text(dayInitial(slot.date))
                .font(.system(size: daySize, design: .monospaced))
                .tracking(daySize * 0.01)
                .foregroundStyle(Color.mutedInk)
            }
          }
        }
        Text(caption).font(.footnote)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Space.xl)
      .paperCard(radius: Radius.tile)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("\(doneCount) de \(slots.count) treinos nesta semana")
      .accessibilityValue(String(caption.characters))
      .accessibilityIdentifier("hoje.aderencia")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private struct PlannedSlot: Identifiable {
    let date: CalendarDate
    let workout: WeekPlanItem
    let isDone: Bool
    var id: String { date.iso }
  }

  /// Os dias da semana de `today`, de segunda a domingo, só os que têm treino no
  /// plano. Treino sem dia marcado não entra porque não há dia para cobrar.
  private var slots: [PlannedSlot] {
    let monday = today.adding(days: -((today.weekday() + 6) % 7))
    return (0..<7).compactMap { offset in
      let date = monday.adding(days: offset)
      guard let workout = plan.first(where: { $0.weekdays.contains(date.weekday()) }) else {
        return nil
      }
      return PlannedSlot(date: date, workout: workout, isDone: done.contains(date))
    }
  }

  private var doneCount: Int { slots.filter(\.isDone).count }

  private var caption: AttributedString {
    let pending = slots.filter { !$0.isDone }
    if pending.isEmpty, !slots.isEmpty { return muted("semana fechada") }
    if let todaySlot = pending.first(where: { $0.date == today }) {
      return highlighted(todaySlot.workout.name) + muted(" é hoje")
    }
    if pending.count == 1 { return muted("falta ") + highlighted(pending[0].workout.name) }
    return muted("faltam \(pending.count) treinos")
  }

  private func muted(_ text: String) -> AttributedString {
    var part = AttributedString(text)
    part.foregroundColor = Color.mutedInk
    return part
  }

  private func highlighted(_ name: String) -> AttributedString {
    var part = AttributedString(name.lowercased())
    part.foregroundColor = accent.base
    part.font = .footnote.weight(.semibold)
    return part
  }

  private func dayInitial(_ date: CalendarDate) -> String {
    date.date().formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "pt_BR")))
      .lowercased()
      .replacingOccurrences(of: ".", with: "")
  }
}
