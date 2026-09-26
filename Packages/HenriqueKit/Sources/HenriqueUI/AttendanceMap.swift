import HenriqueCore
import SwiftUI

/// O mapa de frequência da tela de progresso, no estilo do GitHub. Recebe a
/// frequência já carregada e pede o intervalo do período visível a quem tem
/// o servidor; assim o preview roda com dados fabricados.
struct AttendanceMap: View {
  @Environment(\.locale) private var locale
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var period: AttendancePeriod = .year(CalendarDate.today.year)
  @State private var grid = AttendanceGrid(period: .year(CalendarDate.today.year), attendance: [:])
  @State private var answered = false
  @State private var loaded: AttendancePeriod?
  let attendance: [CalendarDate: AttendanceDay]
  let load: (CalendarDate, CalendarDate) async -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      AttendanceHeader(period: $period, title: period.title(locale: locale))
      AttendanceCount(total: grid.total, name: period.name(locale: locale), answered: answered)
      // Trocar de período monta a grade de novo, e a onda de entrada corre outra
      // vez. As casas só nascem quando a frequência daquele período chegou;
      // antes disso a grade pulsa vazia, com o mesmo desenho.
      AttendanceGraph(grid: grid, ready: loaded == period, scrolls: period.isYear)
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
      loaded = period
    }
  }
}

extension AttendancePeriod {
  fileprivate var isYear: Bool {
    if case .year = self { true } else { false }
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

/// As medidas da grade do GitHub Graph do unlumen, em pontos: casa de 18, vão de
/// 4 e canto de 3. A posição de uma casa sai só do índice da semana e do dia, e
/// é isso que deixa o toque achar a casa sem medir nada.
private enum GraphMetrics {
  static let side: CGFloat = 18
  static let gap: CGFloat = 4
  static let radius: CGFloat = 3
  static var pitch: CGFloat { side + gap }
}

/// A casa sob o dedo, pela coluna da semana e pela linha do dia.
private struct GraphFocus: Equatable {
  let week: Int
  let day: Int
}

/// A grade no desenho do GitHub Graph: uma coluna por semana, sete dias
/// descendo. As animações são as do componente, convertidas para SwiftUI:
/// a onda de entrada, a cintilação contínua, o brilho em volta da casa tocada e
/// o balão que corre de casa em casa.
private struct AttendanceGraph: View {
  @Environment(\.locale) private var locale
  @State private var focus: GraphFocus?
  @State private var scrubbed = false
  /// O trecho da fita do ano que está na tela, em coordenadas da grade.
  @State private var viewport: CGRect?
  let grid: AttendanceGrid
  let ready: Bool
  let scrolls: Bool

  /// Como no componente, a grade para na semana de hoje. O resto do ano ainda
  /// não aconteceu, e com a fita ancorada à direita ele empurraria os treinos
  /// para fora da tela.
  private var weeks: [AttendanceGrid.Week] {
    grid.weeks.filter { $0.start <= .today }
  }

  var body: some View {
    if scrolls {
      ScrollView(.horizontal) {
        board.padding(.vertical, Space.s)
      }
      .scrollIndicators(.hidden)
      .defaultScrollAnchor(.trailing)
      .onScrollGeometryChange(for: CGRect.self, of: \.visibleRect) { _, visible in
        viewport = visible
      }
    } else {
      board.padding(.vertical, Space.s)
    }
  }

  private var board: some View {
    HStack(alignment: .top, spacing: GraphMetrics.gap) {
      ForEach(Array(weeks.enumerated()), id: \.element.id) { week, column in
        VStack(spacing: GraphMetrics.gap) {
          ForEach(Array(column.cells.enumerated()), id: \.element.id) { day, cell in
            GraphCell(
              cell: cell, week: week, day: day, ready: ready,
              glow: glow(week: week, day: day)
            )
          }
        }
      }
    }
    .overlay(alignment: .topLeading) {
      tooltip.animation(.easeOut(duration: 0.12), value: focus == nil)
    }
    .contentShape(Rectangle())
    // Um toque abre ou fecha a casa. Segurar e arrastar percorre as casas, e
    // corre junto com o toque: numa combinação exclusiva dentro da ScrollView o
    // toque nunca chegava. O arrasto só começa depois do toque longo, então rolar
    // a fita do ano continua com a ScrollView.
    .onTapGesture { point in
      let picked = cell(at: point)
      if scrubbed {
        scrubbed = false
        focus = picked
      } else {
        focus = picked == focus ? nil : picked
      }
    }
    .simultaneousGesture(scrub)
    .sensoryFeedback(.selection, trigger: focus) { _, new in new != nil }
    .accessibilityElement(children: .contain)
  }

  private var scrub: some Gesture {
    LongPressGesture(minimumDuration: 0.2)
      .sequenced(before: DragGesture(minimumDistance: 0))
      .onChanged { value in
        if case .second(true, let drag) = value {
          // Marca que este toque foi longo, para o toque simples que dispara ao
          // soltar não fechar a casa que o arrasto acabou de abrir.
          scrubbed = true
          if let drag, let picked = cell(at: drag.location) { focus = picked }
        }
      }
  }

  private func cell(at point: CGPoint) -> GraphFocus? {
    let week = Int(point.x / GraphMetrics.pitch)
    let day = Int(point.y / GraphMetrics.pitch)
    guard weeks.indices.contains(week), (0..<7).contains(day),
      weeks[week].cells[day].date != nil
    else { return nil }
    return GraphFocus(week: week, day: day)
  }

  /// A onda de brilho do componente: quem está a menos de três casas da casa
  /// tocada acende, mais forte quanto mais perto.
  private func glow(week: Int, day: Int) -> Double {
    guard let focus else { return 0 }
    let distance = hypot(Double(week - focus.week), Double(day - focus.day))
    return max(0, 1 - distance / 3)
  }

  @ViewBuilder private var tooltip: some View {
    if let focus, let date = weeks[focus.week].cells[focus.day].date {
      // Nas duas primeiras linhas o balão desce, porque em cima não cabe dentro
      // da fita. Na horizontal ele para 80 pontos antes da borda do trecho
      // visível, que é um pouco mais que meio balão; senão a ScrollView corta.
      let above = focus.day >= 2
      let center = CGFloat(focus.week) * GraphMetrics.pitch + GraphMetrics.side / 2
      let lower = (viewport?.minX ?? 0) + 80
      let upper = viewport.map { $0.maxX - 80 } ?? .infinity
      let x = lower <= upper ? min(max(center, lower), upper) : center
      let top = CGFloat(focus.day) * GraphMetrics.pitch
      let y = above ? top - 9 : top + GraphMetrics.side + 9
      Text(tooltipText(date: date, sets: weeks[focus.week].cells[focus.day].workSets))
        .font(.footnote.weight(.medium)).monospacedDigit()
        .foregroundStyle(Color.canvas)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.ink, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.ink.opacity(0.15), lineWidth: 1))
        .fixedSize()
        // Um quadro de tamanho zero com o balão alinhado pela base (ou pelo
        // topo) põe a ponta do balão exatamente em (x, y).
        .frame(width: 0, height: 0, alignment: above ? .bottom : .top)
        .animation(.interpolatingSpring(mass: 1, stiffness: 620, damping: 42)) {
          $0.offset(x: x, y: y)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: above ? .bottom : .top)))
    }
  }

  private func tooltipText(date: CalendarDate, sets: Int) -> String {
    let day = date.date().formatted(Date.FormatStyle(locale: locale).day().month(.abbreviated))
    switch sets {
    case 0: return "sem treino · \(day)"
    case 1: return "1 série · \(day)"
    default: return "\(sets) séries · \(day)"
    }
  }
}

/// Uma casa. Três camadas de movimento, cada uma com a sua curva, como no
/// componente: a entrada em onda (opacidade, subida de 4 pontos e escala de
/// 0.35), a cintilação que não para e o brilho da onda de toque.
private struct GraphCell: View {
  @Environment(\.accent) private var accent
  @Environment(\.locale) private var locale
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var shown = false
  @State private var twinkling = false
  let cell: AttendanceGrid.Cell
  let week: Int
  let day: Int
  let ready: Bool
  let glow: Double

  var body: some View {
    Group {
      if cell.date != nil {
        if ready { square } else { SkeletonSquare(week: week, day: day) }
      } else {
        Color.clear
      }
    }
    .frame(width: GraphMetrics.side, height: GraphMetrics.side)
    // O elemento de acessibilidade é o quadro fixo de 18 pontos, não o quadrado
    // que cintila. Com a escala animando para sempre, o quadro do elemento mudava
    // a cada frame, e o VoiceOver e o XCUITest nunca achavam a árvore parada.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
    .accessibilityHidden(cell.date == nil || !ready)
  }

  private var accessibilityText: String {
    guard let date = cell.date else { return "" }
    return label(for: date)
  }

  private var square: some View {
    let visible = shown || reduceMotion
    let delay = Double(week) * 0.026 + Double(day) * 0.016
    return RoundedRectangle(cornerRadius: GraphMetrics.radius)
      .fill(AttendanceFill.color(level: cell.level, accent: accent))
      .animation(reduceMotion ? nil : Motion.crossfade, value: cell.level)
      // Cintilação do componente com a intensidade padrão de 0.65: a casa perde
      // até 22% da opacidade e 5% do tamanho num ciclo de 2 a 3,4 segundos. A
      // semente espalha o ciclo para as casas vizinhas não piscarem juntas.
      .opacity(twinkling ? 1 - 0.34 * 0.65 : 1)
      .scaleEffect(twinkling ? 1 - 0.08 * 0.65 : 1)
      .animation(twinkle(after: delay), value: twinkling)
      .brightness(0.2 * glow)
      .saturation(1 + 0.2 * glow)
      .animation(.easeOut(duration: 0.08), value: glow)
      .animation(.linear(duration: 0.14).delay(delay)) { $0.opacity(visible ? 1 : 0) }
      .animation(.interpolatingSpring(mass: 1, stiffness: 520, damping: 28).delay(delay)) {
        $0.offset(y: visible ? 0 : 4)
      }
      .animation(.interpolatingSpring(mass: 1, stiffness: 900, damping: 32)) {
        $0.scaleEffect(visible ? 1 : 0.35)
      }
      .onAppear {
        guard !reduceMotion else { return }
        shown = true
        twinkling = true
      }
      .onDisappear { twinkling = false }
  }

  private var seed: Double { Double((week * 17 + day * 31) % 11) / 10 }

  private func twinkle(after entrance: Double) -> Animation? {
    guard twinkling else { return nil }
    let cycle = 2 + seed * 1.4
    return .easeInOut(duration: cycle / 2).repeatForever(autoreverses: true)
      .delay(entrance + seed * 0.85)
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

/// A casa enquanto a frequência não chegou: cinza, pulsando, com o atraso
/// crescendo em diagonal como no esqueleto do componente.
private struct SkeletonSquare: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var dim = false
  let week: Int
  let day: Int

  var body: some View {
    RoundedRectangle(cornerRadius: GraphMetrics.radius)
      .fill(Color.surfaceMuted)
      .opacity(dim ? 0.5 : 1)
      .animation(
        dim ? .easeInOut(duration: 1).repeatForever(autoreverses: true).delay(Double(week + day) * 0.012) : nil,
        value: dim
      )
      .onAppear { if !reduceMotion { dim = true } }
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
