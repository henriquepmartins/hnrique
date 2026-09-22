import HenriqueCore
import SwiftUI

struct DayStrip: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var selection
  @State private var anchor = CalendarDate.today
  @State private var days: [CalendarDate] = []
  @State private var visible: CalendarDate?
  let selected: CalendarDate
  @Binding var notch: CGFloat

  /// A fita nasce montada e já centrada no dia escolhido. Enquanto os dias e a
  /// posição vinham do `onAppear`, o primeiro quadro tinha a fita vazia e o
  /// seguinte tinha 181 dias com o scroll voando até o meio, então quem abria o
  /// app via a linha se construir de lado antes de parar.
  init(selected: CalendarDate, notch: Binding<CGFloat>) {
    self.selected = selected
    _notch = notch
    _anchor = State(initialValue: selected)
    _days = State(initialValue: (-90...90).map { selected.adding(days: $0) })
    _visible = State(initialValue: selected)
  }

  private var selectionAnimation: Animation {
    .interpolatingSpring(mass: 1, stiffness: 900, damping: 48)
  }

  var body: some View {
    VStack(spacing: 12) {
      HStack {
        Button { move(-7) } label: { Image(systemName: "chevron.left").offset(x: 1) }
          .accessibilityLabel("Voltar uma semana").buttonStyle(.glass).controlSize(.large)
        Spacer()
        Button { moveTo(.today) } label: {
          Label(selected.date().formatted(.dateTime.month(.wide).year()), systemImage: "calendar")
            .font(.subheadline).foregroundStyle(Color.ink)
            .frame(minHeight: 44).contentShape(.rect)
        }.buttonStyle(StudyPressStyle()).accessibilityLabel("Ir para hoje")
        Spacer()
        Button { move(7) } label: { Image(systemName: "chevron.right").offset(x: -1) }
          .accessibilityLabel("Avançar uma semana").buttonStyle(.glass).controlSize(.large)
      }
      ScrollView(.horizontal) {
        LazyHStack(spacing: 0) {
          ForEach(days, id: \.self) { day in
            DayChip(day: day, isSelected: day == selected, selection: selection) {
              moveTo(day)
            }
            .containerRelativeFrame(.horizontal, count: 7, spacing: 0)
            .onGeometryChange(for: SelectedDayPosition.self) { geometry in
              SelectedDayPosition(midpoint: geometry.frame(in: .named("days")).midX, selected: day == selected)
            } action: { oldPosition, position in
              guard position.selected else { return }
              let animation = !oldPosition.selected && !reduceMotion ? selectionAnimation : nil
              withAnimation(animation) { updateNotch(midpoint: position.midpoint) }
            }
            .id(day)
          }
        }
        .scrollTargetLayout()
        .animation(reduceMotion ? .easeOut(duration: 0.16) : selectionAnimation, value: selected)
        .sensoryFeedback(.selection, trigger: selected)
      }
      .coordinateSpace(.named("days"))
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
      .scrollIndicators(.hidden)
      .scrollPosition(id: $visible, anchor: .center)
      .scrollTargetBehavior(.viewAligned)
      .frame(height: 76)
      .onChange(of: selected) {
        if !days.contains(selected) { resetWindow(around: selected) }
        withAnimation(reduceMotion ? nil : selectionAnimation) {
          if let visible, abs(selected.date().timeIntervalSince(visible.date())) > 3 * 86400 {
            self.visible = selected
          }
        }
      }
    }
  }

  @State private var width: CGFloat = 1
  private func updateNotch(midpoint: CGFloat) { notch = min(max(midpoint / max(width, 1), 0), 1) }
  private func resetWindow(around day: CalendarDate) {
    anchor = day
    days = (-90...90).map { day.adding(days: $0) }
  }
  private func move(_ offset: Int) { moveTo(selected.adding(days: offset)) }
  private func moveTo(_ day: CalendarDate) {
    if abs(day.date().timeIntervalSince(anchor.date())) > 80 * 86400 { resetWindow(around: day) }
    Task { await store.select(date: day) }
  }
}

struct DayChip: View {
  @Environment(\.accent) private var accent
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let day: CalendarDate
  let isSelected: Bool
  let selection: Namespace.ID
  let onTap: () -> Void
  var body: some View {
    Button(action: onTap) {
      VStack(spacing: 10) {
        Text(day.date(), format: .dateTime.weekday(.abbreviated))
          .font(.caption2).foregroundStyle(isSelected ? accent.deep : Color.mutedInk)
        Text("\(day.day)").font(.body.weight(isSelected ? .semibold : .regular))
          .frame(width: 40, height: 40)
          .foregroundStyle(isSelected ? .white : Color.ink)
          .background {
            if reduceMotion {
              Circle().fill(accent.base).opacity(isSelected ? 1 : 0)
            } else if isSelected {
              Circle()
                .fill(accent.base)
                .matchedGeometryEffect(id: "selected-day", in: selection)
                .transition(.identity)
            }
          }
          // A bolinha cai inteira fora do círculo da seleção, então ela é sempre
          // da cor do acento. Branca, ela só se veria no dia selecionado, e
          // mesmo ali metade dela já estaria sobre o fundo da tela.
          .overlay(alignment: .bottom) {
            if day == .today {
              Circle()
                .fill(accent.base)
                .frame(width: 4, height: 4)
                .offset(y: 6)
                .accessibilityHidden(true)
            }
          }
      }.frame(maxWidth: .infinity).contentShape(.rect)
    }.buttonStyle(StudyPressStyle())
      .accessibilityLabel(
        Text(day.date(), format: .dateTime.weekday(.wide).day().month(.wide))
          + Text(day == .today ? ", hoje" : ""))
      .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

private struct SelectedDayPosition: Equatable {
  let midpoint: CGFloat
  let selected: Bool
}
