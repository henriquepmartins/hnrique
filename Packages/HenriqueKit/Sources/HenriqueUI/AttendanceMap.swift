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
  @State private var failed = false
  @State private var attempt = 0
  let attendance: [CalendarDate: AttendanceDay]
  /// Falso quando o servidor não respondeu, e aí o mapa pede outra tentativa em
  /// vez de pintar o período como se ninguém tivesse treinado.
  let load: (CalendarDate, CalendarDate) async -> Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      // No ano corrente o ano no título só ocupa o espaço que falta ao mês.
      AttendanceHeader(
        period: $period,
        title: period.year == CalendarDate.today.year ? period.name(locale: locale) : period.title(locale: locale))
      if failed {
        AttendanceFailure { attempt += 1 }
      } else {
        AttendanceCount(
          total: grid.total, name: period.name(locale: locale), answered: answered,
          isPast: period.range().upperBound < .today)
      }
      // Trocar de período monta a grade de novo, e a onda de entrada corre outra
      // vez. As casas só nascem quando a frequência daquele período chegou;
      // antes disso a grade pulsa vazia, com o mesmo desenho.
      AttendanceGraph(
        grid: grid, name: period.name(locale: locale), ready: loaded == period, scrolls: period.isYear)
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
    .task(id: AttendanceRequest(period: period, attempt: attempt)) {
      failed = false
      let range = period.range()
      let ok = await load(range.lowerBound, range.upperBound)
      guard !Task.isCancelled else { return }
      failed = !ok
      guard ok else { return }
      answered = true
      loaded = period
    }
  }
}

struct AttendanceRequest: Equatable {
  let period: AttendancePeriod
  let attempt: Int
}

extension AttendancePeriod {
  fileprivate var isYear: Bool {
    if case .year = self { true } else { false }
  }

  fileprivate var year: Int {
    switch self {
    case .month(let year, _), .year(let year): year
    }
  }
}

/// O período que não carregou, com a nova tentativa. O mapa e o calendário do
/// plano usam o mesmo aviso.
struct AttendanceFailure: View {
  let retry: () -> Void

  var body: some View {
    HStack(spacing: Space.m) {
      Label("não carregou", systemImage: "wifi.exclamationmark")
        .font(.subheadline.weight(.medium)).foregroundStyle(Color.mutedInk)
      Spacer(minLength: 8)
      Button("tentar de novo", systemImage: "arrow.clockwise", action: retry)
        .font(.subheadline.weight(.medium))
        .buttonStyle(.glass)
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
        .lineLimit(1).minimumScaleFactor(0.7)
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
  let isPast: Bool

  var body: some View {
    Text(text)
      .font(.title2.weight(.medium)).monospacedDigit().foregroundStyle(Color.ink)
      .contentTransition(.numericText(value: Double(total)))
      .opacity(answered || total > 0 ? 1 : 0)
      .animation(reduceMotion ? nil : Motion.roll, value: total)
  }

  private var text: String {
    switch total {
    case 0: isPast ? "nenhum treino" : "nenhum treino ainda"
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
  /// A linha dos meses em cima da fita do ano.
  static let monthRow: CGFloat = 14
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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var focus: GraphFocus?
  @State private var scrubbed = false
  /// O trecho da fita do ano que está na tela, em coordenadas da grade.
  @State private var viewport: CGRect?
  /// A onda já passou. Na fita do ano a LazyHStack recria as colunas que voltam
  /// à tela, e sem isso a onda tocava de novo debaixo do dedo.
  @State private var entered = false
  /// A semana que o VoiceOver está lendo, andando de uma em uma pelo gesto de
  /// ajuste. Nula enquanto ele só ouviu o total.
  @State private var spokenWeek: Int?
  let grid: AttendanceGrid
  let name: String
  let ready: Bool
  let scrolls: Bool

  /// Como no componente, a grade para na semana de hoje. O resto do ano ainda
  /// não aconteceu, e com a fita ancorada à direita ele empurraria os treinos
  /// para fora da tela.
  private var weeks: [AttendanceGrid.Week] {
    grid.weeks.filter { $0.start <= .today }
  }

  var body: some View {
    HStack(alignment: .top, spacing: 6) {
      weekdayLabels
      if scrolls {
        ScrollView(.horizontal) {
          VStack(alignment: .leading, spacing: GraphMetrics.gap) {
            monthLabels
            board
          }
          .padding(.vertical, Space.s)
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
  }

  /// Segunda, quarta e sexta, nas linhas da semana que começa na segunda. Fora
  /// da rolagem, para continuarem na tela com a fita em qualquer mês.
  private var weekdayLabels: some View {
    VStack(alignment: .leading, spacing: GraphMetrics.gap) {
      ForEach(0..<7, id: \.self) { row in
        Text(row.isMultiple(of: 2) && row < 6 ? ["seg", "qua", "sex"][row / 2] : "")
          .frame(height: GraphMetrics.side)
      }
    }
    .padding(.top, Space.s + (scrolls ? GraphMetrics.monthRow + GraphMetrics.gap : 0))
    .font(.caption2).foregroundStyle(Color.mutedInk)
    .dynamicTypeSize(...DynamicTypeSize.large)
    .accessibilityHidden(true)
  }

  /// O mês abreviado em cima da coluna em que cai o dia 1.
  private var monthLabels: some View {
    let style = Date.FormatStyle(locale: locale).month(.abbreviated)
    let starts = weeks.enumerated().compactMap { index, week in
      week.cells.first { $0.date?.day == 1 }?.date.map { (week: index, name: $0.date().formatted(style)) }
    }
    return ZStack(alignment: .topLeading) {
      ForEach(starts, id: \.week) { start in
        Text(start.name).fixedSize()
          .offset(x: CGFloat(start.week) * GraphMetrics.pitch)
      }
    }
    .frame(
      width: CGFloat(weeks.count) * GraphMetrics.pitch, height: GraphMetrics.monthRow,
      alignment: .topLeading)
    .font(.caption2).foregroundStyle(Color.mutedInk)
    .dynamicTypeSize(...DynamicTypeSize.large)
    .accessibilityHidden(true)
  }

  private var board: some View {
    // Na fita do ano só as semanas na tela existem; as de janeiro, fora da
    // tela, não cintilam nem pulsam à toa. No mês tudo cabe e a pilha é comum.
    Group {
      if scrolls {
        LazyHStack(alignment: .top, spacing: GraphMetrics.gap) { columns }
      } else {
        HStack(alignment: .top, spacing: GraphMetrics.gap) { columns }
      }
    }
    .overlay(alignment: .topLeading) {
      tooltip.animation(Motion.swap, value: focus == nil)
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
    // Uma casa por elemento fazia o VoiceOver atravessar o ano inteiro para
    // chegar à legenda. A grade é um elemento só, e o ajuste anda de semana em
    // semana para quem quer o detalhe.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("frequência de \(name)")
    .accessibilityValue(spokenValue)
    .accessibilityAdjustableAction { direction in
      guard !weeks.isEmpty else { return }
      let current = spokenWeek ?? weeks.count
      switch direction {
      case .increment: spokenWeek = min(current + 1, weeks.count - 1)
      case .decrement: spokenWeek = max(current - 1, 0)
      @unknown default: break
      }
    }
    .task(id: ready) {
      guard ready, !entered else { return }
      // A onda leva 0,25 s para atravessar e cada casa entra em 0,3 s.
      try? await Task.sleep(for: .seconds(0.6))
      entered = true
    }
  }

  private var columns: some View {
    // A onda atravessa a grade inteira em 0,25 s, seja um mês ou um ano. A fita
    // do ano abre na borda direita, então a onda parte de lá.
    let span = Double(max(weeks.count - 1, 1) + 6)
    return ForEach(Array(weeks.enumerated()), id: \.element.id) { week, column in
      VStack(spacing: GraphMetrics.gap) {
        ForEach(Array(column.cells.enumerated()), id: \.element.id) { day, cell in
          GraphCell(
            cell: cell, week: week, day: day, ready: ready, entered: entered,
            delay: 0.25 * Double((scrolls ? weeks.count - 1 - week : week) + day) / span,
            glow: glow(week: week, day: day)
          )
        }
      }
    }
  }

  private var spokenValue: String {
    guard ready else { return "carregando" }
    guard let index = spokenWeek, weeks.indices.contains(index) else {
      return grid.total == 1 ? "1 treino" : "\(grid.total) treinos"
    }
    let days = weeks[index].cells.filter { $0.date != nil }
    let trained = days.count { $0.workSets > 0 }
    let sets = days.reduce(0) { $0 + $1.workSets }
    let start = (days.first?.date ?? weeks[index].start).date()
      .formatted(Date.FormatStyle(locale: locale).day().month(.wide))
    let workouts = trained == 1 ? "1 treino" : "\(trained) treinos"
    let series = sets == 1 ? "1 série" : "\(sets) séries"
    return "semana de \(start), \(workouts), \(series)"
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
        .animation(reduceMotion ? nil : Motion.tap) {
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

/// Uma casa. Três camadas de movimento: a entrada em onda, a cintilação que não
/// para e o brilho da onda de toque. São centenas de casas na tela, então cada
/// camada mexe só em opacidade, escala ou na cor do preenchimento.
private struct GraphCell: View {
  @Environment(\.accent) private var accent
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var shown = false
  @State private var twinkling = false
  let cell: AttendanceGrid.Cell
  let week: Int
  let day: Int
  let ready: Bool
  let entered: Bool
  let delay: Double
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
  }

  private var square: some View {
    let visible = shown || reduceMotion
    // O brilho da onda de toque entra na própria cor, clareando o preenchimento;
    // um filtro de brilho em cada casa custava uma passada a mais por casa.
    return RoundedRectangle(cornerRadius: GraphMetrics.radius)
      .fill(AttendanceFill.color(level: cell.level, accent: accent).mix(with: .white, by: 0.2 * glow))
      .animation(reduceMotion ? nil : Motion.crossfade, value: cell.level)
      .animation(Motion.swap, value: glow)
      // Cintilação do componente com a intensidade padrão de 0.65: a casa perde
      // até 22% da opacidade num ciclo de 2 a 3,4 segundos. A semente espalha o
      // ciclo para as casas vizinhas não piscarem juntas.
      .opacity(twinkling ? 1 - 0.34 * 0.65 : 1)
      .animation(twinkle(after: delay), value: twinkling)
      .animation(entered ? nil : Motion.entrance.delay(delay)) {
        $0.opacity(visible ? 1 : 0).scaleEffect(visible ? 1 : 0.95)
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
      AttendanceMap(attendance: AttendancePreview.sample) { _, _ in true }
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
