import HenriqueCore
import SwiftUI

/// Um dia da fita. O plano guarda dia da semana, não data, então a fita resolve as
/// duas coisas aqui e a tela só desenha.
struct PlannedDay: Identifiable, Equatable {
  let date: CalendarDate
  let workout: WeekPlanItem?

  var id: String { date.iso }

  var weekdayLabel: String {
    date == CalendarDate.today.adding(days: 1) ? "amanhã" : Formatting.weekday(date)
  }

  var title: String { workout?.name.lowercased() ?? "descanso" }
}

/// Os próximos dias do plano, a partir de `start`. A home começa amanhã: o
/// cartão do dia logo acima já diz o que é hoje.
func plannedDays(from start: CalendarDate, schedule: PlanSchedule, count: Int = 5) -> [PlannedDay] {
  (0..<count).map { offset in
    let date = start.adding(days: offset)
    return PlannedDay(date: date, workout: schedule.workout(on: date))
  }
}

struct NextDaysStrip: View {
  @ScaledMetric(relativeTo: .caption) private var cardWidth = 104.0
  @ScaledMetric(relativeTo: .caption) private var cardHeight = 96.0
  let days: [PlannedDay]
  let onPlan: () -> Void
  let onDay: (CalendarDate) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: Space.m) {
      // Em texto de acessibilidade o título e o atalho não cabem lado a lado e
      // os dois quebravam no meio da palavra; o atalho desce.
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline) {
          heading.fixedSize()
          Spacer()
          planButton.fixedSize()
        }
        VStack(alignment: .leading, spacing: 0) {
          heading
          planButton
        }
      }
      ScrollView(.horizontal) {
        HStack(spacing: Space.s) {
          ForEach(days) { day in
            Button { onDay(day.date) } label: { card(day) }
              .buttonStyle(StudyPressStyle())
          }
        }
        .scrollTargetLayout()
      }
      .scrollIndicators(.hidden)
      .scrollClipDisabled()
      .scrollTargetBehavior(.viewAligned)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var heading: some View {
    SectionHeading(title: "próximos dias", systemImage: "calendar.day.timeline.left")
  }

  private var planButton: some View {
    Button("plano", systemImage: "calendar", action: onPlan)
      .labelStyle(.titleAndIcon)
      .font(.subheadline).buttonStyle(.plain)
      .foregroundStyle(.tint)
      .frame(minHeight: 44).contentShape(.rect)
      .accessibilityIdentifier("hoje.plano")
  }

  private func card(_ day: PlannedDay) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(day.weekdayLabel)
        .font(.caption2.weight(.medium))
        .foregroundStyle(Color.mutedInk)
      Text("\(day.date.day)")
        .font(.title2.weight(.medium)).monospacedDigit().tracking(-1)
        .foregroundStyle(Color.ink)
        .padding(.top, 1)
      Spacer(minLength: Space.s)
      HStack(alignment: .top, spacing: 6) {
        Circle().fill(dot(day)).frame(width: 8, height: 8).padding(.top, 4)
        Text(day.title)
          .font(.caption)
          .foregroundStyle(day.workout == nil ? Color.mutedInk : Color.ink)
          .lineLimit(2).multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(width: cardWidth, alignment: .topLeading)
    .frame(minHeight: cardHeight, alignment: .topLeading)
    .padding(Space.m)
    .background(Color.white, in: .rect(cornerRadius: Radius.tile))
    .overlay(RoundedRectangle(cornerRadius: Radius.tile).strokeBorder(Color.ink.opacity(0.07)))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(day.weekdayLabel), \(day.title)")
  }

  /// A cor é a do treino no plano, a mesma do calendário e da aba do plano.
  private func dot(_ day: PlannedDay) -> Color {
    day.workout?.tone.top ?? Color.ink.opacity(0.18)
  }
}
