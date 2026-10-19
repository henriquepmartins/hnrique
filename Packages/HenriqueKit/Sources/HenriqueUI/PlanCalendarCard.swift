import HenriqueCore
import SwiftUI

/// O calendário da tela "plano": por dia, qual treino foi feito e qual o plano
/// pede. Recebe a frequência e o plano já carregados e pede o intervalo do mês
/// visível a quem tem o servidor; assim o preview roda com dados fabricados.
struct PlanCalendarCard: View {
  @Environment(\.locale) private var locale
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var painting = PlanMarkerPlayback()
  @State private var isVisible = false
  @State private var hasLoadedAttendance = false
  @State private var period: AttendancePeriod = .month(containing: .today)
  @State private var failed = false
  @State private var attempt = 0
  /// Os meses já pintados nesta tela. Voltar à aba ou salvar um treino não
  /// pinta de novo o que o dono já viu entrar.
  @State private var paintedPeriods: Set<AttendancePeriod> = []
  @State private var swapCount = 0
  let attendance: [CalendarDate: AttendanceDay]
  let weekPlan: [WeekPlanItem]
  let swaps: [DaySwap]
  let week: TrainingWeek?
  /// As datas que aceitam troca pelo toque. Nula esconde o menu.
  let swapWindow: ClosedRange<CalendarDate>?
  let load: (CalendarDate, CalendarDate) async -> Bool
  let onSwap: (CalendarDate, String?) async -> Bool

  init(
    attendance: [CalendarDate: AttendanceDay], weekPlan: [WeekPlanItem], swaps: [DaySwap] = [],
    week: TrainingWeek? = nil, swapWindow: ClosedRange<CalendarDate>? = nil,
    load: @escaping (CalendarDate, CalendarDate) async -> Bool,
    onSwap: @escaping (CalendarDate, String?) async -> Bool = { _, _ in false }
  ) {
    self.attendance = attendance
    self.weekPlan = weekPlan
    self.swaps = swaps
    self.week = week
    self.swapWindow = swapWindow
    self.load = load
    self.onSwap = onSwap
  }

  private var swapContext: PlanSwapContext? {
    swapWindow.map { window in
      PlanSwapContext(
        window: window, plan: weekPlan.inTrainingWeekOrder(),
        schedule: PlanSchedule(plan: weekPlan, swaps: swaps, calendar: .trainingWeek)
      ) { date, workoutId in
        Task {
          if await onSwap(date, workoutId) { swapCount += 1 }
        }
      }
    }
  }

  private var calendarGrid: PlanCalendar {
    PlanCalendar(
      period: period, attendance: attendance, weekPlan: weekPlan, swaps: swaps,
      calendar: .trainingWeek, week: week)
  }

  private var workoutsById: [String: WeekPlanItem] {
    Dictionary(weekPlan.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
  }

  /// Um mês adiante fica aberto: no fim do mês a semana seguinte já cai nele,
  /// e o que o plano pede ali é o que o calendário existe para mostrar.
  private var nextIsFuture: Bool {
    period.next.range().lowerBound > CalendarDate.today.adding(days: 31)
  }

  var body: some View {
    let grid = calendarGrid
    let workouts = workoutsById
    VStack(alignment: .leading, spacing: 16) {
      header
      if failed { AttendanceFailure { attempt += 1 } }
      TimelineView(.animation(paused: !painting.isDrawing || reduceMotion)) { timeline in
        PlanMonthGrid(
          grid: grid, workoutsById: workouts, swap: swapContext,
          paintProgress: reduceMotion ? 1 : painting.progress(at: timeline.date))
      }
      .transaction { $0.animation = nil }
      PlanLegend()
    }
    .padding(Space.xl).paperCard()
    .sensoryFeedback(.selection, trigger: swapCount)
    .onAppear {
      isVisible = true
      hasLoadedAttendance = false
      resetPainting()
    }
    .onChange(of: period) {
      hasLoadedAttendance = false
      resetPainting()
    }
    .onChange(of: attendance) {
      if hasLoadedAttendance { startPainting() }
    }
    .onChange(of: weekPlan) {
      if hasLoadedAttendance { startPainting() }
    }
    .onDisappear {
      isVisible = false
      painting.finish()
    }
    .onChange(of: reduceMotion) { if reduceMotion { painting.finish() } }
    .task(id: AttendanceRequest(period: period, attempt: attempt)) {
      failed = false
      let range = period.range()
      let ok = await load(range.lowerBound, range.upperBound)
      guard !Task.isCancelled else { return }
      // Sem a resposta, o mês pintado sem nenhum feito diria que ninguém treinou.
      failed = !ok
      guard ok else { return }
      hasLoadedAttendance = true
      startPainting()
    }
    .task(id: painting.startedAt) {
      guard let start = painting.startedAt else { return }
      do {
        try await Task.sleep(for: .seconds(max(0, PlanMarkerPlayback.duration - Date().timeIntervalSince(start))))
      } catch { return }
      guard !Task.isCancelled, painting.startedAt == start else { return }
      painting.finish()
    }
  }

  private func resetPainting() {
    if paintedPeriods.contains(period) { painting.finish() } else { painting.reset() }
  }

  private func startPainting() {
    guard isVisible else { return }
    guard !reduceMotion, !paintedPeriods.contains(period) else {
      painting.finish()
      return
    }
    paintedPeriods.insert(period)
    painting.start(at: .now)
  }

  private var header: some View {
    HStack(spacing: 8) {
      // Duas linhas, porque numa só o texto grande cortava o ano em "202…".
      Text(period.title(locale: locale)).font(.subheadline).foregroundStyle(Color.ink)
        .lineLimit(2).minimumScaleFactor(0.6)
      Spacer(minLength: 4)
      IconButton(title: "Mês anterior", systemImage: "chevron.left", glass: true, nudge: CGSize(width: 1, height: 0)) { period = period.previous }
      IconButton(title: "Próximo mês", systemImage: "chevron.right", glass: true, nudge: CGSize(width: -1, height: 0)) { period = period.next }
        .disabled(nextIsFuture)
    }
  }

}

/// Cada entrada e cada resposta nova podem iniciar uma pintura completa.
struct PlanMarkerPlayback {
  static let duration = 1.15
  private(set) var startedAt: Date?
  private var completed = false
  var isDrawing: Bool { startedAt != nil }

  mutating func reset() {
    startedAt = nil
    completed = false
  }

  mutating func start(at date: Date) {
    startedAt = date
    completed = false
  }

  mutating func finish() {
    startedAt = nil
    completed = true
  }

  func progress(at date: Date) -> Double {
    guard let startedAt else { return completed ? 1 : 0 }
    return max(0, min(1, date.timeIntervalSince(startedAt) / Self.duration))
  }
}

/// O que o menu de uma casa precisa para trocar o treino daquela data.
struct PlanSwapContext {
  let window: ClosedRange<CalendarDate>
  let plan: [WeekPlanItem]
  let schedule: PlanSchedule
  let swap: (CalendarDate, String?) -> Void
}

private struct PlanMonthGrid: View {
  @Environment(\.locale) private var locale
  @Environment(\.dynamicTypeSize) private var textSize
  let grid: PlanCalendar
  let workoutsById: [String: WeekPlanItem]
  let swap: PlanSwapContext?
  let paintProgress: Double

  /// Nos tamanhos de acessibilidade "ter." já não cabe na coluna; fica a
  /// inicial.
  private var weekdayInitials: [(weekday: Int, initial: String)] {
    var calendar = Calendar.trainingWeek
    calendar.locale = locale
    let symbols = textSize.isAccessibilitySize
      ? calendar.veryShortStandaloneWeekdaySymbols : calendar.shortStandaloneWeekdaySymbols
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
            DayCell(cell: cell, workoutsById: workoutsById, swap: swap, paintProgress: paintProgress)
              .aspectRatio(1, contentMode: .fit).frame(maxWidth: .infinity)
          }
        }
      }
    }
  }
}

private struct DayCell: View {
  @Environment(\.locale) private var locale
  let cell: PlanCalendar.Cell
  let workoutsById: [String: WeekPlanItem]
  let swap: PlanSwapContext?
  let paintProgress: Double
  @ScaledMetric(relativeTo: .caption2) private var daySize = 12.0
  @State private var showsName = false
  private let radius: CGFloat = 8

  private var workout: WeekPlanItem? {
    switch cell.mark {
    case .none: nil
    case .done(let ids):
      // Id desconhecido (treino apagado) ou feito sem treino conhecido: o
      // palpite é o treino que o plano pede nesse weekday, para o feito sair
      // na cor sólida do folder em vez de cinza.
      ids.first.flatMap { workoutsById[$0] }
        ?? workoutsById.values.first { $0.weekdays.contains(cell.slot.weekday()) }
    case .planned(let id), .missed(let id): workoutsById[id]
    }
  }

  /// Hoje e os dias à frente dentro da janela trocam de treino pelo toque. Dia
  /// já feito não troca.
  private func swapping(_ date: CalendarDate) -> PlanSwapContext? {
    guard let swap, swap.window.contains(date) else { return nil }
    if case .done = cell.mark { return nil }
    return swap
  }

  var body: some View {
    if let date = cell.date {
      if let swap = swapping(date) {
        Menu {
          Section(workout?.name.lowercased() ?? "descanso") {
            ForEach(swap.plan.filter { $0.id != workout?.id }) { item in
              Button(item.name.lowercased()) { swap.swap(date, item.id) }
            }
          }
          if swap.schedule.isSwapped(date) {
            Button("voltar ao plano", systemImage: "arrow.uturn.backward") { swap.swap(date, nil) }
          }
        } label: {
          square
        }
        .buttonStyle(StudyPressStyle())
        .accessibilityLabel(label(for: date))
        .accessibilityHint("trocar o treino do dia")
      } else if let workout {
        Button { showsName = true } label: { square }
          .buttonStyle(StudyPressStyle())
          .popover(isPresented: $showsName) {
            Text(workout.name.lowercased())
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(Color.ink)
              .padding(.horizontal, 14).padding(.vertical, 10)
              .presentationCompactAdaptation(.popover)
          }
          .accessibilityLabel(label(for: date))
      } else {
        square.accessibilityElement().accessibilityLabel(label(for: date))
      }
    } else {
      Color.clear.accessibilityHidden(true)
    }
  }

  private var square: some View {
    RoundedRectangle(cornerRadius: radius)
      .fill(Color.ink.opacity(0.04))
      .overlay {
        background
          .mask {
            PlanMarkerMask(progress: paintProgress, day: cell.slot.day)
          }
      }
      .overlay { content }
      .overlay {
        if cell.isToday {
          RoundedRectangle(cornerRadius: Radius.concentric(radius, padding: 3))
            .strokeBorder(Color.ink, lineWidth: 1.5)
            .padding(-3)
        }
      }
  }

  @ViewBuilder private var background: some View {
    let shape = RoundedRectangle(cornerRadius: radius)
    switch cell.mark {
    case .none:
      shape.fill(.clear)
    case .done:
      shape.fill(workout?.tone.top ?? Color.ink.opacity(0.18))
    case .planned:
      let tone = workout?.tone.top ?? Color.mutedInk
      shape.fill(.white)
        .overlay { Hachura().stroke(tone.opacity(0.45), lineWidth: 1).clipShape(.rect(cornerRadius: radius)) }
        .overlay { shape.strokeBorder(tone, lineWidth: 1.5) }
    case .missed:
      let tone = workout?.tone.top ?? Color.mutedInk
      shape.fill(.white)
        .overlay { shape.strokeBorder(tone.opacity(0.28), lineWidth: 1.5) }
    }
  }

  private var content: some View {
    // A casa é quadrada e não cresce com o texto; o número cresce até caber.
    Text("\(cell.slot.day)").font(.system(size: daySize, weight: .medium)).monospacedDigit()
      .lineLimit(1).minimumScaleFactor(0.6)
      .padding(2)
      .foregroundStyle(textColor)
  }

  private var textColor: Color {
    switch cell.mark {
    case .none: Color.mutedInk
    case .done: workout?.tone.ink ?? Color.ink.opacity(0.5)
    case .planned: workout?.tone.ink ?? Color.mutedInk
    case .missed: Color.mutedInk.opacity(0.6)
    }
  }

  private func label(for date: CalendarDate) -> String {
    let day = date.date().formatted(Date.FormatStyle(locale: locale).day().month(.wide))
    switch cell.mark {
    case .none: return "\(day), sem treino"
    case .done: return "\(day), feito" + (workout.map { ", \($0.name)" } ?? "")
    case .planned: return "\(day), planejado" + (workout.map { ", \($0.name)" } ?? "")
    case .missed: return "\(day), planejado, não treinou" + (workout.map { ", \($0.name)" } ?? "")
    }
  }
}

/// Cinco passadas sobrepostas revelam a cor sem mover o texto ou a grade.
@Animatable
struct PlanMarkerMask: Shape {
  var progress: Double
  @AnimatableIgnored var day: Int

  func path(in rect: CGRect) -> Path {
    let delay = Double(max(0, min(day - 1, 30))) / 30 * 0.64
    let local = max(0, min(1, (progress - delay) / 0.36))
    guard local > 0 else { return Path() }
    guard local < 1 else { return Path(rect) }
    let eased = Motion.paintEase(local)
    let slant = day.isMultiple(of: 2) ? 0.035 : -0.035
    var stroke = Path()
    for pass in 0..<5 {
      let y = rect.minY + rect.height * (0.06 + Double(pass) * 0.22)
      let startX = rect.minX - rect.width * 0.12
      let endX = rect.maxX + rect.width * 0.12
      let forward = pass.isMultiple(of: 2)
      let start = CGPoint(x: forward ? startX : endX, y: y + rect.height * slant)
      let end = CGPoint(x: forward ? endX : startX, y: y - rect.height * slant)
      if pass == 0 { stroke.move(to: start) } else { stroke.addLine(to: start) }
      stroke.addQuadCurve(
        to: end,
        control: CGPoint(x: rect.midX, y: y + rect.height * (forward ? -0.025 : 0.025)))
    }
    return stroke.trimmedPath(from: 0, to: eased)
      .strokedPath(StrokeStyle(lineWidth: rect.height * 0.32, lineCap: .round, lineJoin: .round))
  }
}

private struct Hachura: Shape {
  var espaco: CGFloat = 5

  func path(in rect: CGRect) -> Path {
    var path = Path()
    var x = -rect.height
    while x < rect.width {
      path.move(to: CGPoint(x: x, y: rect.maxY))
      path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
      x += espaco
    }
    return path
  }
}

private struct PlanLegend: View {
  @ScaledMetric(relativeTo: .caption2) private var side = 11.0
  private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 3) }

  /// Numa linha quando cabe; senão uma marca por linha, sem quebrar palavra.
  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 10) { entries }.fixedSize()
      VStack(alignment: .trailing, spacing: 4) { entries }
    }
    .font(.caption2).foregroundStyle(Color.mutedInk)
    .lineLimit(1)
    .frame(maxWidth: .infinity, alignment: .trailing)
    .accessibilityHidden(true)
  }

  @ViewBuilder private var entries: some View {
    entry("feito") { shape.fill(Color.mutedInk) }
    entry("planejado") {
      shape.fill(.white)
        .overlay { Hachura(espaco: 3).stroke(Color.mutedInk.opacity(0.45), lineWidth: 1).clipShape(.rect(cornerRadius: 3)) }
        .overlay { shape.strokeBorder(Color.mutedInk, lineWidth: 1) }
    }
    entry("furou") { shape.strokeBorder(Color.mutedInk.opacity(0.28), lineWidth: 1) }
  }

  private func entry(_ title: String, @ViewBuilder mark: () -> some View) -> some View {
    HStack(spacing: 4) {
      mark().frame(width: side, height: side)
      Text(title)
    }
  }
}

extension Motion {
  /// A pena que desacelera no fim do traço do calendário, cúbica de saída.
  static func paintEase(_ progress: Double) -> Double {
    1 - pow(1 - progress, 3)
  }
}

#if DEBUG
  #Preview("Calendário do plano") {
    ScrollView {
      PlanCalendarCard(
        attendance: PlanCalendarPreview.attendance, weekPlan: PlanCalendarPreview.plan,
        load: { _, _ in true })
        .padding(16)
    }
    .background(Color.canvas)
    .environment(\.locale, Locale(identifier: "pt_BR"))
  }

  enum PlanCalendarPreview {
    /// Peito na segunda, costas na terça, perna na quinta, ombro no sábado.
    static let plan: [WeekPlanItem] = {
      let tones = WorkoutTone.all
      let json = """
        [
          {"id": "peito", "weekdays": [1], "name": "peito e tríceps", "focus": "", "exerciseCount": 0,
           "exercises": [], "estimatedMinutes": 50, "color": "\(tones[0].hex)"},
          {"id": "costas", "weekdays": [2], "name": "costas e bíceps", "focus": "", "exerciseCount": 0,
           "exercises": [], "estimatedMinutes": 50, "color": "\(tones[1].hex)"},
          {"id": "perna", "weekdays": [4], "name": "perna", "focus": "", "exerciseCount": 0,
           "exercises": [], "estimatedMinutes": 60, "color": "\(tones[4].hex)"},
          {"id": "ombro", "weekdays": [6], "name": "ombro e abdômen", "focus": "", "exerciseCount": 0,
           "exercises": [], "estimatedMinutes": 40, "color": "\(tones[2].hex)"}
        ]
        """
      return try! JSONDecoder.henrique().decode([WeekPlanItem].self, from: Data(json.utf8))
    }()

    static var attendance: [CalendarDate: AttendanceDay] {
      let today = CalendarDate.today
      var days: [CalendarDate: AttendanceDay] = [:]
      for back in 1..<60 {
        let date = today.adding(days: -back)
        guard let item = plan.first(where: { $0.weekdays.contains(date.weekday()) }) else { continue }
        // A cada nove dias o treino ficou por fazer; o de 40 dias atrás veio de
        // um servidor que ainda não dizia qual treino foi.
        if back % 9 == 0 { continue }
        let ids = back == 40 ? [] : [item.id]
        days[date] = AttendanceDay(date: date, workSets: 12, completed: true, workoutTemplateIds: ids)
      }
      return days
    }
  }
#endif
