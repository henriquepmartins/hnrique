import HenriqueCore
import SwiftUI

struct DayStrip: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var textSize
  @Namespace private var selection
  @State private var anchor = CalendarDate.today
  /// A segunda de cada semana da fita. Cada semana é uma página inteira.
  @State private var weeks: [CalendarDate] = []
  @State private var visible: CalendarDate?
  let selected: CalendarDate
  @Binding var notch: CGFloat

  /// A fita nasce montada e já na semana do dia escolhido. Enquanto os dias e a
  /// posição vinham do `onAppear`, o primeiro quadro tinha a fita vazia e o
  /// seguinte tinha 181 dias com o scroll voando até o meio, então quem abria o
  /// app via a linha se construir de lado antes de parar.
  ///
  /// Cada página é uma semana de segunda a domingo, a mesma semana da sequência
  /// e do calendário do plano.
  init(selected: CalendarDate, notch: Binding<CGFloat>) {
    self.selected = selected
    _notch = notch
    _anchor = State(initialValue: selected)
    _weeks = State(initialValue: Self.window(around: selected))
    _visible = State(initialValue: selected.trainingWeekStart())
  }

  /// Treze semanas para cada lado.
  private static func window(around day: CalendarDate) -> [CalendarDate] {
    let monday = day.trainingWeekStart()
    return (-13...13).map { monday.adding(days: $0 * 7) }
  }

  /// Dias com ao menos uma série valendo. Hoje conta pelo painel, que já tem a
  /// série marcada antes da frequência do servidor saber dela.
  private func trained(_ day: CalendarDate) -> Bool {
    store.attendance[day].map { $0.workSets > 0 } == true
      || store.dashboard?.hasAttended(on: day) == true
  }

  private var selectionAnimation: Animation { Motion.tap }

  /// A semana na tela, pela quinta: numa semana que vira o mês, o rótulo fica
  /// com o mês que tem mais dias nela.
  private var shownMonth: CalendarDate {
    (visible ?? selected.trainingWeekStart()).adding(days: 3)
  }

  private var awayFromToday: Bool {
    selected != .today || (visible ?? selected.trainingWeekStart()) != CalendarDate.today.trainingWeekStart()
  }

  private var backButton: some View {
    Button { move(-7) } label: { Image(systemName: "chevron.left").offset(x: 1) }
      .accessibilityLabel("Voltar uma semana").buttonStyle(.glass).controlSize(.large)
  }

  private var forwardButton: some View {
    Button { move(7) } label: { Image(systemName: "chevron.right").offset(x: -1) }
      .accessibilityLabel("Avançar uma semana").buttonStyle(.glass).controlSize(.large)
  }

  private var monthButton: some View {
    Button { moveTo(.today) } label: {
      Label(
        shownMonth.date().formatted(.dateTime.month(.wide).year()),
        systemImage: awayFromToday ? "arrow.uturn.backward" : "calendar"
      )
      .font(.subheadline).foregroundStyle(Color.ink)
      .lineLimit(1).minimumScaleFactor(0.6)
      .contentTransition(.symbolEffect(.replace))
      .frame(minHeight: 44).contentShape(.rect)
    }.buttonStyle(StudyPressStyle()).accessibilityLabel("Ir para hoje")
      .accessibilityValue(shownMonth.date().formatted(.dateTime.month(.wide).year()))
  }

  var body: some View {
    VStack(spacing: 12) {
      // Em texto de acessibilidade o mês espremido entre os dois botões saía
      // em cinco linhas ("out- / ubro / de / 202 / 6"); ele sobe para a dele.
      if textSize.isAccessibilitySize {
        monthButton
        HStack {
          backButton
          Spacer()
          forwardButton
        }
      } else {
        HStack {
          backButton
          Spacer()
          monthButton
          Spacer()
          forwardButton
        }
      }
      ScrollView(.horizontal) {
        LazyHStack(spacing: 0) {
          ForEach(weeks, id: \.self) { monday in
            HStack(spacing: 0) {
              ForEach(0..<7, id: \.self) { offset in
                let day = monday.adding(days: offset)
                DayChip(day: day, isSelected: day == selected, trained: trained(day), selection: selection) {
                  moveTo(day)
                }
                .frame(maxWidth: .infinity)
                // Só a casa escolhida informa a posição. As outras devolvem nil,
                // que nunca muda, e rolar a fita não chama a ação de 189 casas.
                .onGeometryChange(for: CGFloat?.self) { geometry in
                  day == selected ? geometry.frame(in: .named("days")).midX : nil
                } action: { old, midpoint in
                  guard let midpoint else { return }
                  let animation = old == nil && !reduceMotion ? selectionAnimation : nil
                  withAnimation(animation) { updateNotch(midpoint: midpoint) }
                }
              }
            }
            .containerRelativeFrame(.horizontal)
            .id(monday)
          }
        }
        .scrollTargetLayout()
        .animation(reduceMotion ? nil : selectionAnimation, value: selected)
        .sensoryFeedback(.selection, trigger: selected)
      }
      .coordinateSpace(.named("days"))
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
      .scrollIndicators(.hidden)
      .scrollPosition(id: $visible)
      .scrollTargetBehavior(.viewAligned)
      .frame(height: 76)
      // A altura da fita é fixa para as páginas de semana caberem lado a lado. O
      // VoiceOver lê a data inteira de cada dia, então o texto para de crescer
      // antes de estourar o círculo.
      .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
      .onChange(of: selected) {
        let week = selected.trainingWeekStart()
        if !weeks.contains(week) { resetWindow(around: selected) }
        guard visible != week else { return }
        withAnimation(reduceMotion ? nil : selectionAnimation) { visible = week }
      }
      .task(id: visible) {
        guard let visible else { return }
        await store.loadAttendance(from: visible, to: visible.adding(days: 6))
      }
    }
  }

  @State private var width: CGFloat = 1
  private func updateNotch(midpoint: CGFloat) { notch = min(max(midpoint / max(width, 1), 0), 1) }
  private func resetWindow(around day: CalendarDate) {
    anchor = day
    weeks = Self.window(around: day)
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
  /// Dia com série valendo. Um círculo claro atrás do número, que some sob o
  /// círculo cheio da seleção.
  let trained: Bool
  let selection: Namespace.ID
  let onTap: () -> Void
  var body: some View {
    Button(action: onTap) {
      VStack(spacing: 10) {
        Text(Formatting.weekday(day))
          .font(.caption2).foregroundStyle(isSelected ? accent.deep : Color.mutedInk)
          .lineLimit(1).minimumScaleFactor(0.5)
        Text("\(day.day)").font(.body.weight(isSelected ? .semibold : .regular))
          .frame(width: 40, height: 40)
          .foregroundStyle(isSelected ? .white : Color.ink)
          .background {
            if trained {
              Circle().fill(accent.base.opacity(0.16))
            }
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
        Text("\(day.date(), format: .dateTime.weekday(.wide).day().month(.wide))\(day == .today ? ", hoje" : "")\(trained ? ", treinou" : "")"))
      .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

