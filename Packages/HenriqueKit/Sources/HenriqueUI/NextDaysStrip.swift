import HenriqueCore
import SwiftUI

/// Um dia da fita. O plano guarda dia da semana, não data, então a fita resolve as
/// duas coisas aqui e a tela só desenha.
struct PlannedDay: Identifiable, Equatable {
  let date: CalendarDate
  let workout: WeekPlanItem?
  let isToday: Bool
  let isDone: Bool

  var id: String { date.iso }

  var weekdayLabel: String {
    let name = date.date().formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "pt_BR")))
      .lowercased().replacingOccurrences(of: ".", with: "")
    return isToday ? "\(name) · hoje" : name
  }

  var title: String { workout?.name.lowercased() ?? "descanso" }
}

/// Os próximos cinco dias do plano, a partir de hoje. Responde "o que vem depois"
/// sem abrir a aba do plano, que é a pergunta seguinte a "o que eu faço agora".
func plannedDays(from today: CalendarDate, plan: [WeekPlanItem], done: Set<CalendarDate>, count: Int = 5) -> [PlannedDay] {
  (0..<count).map { offset in
    let date = today.adding(days: offset)
    let weekday = date.weekday()
    return PlannedDay(
      date: date,
      workout: plan.first { $0.weekdays.contains(weekday) },
      isToday: offset == 0,
      isDone: done.contains(date))
  }
}

struct NextDaysStrip: View {
  let days: [PlannedDay]
  let plan: [WeekPlanItem]
  let onPlan: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: Space.m) {
      HStack(alignment: .firstTextBaseline) {
        Text("próximos dias").font(.title3.weight(.medium)).tracking(-0.6)
        Spacer()
        Button("plano", action: onPlan).font(.subheadline).buttonStyle(.plain)
          .foregroundStyle(Color.accentColor)
          .accessibilityIdentifier("hoje.plano")
      }
      ScrollView(.horizontal) {
        HStack(spacing: Space.s) {
          ForEach(days) { day in card(day) }
        }
        .scrollTargetLayout()
      }
      .scrollIndicators(.hidden)
      .scrollClipDisabled()
      .scrollTargetBehavior(.viewAligned)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func card(_ day: PlannedDay) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(day.weekdayLabel)
        .font(.caption2.weight(.medium))
        .foregroundStyle(day.isToday ? Color.white.opacity(0.62) : Color.mutedInk)
      Text("\(day.date.day)")
        .font(.title2.weight(.medium)).monospacedDigit().tracking(-1)
        .foregroundStyle(day.isToday ? .white : Color.ink)
        .padding(.top, 1)
      Spacer(minLength: Space.s)
      HStack(spacing: 6) {
        Circle().fill(dot(day)).frame(width: 8, height: 8)
        Text(day.title)
          .font(.caption)
          .foregroundStyle(day.isToday ? Color.white.opacity(0.86)
            : day.workout == nil ? Color.mutedInk : Color.ink)
          .lineLimit(2).multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
      }
      if day.isDone {
        Label("feito", systemImage: "checkmark")
          .font(.caption2.weight(.medium)).labelStyle(.titleAndIcon)
          .foregroundStyle(day.isToday ? Color.white.opacity(0.7) : Color.mutedInk)
          .padding(.top, 4)
      }
    }
    .frame(width: 104, height: 96, alignment: .topLeading)
    .padding(Space.m)
    .background(day.isToday ? AnyShapeStyle(Color.ink) : AnyShapeStyle(Color.white),
      in: .rect(cornerRadius: Radius.tile))
    .overlay(RoundedRectangle(cornerRadius: Radius.tile)
      .strokeBorder(Color.ink.opacity(day.isToday ? 0 : 0.07)))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(day.weekdayLabel), \(day.title)")
  }

  /// A cor é a do treino no plano, a mesma do calendário e da aba do plano. Sem cor
  /// escolhida, cai no tom da posição, que é o que o resto do app também faz.
  private func dot(_ day: PlannedDay) -> Color {
    guard let workout = day.workout else { return Color.ink.opacity(0.18) }
    if let hex = workout.color, let tone = WorkoutTone.from(hex: hex) { return tone.top }
    let position = plan.firstIndex { $0.id == workout.id } ?? 0
    return WorkoutTone.at(position).top
  }
}
