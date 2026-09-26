import HenriqueCore
import SwiftUI

/// Quantos dos treinos que o plano marca para esta semana já foram feitos. Quilos
/// somados não dizem nada a quem levanta; "4 de 5 treinos" diz se a semana está
/// em dia. A conta é a de `TrainingWeek`, a mesma da sequência e do calendário.
struct WeeklyAdherenceCard: View {
  @Environment(\.accent) private var accent
  @ScaledMetric(relativeTo: .largeTitle) private var numberSize = 40.0
  @ScaledMetric(relativeTo: .title3) private var unitSize = 19.0
  @ScaledMetric(relativeTo: .caption2) private var daySize = 11.0
  let week: TrainingWeek
  let today: CalendarDate

  var body: some View {
    VStack(alignment: .leading, spacing: Space.m) {
      Text("esta semana").font(.title3.weight(.medium)).tracking(-0.6)
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
          Text("\(week.done)")
            .font(.system(size: numberSize, weight: .semibold)).monospacedDigit()
            .tracking(numberSize * -0.055)
          Text("de \(week.planned) \(week.planned == 1 ? "treino" : "treinos")")
            .font(.system(size: unitSize, weight: .semibold))
            .foregroundStyle(Color.mutedInk)
        }
        HStack(spacing: 10) {
          ForEach(week.slots) { slot in
            VStack(spacing: 6) {
              dot(slot.state)
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
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Space.xl)
      .paperCard(radius: Radius.tile)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("\(week.done) de \(week.planned) treinos nesta semana")
      .accessibilityValue(spokenState)
      .accessibilityIdentifier("hoje.aderencia")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// Feito cheio, perdido tracejado, o que falta apagado.
  @ViewBuilder
  private func dot(_ state: TrainingWeek.State) -> some View {
    switch state {
    case .done:
      Circle().fill(accent.base)
    case .missed:
      Circle().strokeBorder(Color.ink.opacity(0.4), style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
    case .today, .upcoming:
      Circle().fill(Color.ink.opacity(0.14))
    }
  }

  private var spokenState: String {
    guard week.done < week.planned else { return "semana fechada" }
    var parts: [String] = []
    if let today = week.slots.first(where: { $0.state == .today }) {
      parts.append("\(today.workout.name.lowercased()) é hoje")
    }
    let missed = week.slots.count { $0.state == .missed }
    if missed > 0 { parts.append(missed == 1 ? "1 perdido" : "\(missed) perdidos") }
    return parts.joined(separator: ", ")
  }

  private func dayInitial(_ date: CalendarDate) -> String {
    date.date().formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "pt_BR")))
      .lowercased()
      .replacingOccurrences(of: ".", with: "")
  }
}
