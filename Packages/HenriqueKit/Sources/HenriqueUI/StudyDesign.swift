import HenriqueCore
import SwiftUI

// MARK: - Cores

extension Color {
  static let studyPaper = Color(hex: 0xf6f5f4)
  static let studyInk = Color(hex: 0x000000)
  static let studyInk60 = Color.black.opacity(0.6)
  static let studyInk40 = Color.black.opacity(0.4)
  static let studyInk20 = Color.black.opacity(0.2)
  static let studyGraphite = Color(hex: 0x615d59)
  static let studyLine = Color.black.opacity(0.08)
  static let studyBlue = Color(hex: 0x0075de)
  static let studySky = Color(hex: 0xe6f3fe)
  static let studyMarigold = Color(hex: 0xffb110)
  static let studyCoral = Color(hex: 0xf64932)
  static let studyMidnight = Color(hex: 0x02093a)
  static let studyLilac = Color(hex: 0x9d95ff)
  static let studyPeach = Color(hex: 0xf6d5b8)
  static let studyBlack = Color(hex: 0x0e100f)
  static let studyOffBlack = Color(hex: 0x191919)
  static let studyCream = Color(hex: 0xfffce1)
  static let studyCream50 = Color(hex: 0x7c7c6f)
  static let studyCream25 = Color(hex: 0x42433d)
  static let studyGreen = Color(hex: 0x0ae448)
  static let studyLightGreen = Color(hex: 0xabff84)
  static let studyCoreGreen = Color(hex: 0xdfffd1)

  /// A cor da matéria vem do banco como texto. Quando vem quebrada ou vazia, o
  /// desenho continua de pé no marigold em vez de sumir.
  init(hexString: String?) {
    let channels = studyChannels(hexString)
    self.init(.sRGB, red: channels.red, green: channels.green, blue: channels.blue, opacity: 1)
  }

  /// Tinta legível sobre a cor da matéria. Sai da luminância da própria cor, com
  /// a mesma fórmula do web, porque uma tabela fixa não cobre cor de banco.
  static func subjectInk(for hex: String?) -> Color {
    let channels = studyChannels(hex)
    let luminance =
      0.2126 * channels.red + 0.7152 * channels.green + 0.0722 * channels.blue
    return luminance < 0.55 ? .white : .black
  }
}

private let studyFallbackChannels = (red: 1.0, green: 177.0 / 255, blue: 16.0 / 255)

private func studyChannels(_ value: String?) -> (red: Double, green: Double, blue: Double) {
  var text = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
  if text.hasPrefix("#") { text.removeFirst() }
  if text.count == 3 { text = text.flatMap { [$0, $0] }.map(String.init).joined() }
  guard text.count == 6, let raw = UInt32(text, radix: 16) else { return studyFallbackChannels }
  return (
    Double((raw >> 16) & 0xff) / 255, Double((raw >> 8) & 0xff) / 255, Double(raw & 0xff) / 255
  )
}

// MARK: - Raios

/// Raio concêntrico do web: o externo é o interno mais o respiro de 16 que os
/// separa.
enum StudyRadius {
  static let inner: CGFloat = 8
  static let card: CGFloat = 12
  static let outer: CGFloat = 24
}

// MARK: - Formatação

/// Data e hora saem sempre em Fortaleza, e não no fuso do aparelho, porque o
/// prazo de uma entrega é o prazo que o professor marcou lá.
enum StudyFormat {
  static let zone = TimeZone(identifier: "America/Fortaleza") ?? .gmt
  static let locale = Locale(identifier: "pt_BR")

  static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    calendar.locale = locale
    return calendar
  }()

  static func due(_ date: Date, now: Date) -> String {
    let day = calendar.startOfDay(for: date)
    let today = calendar.startOfDay(for: now)
    if day == today { return "hoje · \(hour(date))" }
    if day == calendar.date(byAdding: .day, value: 1, to: today) {
      return "amanhã · \(hour(date))"
    }
    return "\(shortDay(date)) · \(hour(date))"
  }

  static func relative(_ date: Date, now: Date) -> String {
    let minutes = max(0, Int((now.timeIntervalSince(date) / 60).rounded()))
    if minutes < 1 { return "agora" }
    if minutes < 60 { return "há \(minutes) min" }
    let hours = Int((Double(minutes) / 60).rounded())
    if hours < 24 { return "há \(hours) h" }
    return "há \(Int((Double(hours) / 24).rounded())) d"
  }

  static func minutes(_ total: Int) -> String {
    if total < 60 { return "\(total) min" }
    let hours = total / 60
    let rest = total % 60
    return rest == 0 ? "\(hours)h" : "\(hours)h\(String(format: "%02d", rest))"
  }

  static func clock(_ seconds: TimeInterval) -> String {
    let safe = max(0, Int(seconds.rounded()))
    return String(format: "%02d:%02d", safe / 60, safe % 60)
  }

  static func weekdayLong(_ date: Date) -> String {
    date.formatted(style(.dateTime.weekday(.wide).day().month(.wide)))
  }

  static func hour(_ date: Date) -> String {
    date.formatted(style(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
  }

  /// O pt_BR abrevia com ponto e vírgula ("ter., 15"). O web tira os dois e o
  /// app faz igual para o rótulo caber na linha da tarefa.
  static func shortDay(_ date: Date) -> String {
    date.formatted(style(.dateTime.weekday(.abbreviated).day(.twoDigits)))
      .filter { $0 != "." && $0 != "," }
  }

  static func dayLabel(_ date: CalendarDate, today: CalendarDate) -> String {
    if date == today { return "hoje" }
    if date == today.adding(days: 1, in: calendar) { return "amanhã" }
    return weekdayLong(date.date(in: calendar))
  }

  private static func style(_ base: Date.FormatStyle) -> Date.FormatStyle {
    var style = base
    style.locale = locale
    style.timeZone = zone
    style.calendar = calendar
    return style
  }
}

// MARK: - Tons

enum StudyPillTone {
  case neutral, blue, green, yellow, coral, lilac, outline, cream

  var background: Color {
    switch self {
    case .neutral: Color.black.opacity(0.06)
    case .blue: .studySky
    case .green: .studyCoreGreen
    case .yellow: Color(hex: 0xfff1cc)
    case .coral: Color(hex: 0xfde0dc)
    case .lilac: Color(hex: 0xe9e7ff)
    case .outline, .cream: .clear
    }
  }

  var foreground: Color {
    switch self {
    case .neutral, .outline: Color.black.opacity(0.95)
    case .blue: .studyBlue
    case .green: Color(hex: 0x0b6b30)
    case .yellow: Color(hex: 0x7a4d00)
    case .coral: Color(hex: 0xa3200e)
    case .lilac: Color(hex: 0x3d35a6)
    case .cream: .studyCream
    }
  }

  var border: Color {
    switch self {
    case .outline: .studyInk20
    case .cream: Color.white.opacity(0.08)
    default: .clear
    }
  }
}

enum StudyCalloutTone {
  case sky, yellow

  var background: Color {
    switch self {
    case .sky: .studySky
    case .yellow: Color(hex: 0xfff3d6)
    }
  }

  var icon: Color {
    switch self {
    case .sky: .studyBlue
    case .yellow: Color(hex: 0x7a4d00)
    }
  }
}

extension AssignmentStatus {
  var pillTone: StudyPillTone {
    switch self {
    case .open: .blue
    case .in_progress: .yellow
    case .done: .green
    }
  }
}

// MARK: - Tipografia de página

struct StudyEyebrow: View {
  let text: String
  var cream = false

  init(_ text: String, cream: Bool = false) {
    self.text = text
    self.cream = cream
  }

  var body: some View {
    Text(text)
      .font(.caption.weight(.medium))
      .tracking(0.12)
      .foregroundStyle(cream ? Color.studyCream50 : Color.studyInk60)
  }
}

struct StudyHeading<Trailing: View>: View {
  @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 32.0
  let eyebrow: String?
  let title: String
  let trailing: Trailing

  init(eyebrow: String? = nil, title: String, @ViewBuilder trailing: () -> Trailing) {
    self.eyebrow = eyebrow
    self.title = title
    self.trailing = trailing()
  }

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        if let eyebrow { StudyEyebrow(eyebrow) }
        Text(title)
          .font(.system(size: titleSize, weight: .semibold).leading(.tight))
          .tracking(-titleSize * 0.03)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)
      }
      Spacer(minLength: 0)
      trailing
    }
    .padding(.top, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

extension StudyHeading where Trailing == EmptyView {
  init(eyebrow: String? = nil, title: String) {
    self.init(eyebrow: eyebrow, title: title) { EmptyView() }
  }
}

struct StudySectionHeading: View {
  let title: String
  var action: (label: String, perform: () -> Void)?

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(title)
        .font(.title3.weight(.semibold))
        .tracking(-0.22)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 0)
      if let action {
        Button(action.label, action: action.perform)
          .font(.footnote.weight(.medium))
          .foregroundStyle(Color.studyInk60)
          .buttonStyle(StudyPressStyle(slop: 13))
      }
    }
    // O respiro até o conteúdo da seção mora aqui, como a margem do web, então
    // a tela empilha título e conteúdo com espaçamento zero.
    .padding(.bottom, Space.m)
  }
}

struct StudyGroupLabel: View {
  let left: String

  var body: some View {
    Text(left)
      .font(.caption.weight(.medium))
      .foregroundStyle(Color.studyInk40)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 4)
      .padding(.horizontal, 2)
  }
}

// MARK: - Pills

struct StudyPill: View {
  let tone: StudyPillTone
  let color: String?
  let systemImage: String?
  let text: String

  init(tone: StudyPillTone = .neutral, color: String? = nil, text: String) {
    self.tone = tone
    self.color = color
    self.systemImage = nil
    self.text = text
  }

  init(tone: StudyPillTone = .neutral, systemImage: String, text: String) {
    self.tone = tone
    self.color = nil
    self.systemImage = systemImage
    self.text = text
  }

  private var hasGlyph: Bool { color != nil || systemImage != nil }

  var body: some View {
    HStack(spacing: 4) {
      if let color { StudyDot(color: color) }
      if let systemImage { Image(systemName: systemImage).imageScale(.small) }
      Text(text)
    }
    .font(.caption.weight(.medium))
    .foregroundStyle(tone.foreground)
    .lineLimit(1)
    .padding(.vertical, 2)
    // O ponto e o ícone parecem afastados da borda com o mesmo padding do texto.
    .padding(.leading, hasGlyph ? 6 : 8)
    .padding(.trailing, 8)
    .frame(minHeight: 22)
    .modifier(StudyPillSurface(tone: tone))
  }
}

private struct StudyPillSurface: ViewModifier {
  let tone: StudyPillTone

  @ViewBuilder
  func body(content: Content) -> some View {
    if tone == .outline {
      content.elevated(Capsule())
    } else {
      content
        .background(tone.background, in: .capsule)
        .overlay(Capsule().strokeBorder(tone.border))
    }
  }
}

struct StudyDot: View {
  let color: String?

  var body: some View {
    Circle()
      .fill(Color(hexString: color))
      .frame(width: 8, height: 8)
  }
}

// MARK: - Superfícies

struct StudyCard<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Space.l)
      .paperCard(radius: StudyRadius.card)
  }
}

struct StudyDbList<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    VStack(spacing: 0) {
      Group(subviews: content) { rows in
        ForEach(rows.indices, id: \.self) { index in
          if index > 0 { Rectangle().fill(Color.studyLine).frame(height: 1) }
          rows[index]
        }
      }
    }
    .padding(.vertical, Space.xs)
    .padding(.horizontal, Space.m)
    .paperCard(radius: StudyRadius.card)
  }
}

struct StudyRowChevron: View {
  var body: some View {
    Image(systemName: "chevron.right")
      .font(.system(size: 12))
      .foregroundStyle(Color.studyInk40)
  }
}

struct StudyDbRow<End: View>: View {
  let icon: String?
  let dot: String?
  let title: String
  let detail: String?
  let end: End
  let action: (() -> Void)?

  init(
    icon: String? = nil, dot: String? = nil, title: String, detail: String? = nil,
    @ViewBuilder end: () -> End, action: (() -> Void)? = nil
  ) {
    self.icon = icon
    self.dot = dot
    self.title = title
    self.detail = detail
    self.end = end()
    self.action = action
  }

  var body: some View {
    if let action {
      Button(action: action) { row }
        .buttonStyle(StudyPressStyle())
    } else {
      row
    }
  }

  private var row: some View {
    HStack(spacing: 6) {
      Group {
        if let icon {
          Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Color.studyInk60)
        } else {
          StudyDot(color: dot)
        }
      }
      .frame(width: 26)
      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(Color.studyInk)
          .lineLimit(1)
        if let detail {
          Text(detail).font(.caption).foregroundStyle(Color.studyInk40).lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      end
        .font(.caption)
        .foregroundStyle(Color.studyInk40)
    }
    .frame(minHeight: 44)
    .padding(.vertical, 8)
    .contentShape(.rect)
  }
}

extension StudyDbRow where End == StudyRowChevron {
  init(
    icon: String? = nil, dot: String? = nil, title: String, detail: String? = nil,
    action: (() -> Void)? = nil
  ) {
    self.init(icon: icon, dot: dot, title: title, detail: detail, end: { StudyRowChevron() },
      action: action)
  }
}

struct StudyCallout: View {
  let icon: String
  var tone: StudyCalloutTone?
  let title: String
  var detail: String?

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: icon)
        .font(.system(size: 20))
        .foregroundStyle(tone?.icon ?? Color.studyInk60)
        .frame(width: 24, height: 24)
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.subheadline.weight(.medium))
        if let detail {
          Text(detail).font(.caption).foregroundStyle(Color.studyInk60).lineLimit(3)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, Space.m)
    .padding(.horizontal, Space.m)
    .modifier(StudyCalloutSurface(tone: tone))
  }
}

private struct StudyCalloutSurface: ViewModifier {
  let tone: StudyCalloutTone?

  @ViewBuilder
  func body(content: Content) -> some View {
    if let tone {
      content.background(tone.background, in: .rect(cornerRadius: StudyRadius.card))
    } else {
      content.paperCard(radius: StudyRadius.card)
    }
  }
}

struct StudyEmptyState: View {
  let icon: String
  let title: String
  var detail: String?
  var cream = false
  var action: (label: String, perform: () -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Image(systemName: icon)
        .font(.system(size: 24))
        // Na lousa o ink40 do web sumiria no preto, então a versão creme usa o
        // tom apagado do próprio creme.
        .foregroundStyle(cream ? Color.studyCream50 : Color.studyInk40)
        .frame(height: 28)
        .offset(x: -2)
      Text(title)
        .font(.callout.weight(.semibold))
        .foregroundStyle(cream ? Color.studyCream : Color.studyInk)
      if let detail {
        Text(detail)
          .font(.footnote)
          .foregroundStyle(cream ? Color.studyCream50 : Color.studyGraphite)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let action {
        Button(action.label, action: action.perform)
          .buttonStyle(.glass)
          .controlSize(.large)
          .tint(cream ? Color.studyCream : Color.studyInk)
          .padding(.top, 4)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 28)
    .padding(.horizontal, 16)
    .background(cream ? Color.clear : .white, in: .rect(cornerRadius: StudyRadius.card))
    .overlay(
      RoundedRectangle(cornerRadius: StudyRadius.card)
        .strokeBorder(
          cream ? Color.studyCream25 : Color.studyInk20,
          style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
  }
}

struct StudyMetric: View {
  @ScaledMetric(relativeTo: .title2) private var valueSize = 24.0
  let value: String
  let caption: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(value)
        .font(.system(size: valueSize, weight: .semibold))
        .tracking(-valueSize * 0.02)
        .contentTransition(.numericText())
        .animation(Motion.crossfade, value: value)
      Text(caption)
        .font(.caption)
        .foregroundStyle(Color.studyInk60)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 14)
    .padding(.horizontal, 12)
    // A legenda de um cartão quebra linha e a do vizinho não. Esticar até a
    // altura do mais alto deixa a fileira reta.
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .paperCard(radius: StudyRadius.card)
  }
}

// MARK: - Tarefa

struct StudyTaskCard: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let assignment: StudyAssignment
  let now: Date
  var onToggle: ((AssignmentStatus) -> Void)?
  var onOpen: (() -> Void)?

  private var done: Bool { assignment.status == .done }

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      check
      VStack(alignment: .leading, spacing: 4) {
        Text(assignment.title)
          .font(.subheadline.weight(.medium))
          .lineLimit(2)
          .strikethrough(done)
        StudyWrap(spacing: 6, lineSpacing: 6) {
          StudyPill(tone: assignment.source == "ava" ? .neutral : .outline, text: assignment.source)
          if let name = assignment.subjectName {
            StudyPill(color: assignment.subjectColor, text: name)
          }
          Text(StudyFormat.due(assignment.dueAt, now: now))
            .font(.caption)
            .foregroundStyle(Color.studyInk60)
            .monospacedDigit()
        }
        .padding(.top, 2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if let onOpen {
        IconButton(title: "abrir entrega", systemImage: "arrow.right", size: 16, action: onOpen)
          .tint(Color.studyInk60)
      }
    }
    .padding(.vertical, 10)
    .padding(.horizontal, Space.m)
    .paperCard(radius: StudyRadius.inner)
    .opacity(done ? 0.55 : 1)
  }

  /// O quadrado tem 20pt de desenho; o `slop` leva o alvo aos 44 da HIG.
  private var check: some View {
    Button { onToggle?(assignment.status.next) } label: {
      RoundedRectangle(cornerRadius: 5)
        .fill(done ? Color.studyBlue : .white)
        .overlay(
          RoundedRectangle(cornerRadius: 5)
            .strokeBorder(done ? Color.studyBlue : Color.studyInk20, lineWidth: 1.5)
        )
        .overlay {
          if done {
            Image(systemName: "checkmark")
              .font(.system(size: 12, weight: .bold))
              .foregroundStyle(.white)
              .offset(y: -0.5)
              .transition(.iconAppear)
          }
        }
        .animation(reduceMotion ? nil : Motion.confirm, value: done)
        .frame(width: 20, height: 20)
    }
    .buttonStyle(StudyPressStyle(slop: 12))
    .disabled(onToggle == nil)
    .accessibilityLabel(done ? "reabrir entrega" : "concluir entrega")
    .sensoryFeedback(.selection, trigger: done)
  }
}

// MARK: - Chips e métricas

struct StudyChip: View {
  let label: String
  var count: Int?
  let isActive: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Text(label)
        if let count { Text("\(count)").monospacedDigit().opacity(0.6) }
      }
      .font(.footnote.weight(.medium))
      .foregroundStyle(isActive ? .white : Color.black.opacity(0.95))
      .padding(.horizontal, 14)
      .frame(minHeight: 44)
      .modifier(StudyChipSurface(isActive: isActive))
      .contentShape(.capsule)
    }
    .buttonStyle(StudyPressStyle())
    .accessibilityAddTraits(isActive ? .isSelected : [])
  }
}

/// Chip inativo é branco com o anel do cartão; ativo é tinta sólida, sem sombra.
struct StudyChipSurface: ViewModifier {
  let isActive: Bool

  @ViewBuilder
  func body(content: Content) -> some View {
    if isActive {
      content.background(Color.studyInk, in: .capsule)
    } else {
      content.elevated(Capsule())
    }
  }
}

// MARK: - Casca de tela

extension View {
  func studyPage() -> some View {
    scrollContentBackground(.hidden)
      .background(Color.studyPaper.ignoresSafeArea())
  }
}

struct StudyLoadingState: View {
  var body: some View {
    ProgressView().frame(maxWidth: .infinity, minHeight: 160)
  }
}

struct StudyFailedState: View {
  let message: String
  let retry: () -> Void

  var body: some View {
    StudyEmptyState(
      icon: "exclamationmark.triangle",
      title: "não carregou",
      detail: message,
      action: (label: "tentar de novo", perform: retry))
  }
}

// MARK: - Quebra de linha

/// A meta da tarefa quebra linha no web (`flex-wrap`) e o SwiftUI não tem pilha
/// que quebre, então a conta de largura mora aqui.
struct StudyWrap: Layout {
  var spacing: CGFloat = 6
  var lineSpacing: CGFloat = 6

  /// Sem largura proposta a resposta é a linha inteira em uma só, e não os 10pt
  /// que `replacingUnspecifiedDimensions` devolveria.
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    arrange(width: proposal.width ?? .infinity, subviews: subviews).size
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let placement = arrange(width: bounds.width, subviews: subviews)
    for index in subviews.indices {
      subviews[index].place(
        at: CGPoint(
          x: bounds.minX + placement.offsets[index].x, y: bounds.minY + placement.offsets[index].y),
        anchor: .topLeading,
        proposal: ProposedViewSize(placement.sizes[index]))
    }
  }

  /// A largura da linha é proposta a cada peça, senão um nome de matéria comprido
  /// nunca trunca e a fila estoura o cartão.
  private func arrange(width: CGFloat, subviews: Subviews)
    -> (size: CGSize, offsets: [CGPoint], sizes: [CGSize])
  {
    var offsets: [CGPoint] = []
    var sizes: [CGSize] = []
    var x: CGFloat = 0
    var y: CGFloat = 0
    var lineHeight: CGFloat = 0
    var widest: CGFloat = 0
    for view in subviews {
      let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
      if x > 0, x + size.width > width {
        x = 0
        y += lineHeight + lineSpacing
        lineHeight = 0
      }
      offsets.append(CGPoint(x: x, y: y))
      sizes.append(size)
      x += size.width + spacing
      widest = max(widest, x - spacing)
      lineHeight = max(lineHeight, size.height)
    }
    return (CGSize(width: min(widest, width), height: y + lineHeight), offsets, sizes)
  }
}
