import HenriqueCore
import SwiftUI

/// O mapa de frequência da tela de progresso, no estilo do GitHub. Recebe a
/// frequência já carregada e pede o intervalo do período visível a quem tem
/// o servidor; assim o preview roda com dados fabricados.
struct AttendanceMap: View {
  @Environment(\.locale) private var locale
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var period: AttendancePeriod = .month(containing: .today)
  @State private var grid = AttendanceGrid(period: .month(containing: .today), attendance: [:])
  @State private var answered = false
  let attendance: [CalendarDate: AttendanceDay]
  let load: (CalendarDate, CalendarDate) async -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      AttendanceHeader(period: $period, title: period.title(locale: locale))
      AttendanceCount(total: grid.total, name: period.name(locale: locale), answered: answered)
      // A grade é uma peça só. O que anima é a cor da casa, dentro do
      // `DaySquare`. Uma animação aqui em cima pegaria o layout junto e fazia a
      // fita do ano deslizar de lado até a borda direita ao entrar.
      Group {
        switch period {
        case .month: MonthGrid(grid: grid)
        case .year: YearGrid(grid: grid)
        }
      }
      // A casa é identificada pela data, então trocar de mês troca as trinta e
      // cinco de uma vez e a animação de cor de cada uma nunca chega a correr. A
      // grade inteira atravessa como uma peça só.
      .id(period)
      .transition(.opacity)
      AttendanceLegend()
        .opacity(grid.total > 0 ? 1 : 0)
        .animation(reduceMotion ? Motion.plain : Motion.crossfade, value: grid.total > 0)
    }
    .padding(Space.xl).paperCard()
    .subtleEntrance()
    .onChange(of: period) { grid = AttendanceGrid(period: period, attendance: attendance) }
    .onChange(of: attendance, initial: true) { grid = AttendanceGrid(period: period, attendance: attendance) }
    .task(id: period) {
      let range = period.range()
      await load(range.lowerBound, range.upperBound)
      answered = true
    }
  }
}

private enum AttendanceScope: Hashable {
  case month, year
}

private struct AttendanceHeader: View {
  @Binding var period: AttendancePeriod
  let title: String

  private var scope: Binding<AttendanceScope> {
    Binding {
      if case .month = period { .month } else { .year }
    } set: { scope in
      withAnimation(Motion.swap) {
        switch (scope, period) {
        case (.month, .year(let year)):
          let today = CalendarDate.today
          period = year == today.year ? .month(containing: today) : .month(year: year, month: 12)
        case (.year, .month(let year, _)):
          period = .year(year)
        default:
          break
        }
      }
    }
  }

  private var nextIsFuture: Bool {
    period.next.range().lowerBound > .today
  }

  var body: some View {
    HStack(spacing: 8) {
      Text(title).font(.subheadline).foregroundStyle(Color.ink)
        .lineLimit(1).minimumScaleFactor(0.8)
      Spacer(minLength: 4)
      IconButton(title: "Período anterior", systemImage: "chevron.left", glass: true, nudge: CGSize(width: 1, height: 0)) {
        withAnimation(Motion.swap) { period = period.previous }
      }
      IconButton(title: "Próximo período", systemImage: "chevron.right", glass: true, nudge: CGSize(width: -1, height: 0)) {
        withAnimation(Motion.swap) { period = period.next }
      }
        .disabled(nextIsFuture)
      Picker("Escala", selection: scope) {
        Text("mês").tag(AttendanceScope.month).accessibilityIdentifier("frequencia.mes")
        Text("ano").tag(AttendanceScope.year).accessibilityIdentifier("frequencia.ano")
      }
      .pickerStyle(.segmented).labelsHidden().frame(width: 112)
    }
  }
}

private struct AttendanceCount: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let total: Int
  let name: String
  let answered: Bool

  var body: some View {
    Text(text)
      .font(.title2.weight(.medium)).monospacedDigit().foregroundStyle(Color.ink)
      .contentTransition(.numericText(value: Double(total)))
      .opacity(answered || total > 0 ? 1 : 0)
      .animation(reduceMotion ? nil : .default, value: total)
  }

  private var text: String {
    switch total {
    case 0: "nenhum treino ainda"
    case 1: "1 treino em \(name)"
    default: "\(total) treinos em \(name)"
    }
  }
}

private struct MonthGrid: View {
  @Environment(\.locale) private var locale
  let grid: AttendanceGrid

  /// A inicial sozinha não distingue segunda, sexta e sábado em português, e as
  /// colunas do mês têm largura para as três letras. A identidade continua sendo
  /// o número do dia, porque o texto ainda pode repetir em outro idioma.
  private var weekdayInitials: [(weekday: Int, initial: String)] {
    var calendar = Calendar.autoupdatingCurrent
    calendar.locale = locale
    let symbols = calendar.shortStandaloneWeekdaySymbols
    let first = calendar.firstWeekday - 1
    return (0..<7).map { weekday in ((first + weekday) % 7, symbols[(first + weekday) % 7]) }
  }

  var body: some View {
    VStack(spacing: 4) {
      HStack(spacing: 4) {
        ForEach(weekdayInitials, id: \.weekday) { _, initial in
          Text(initial).font(.caption2).foregroundStyle(Color.mutedInk)
            .textCase(.lowercase).lineLimit(1).minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
        }
      }
      .accessibilityHidden(true)
      ForEach(grid.weeks) { week in
        HStack(spacing: 4) {
          ForEach(week.cells) { cell in
            DaySquare(cell: cell, radius: 6)
              .aspectRatio(1, contentMode: .fit).frame(maxWidth: .infinity)
          }
        }
      }
    }
  }
}

private struct YearGrid: View {
  @Environment(\.locale) private var locale
  let grid: AttendanceGrid
  private let side: CGFloat = 13

  var body: some View {
    ScrollView(.horizontal) {
      HStack(alignment: .top, spacing: 3) {
        ForEach(grid.weeks) { week in
          VStack(spacing: 3) {
            // O rótulo transborda a coluna de propósito: o mês tem quatro
            // semanas de largura e a inicial sozinha confunde janeiro, junho e
            // julho. `fixedSize` impede a abreviação de virar reticências.
            Text(monthName(for: week)).font(.caption2).foregroundStyle(Color.mutedInk)
              .textCase(.lowercase).fixedSize()
              .frame(width: side, height: 14, alignment: .leading).accessibilityHidden(true)
            ForEach(week.cells) { cell in
              DaySquare(cell: cell, radius: 3).frame(width: side, height: side)
            }
          }
        }
      }
    }
    .scrollIndicators(.hidden)
    .defaultScrollAnchor(.trailing)
  }

  private func monthName(for week: AttendanceGrid.Week) -> String {
    guard let first = week.cells.first(where: { $0.date?.day == 1 })?.date else { return "" }
    return first.date().formatted(Date.FormatStyle(locale: locale).month(.abbreviated))
  }
}

private struct DaySquare: View {
  @Environment(\.accent) private var accent
  @Environment(\.locale) private var locale
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let cell: AttendanceGrid.Cell
  let radius: CGFloat

  var body: some View {
    ZStack {
      if let date = cell.date {
        RoundedRectangle(cornerRadius: radius)
          .fill(AttendanceFill.color(level: cell.level, accent: accent))
          // A frequência chega depois da rede. Só a cor atravessa; o quadrado
          // não muda de tamanho nem de lugar.
          .animation(reduceMotion ? nil : Motion.crossfade, value: cell.level)
          .overlay {
            if date == .today {
              RoundedRectangle(cornerRadius: Radius.concentric(radius, padding: 3))
                .strokeBorder(accent.deep, lineWidth: 1.5)
                .padding(-3)
            }
          }
          .accessibilityElement()
          .accessibilityLabel(label(for: date))
      } else {
        Color.clear.accessibilityHidden(true)
      }
    }
  }

  private func label(for date: CalendarDate) -> String {
    let day = date.date().formatted(Date.FormatStyle(locale: locale).day().month(.wide))
    switch cell.workSets {
    case 0: return "\(day), sem treino"
    case 1: return "\(day), 1 série"
    default: return "\(day), \(cell.workSets) séries"
    }
  }
}

private enum AttendanceFill {
  static func color(level: Int, accent: Accent) -> Color {
    switch level {
    case 0: Color.ink.opacity(0.06)
    case 1: accent.base.opacity(0.28)
    case 2: accent.base.opacity(0.5)
    case 3: accent.base.opacity(0.75)
    default: accent.base
    }
  }
}

private struct AttendanceLegend: View {
  @Environment(\.accent) private var accent

  var body: some View {
    HStack(spacing: 4) {
      Text("menos")
      ForEach(0..<5, id: \.self) { level in
        RoundedRectangle(cornerRadius: 3)
          .fill(AttendanceFill.color(level: level, accent: accent))
          .frame(width: 11, height: 11)
      }
      Text("mais")
    }
    .font(.caption2).foregroundStyle(Color.mutedInk)
    .frame(maxWidth: .infinity, alignment: .trailing)
    .accessibilityHidden(true)
  }
}

#if DEBUG
  #Preview("Mapa com dados") {
    ScrollView {
      AttendanceMap(attendance: AttendancePreview.sample) { _, _ in }
        .padding(16)
    }
    .environment(\.locale, Locale(identifier: "pt_BR"))
    .environment(\.accent, Accent.verde)
  }

  private enum AttendancePreview {
    static var sample: [CalendarDate: AttendanceDay] {
      let today = CalendarDate.today
      var days: [CalendarDate: AttendanceDay] = [:]
      for back in 0..<400 {
        let date = today.adding(days: -back)
        // segunda, quarta e sexta treinam; o volume cresce com a semana.
        let weekday = date.weekday()
        guard [1, 3, 5].contains(weekday) else { continue }
        let sets = (back / 7 % 4 + 1) * 4 + weekday
        days[date] = AttendanceDay(date: date, workSets: sets, completed: true)
      }
      return days
    }
  }
#endif
