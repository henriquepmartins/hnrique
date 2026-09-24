import CoreText
import HenriqueCore
import SwiftUI

/// O que o hero mostra. Espelha o `heroView` do web para as duas telas
/// decidirem o mesmo texto a partir do mesmo treino.
enum HeroModel {
  case rest(dateLabel: String)
  case ready(Session)
  case inProgress(Session)

  struct Session {
    let dateLabel: String
    let workout: WorkoutSummary
    let meta: String
    let actionLabel: String
  }

  init(workout: WorkoutSummary?, date: CalendarDate, finished: Bool = false) {
    let dateLabel = Self.dateLabel(date)
    guard let workout else {
      self = .rest(dateLabel: dateLabel)
      return
    }
    let meta = "\(workout.exerciseCount) exercícios · \(workout.estimatedMinutes) min"
    if finished {
      self = .inProgress(Session(
        dateLabel: dateLabel, workout: workout,
        meta: meta + " · encerrado", actionLabel: "ver o treino"))
    } else if workout.completionPercent > 0 {
      self = .inProgress(Session(
        dateLabel: dateLabel, workout: workout,
        meta: meta + " · \(workout.completionPercent)% concluído", actionLabel: "continuar"))
    } else {
      self = .ready(Session(dateLabel: dateLabel, workout: workout, meta: meta, actionLabel: "começar"))
    }
  }

  var dateLabel: String {
    switch self {
    case .rest(let dateLabel): dateLabel
    case .ready(let session), .inProgress(let session): session.dateLabel
    }
  }

  /// "quarta · 23 de setembro". O "-feira" sai porque em caixa alta e espaçado
  /// ele dobra a largura do rótulo sem dizer nada a mais.
  static func dateLabel(_ date: CalendarDate) -> String {
    let style = Date.FormatStyle(locale: Locale(identifier: "pt_BR"), calendar: .autoupdatingCurrent)
    let day = date.date()
    let weekday = day.formatted(style.weekday(.wide)).replacingOccurrences(of: "-feira", with: "")
    return "\(weekday) · \(day.formatted(style.day().month(.wide)))"
  }
}

struct WorkoutHero: View {
  @Environment(\.accent) private var accent
  @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 76.0
  @ScaledMetric(relativeTo: .largeTitle) private var restTitleSize = 52.0
  let workout: WorkoutSummary?
  let date: CalendarDate
  var finished = false
  let notch: CGFloat
  let onStart: () -> Void

  var body: some View {
    let model = HeroModel(workout: workout, date: date, finished: finished)
    SpreadColumn(minHeight: 408 - 44 - 24, minGap: 24) {
      Text(model.dateLabel)
        .font(.system(size: 11, weight: .semibold)).tracking(2.2).textCase(.uppercase)
        .foregroundStyle(HeroInk.date)
      switch model {
      case .rest:
        middle(
          title: "treino leve ou descanso", size: restTitleSize,
          body: "Sem treino programado. Mobilidade e uma caminhada curta já contam.")
      case .ready(let session), .inProgress(let session):
        middle(title: session.workout.name, size: titleSize, body: session.workout.focus)
        HStack(spacing: 12) {
          Text(session.meta)
            .font(.system(size: 14)).monospacedDigit().foregroundStyle(HeroInk.meta)
            .contentTransition(.numericText())
          Spacer(minLength: 0)
          PaperButton(label: session.actionLabel, action: onStart)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, 44).padding(.horizontal, 24).padding(.bottom, 24)
    .background { HeroBackground(accent: accent) }
    .overlay(alignment: .top) {
      HeroNotch(center: notch).fill(Color.canvas)
        .shadow(color: .white.opacity(0.38), radius: 0, y: 1)
        .frame(height: 24)
    }
    .clipShape(.rect(cornerRadius: 32))
    .shadow(color: accent.deep.opacity(0.13), radius: 30, y: 22)
  }

  /// O -28 puxa o nome para perto da data, como o `margin-top` do web. O
  /// espaço que sobra no cartão fica entre o nome e o rodapé.
  private func middle(title: String, size: CGFloat, body: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      FilmTitle(text: title, size: size)
      Text(body).font(.system(size: 15)).lineSpacing(4).foregroundStyle(HeroInk.focus)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.top, -28)
  }
}

private enum HeroInk {
  static let date = Color(hex: 0xe7efe6)
  static let title = Color(hex: 0xf2ede4)
  static let focus = Color(hex: 0xd8e8e0)
  static let meta = Color(hex: 0xeaf0e4)
  static let cream = Color(hex: 0xf3ede2)
}

/// O `justify-content: space-between` do web. Um VStack com Spacer não cresce
/// dentro do ScrollView, que não propõe altura, então o cartão ficaria do
/// tamanho do texto em vez dos 408 pontos do web.
private struct SpreadColumn: Layout {
  let minHeight: CGFloat
  let minGap: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
    let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
    let content = heights.reduce(0, +) + minGap * CGFloat(max(subviews.count - 1, 0))
    return CGSize(width: width, height: max(minHeight, content))
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height }
    let gap = subviews.count > 1
      ? (bounds.height - heights.reduce(0, +)) / CGFloat(subviews.count - 1) : 0
    var y = bounds.minY
    for (subview, height) in zip(subviews, heights) {
      subview.place(
        at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
        proposal: ProposedViewSize(width: bounds.width, height: height))
      y += height + gap
    }
  }
}

/// A manhã do web: noite no topo, sol no pé. Os degraus saem dos tokens do
/// acento, então cada cor ganha o seu amanhecer. As proporções são as do
/// `styles.css`, acertadas para o verde cair no degradê aprovado.
private struct HeroBackground: View {
  let accent: Accent

  var body: some View {
    let night = mix(accent.deep, 0.46, .black)
    let dusk = mix(accent.base, 0.51, .ink)
    let dawn = mix(accent.deep, 0.75, accent.mint)
    let mist = mix(mix(accent.deep, 0.60, accent.mint), 0.85, accent.acid)
    let field = mix(mix(accent.mint, 0.48, .black), 0.65, accent.signal)
    let ground = mix(accent.acid, 0.43, .ink)
    let sun = mix(accent.signal, 0.40, Color(hex: 0xf0a878))
    ZStack {
      LinearGradient(
        stops: [
          .init(color: night, location: 0), .init(color: dusk, location: 0.30),
          .init(color: dawn, location: 0.55), .init(color: mist, location: 0.76),
          .init(color: field, location: 0.90), .init(color: ground, location: 1),
        ], startPoint: .top, endPoint: .bottom)
      // `radial-gradient(120% 60% at 50% 100%, ...)`: a elipse tem raios de
      // 1,2 da largura e 0,6 da altura. O EllipticalGradient só conhece a
      // proporção do próprio quadro, então o quadro é que ganha essa proporção.
      GeometryReader { proxy in
        EllipticalGradient(
          colors: [sun.opacity(0.35), sun.opacity(0)], center: .center,
          startRadiusFraction: 0, endRadiusFraction: 0.3)
          .frame(width: proxy.size.width * 2.4, height: proxy.size.height * 1.2)
          .position(x: proxy.size.width / 2, y: proxy.size.height)
      }
      FilmGrain()
    }
    .accessibilityHidden(true)
  }

  /// `color-mix(in srgb, a share%, b)`.
  private func mix(_ a: Color, _ share: Double, _ b: Color) -> Color {
    a.mix(with: b, by: 1 - share, in: .device)
  }
}

/// Os ruídos do hero. Cada ladrilho é gerado uma vez, na primeira vez que o
/// hero aparece, e depois só é desenhado repetido; nenhum quadro gera ruído.
enum FilmNoise {
  static let grainScale: CGFloat = 3
  static let grainPoints: CGFloat = 128
  /// Pontos claros de alfa variável. No web o `mix-blend-mode: overlay` mora
  /// dentro do contexto de empilhamento do próprio grão, então mistura com o
  /// vazio e vira composição normal: um véu claro que levanta a noite do topo.
  /// É esse o cartão aprovado, e overlay de verdade não clareia o escuro.
  static let grain = tile(pixels: 384, seed: 0x9e37_79b9) { noise, x, y in
    // O peso fica no ruído de um pixel. As camadas de 2 e 4 pixels formavam
    // manchas que liam como grão grosso na tela do iPhone.
    let v = 0.75 * noise(x, y, 1) + 0.25 * noise(x, y, 2)
    let a = 0.75 * noise(x + 97, y + 211, 1) + 0.25 * noise(x + 97, y + 211, 2)
    let gray = UInt8(clamping: Int((0.86 + 0.4 * (v - 0.5)) * 255))
    let alpha = UInt8(clamping: Int((0.5 + 0.9 * (a - 0.5)) * 255))
    return (gray, alpha)
  }

  /// Furos esparsos no corpo das letras, como a tinta falhando no papel. Onde
  /// o ruído passa do limiar a máscara zera. O limiar deixa uns 3% da área
  /// furada, perto do que o filtro do web fura; a borda de 0,06 deixa o furo
  /// macio em vez de um pixel duro.
  static let specksScale: CGFloat = 3
  static let specks = tile(pixels: 192, seed: 0x85eb_ca6b) { noise, x, y in
    let v = 0.6 * noise(x, y, 2) + 0.4 * noise(x, y, 4)
    let alpha = min(max((0.86 - v) / 0.06, 0), 1)
    return (255, UInt8(alpha * 255))
  }

  /// Ruído de valor em ladrilho: a grade dá a volta nas bordas, então a
  /// repetição não mostra emenda.
  private static func tile(
    pixels: Int, seed: UInt64,
    pixel: ((Int, Int, Int) -> Double, Int, Int) -> (gray: UInt8, alpha: UInt8)
  ) -> CGImage? {
    var state = seed
    var lattices: [Int: [Double]] = [:]
    for cell in [1, 2, 4] {
      let side = pixels / cell
      lattices[cell] = (0..<(side * side)).map { _ in
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
      }
    }
    func noise(_ x: Int, _ y: Int, _ cell: Int) -> Double {
      let side = pixels / cell
      let values = lattices[cell]!
      let fx = Double(x) / Double(cell), fy = Double(y) / Double(cell)
      let x0 = Int(fx), y0 = Int(fy)
      let tx = smooth(fx - Double(x0)), ty = smooth(fy - Double(y0))
      func at(_ i: Int, _ j: Int) -> Double { values[(j % side) * side + (i % side)] }
      let top = at(x0, y0) + (at(x0 + 1, y0) - at(x0, y0)) * tx
      let bottom = at(x0, y0 + 1) + (at(x0 + 1, y0 + 1) - at(x0, y0 + 1)) * tx
      return top + (bottom - top) * ty
    }
    var bytes = [UInt8](repeating: 0, count: pixels * pixels * 4)
    for y in 0..<pixels {
      for x in 0..<pixels {
        let (gray, alpha) = pixel(noise, x, y)
        // Pré-multiplicado, como o contexto pede.
        let value = UInt8(Int(gray) * Int(alpha) / 255)
        let offset = (y * pixels + x) * 4
        bytes[offset] = value
        bytes[offset + 1] = value
        bytes[offset + 2] = value
        bytes[offset + 3] = alpha
      }
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)
    return provider.flatMap {
      CGImage(
        width: pixels, height: pixels, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: pixels * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: $0, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
  }

  private static func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }

  /// Um salto por quadro, sempre para um ponto inteiro: com o ladrilho em 3x,
  /// um ponto é um pixel inteiro do ladrilho e o ruído não borra na reamostragem.
  static func jitter(frame: Int) -> CGSize {
    var hash = UInt64(bitPattern: Int64(frame)) &* 0x9e37_79b9_7f4a_7c15
    hash ^= hash >> 29
    let x = Double(hash & 0xff) / 255, y = Double((hash >> 8) & 0xff) / 255
    return CGSize(width: ((x - 0.5) * grainPoints).rounded(), height: ((y - 0.5) * grainPoints).rounded())
  }
}

/// O grão de filme por cima do degradê, embaixo do texto. Quatro saltos por
/// segundo: seis cansavam a vista no cartão parado. Com movimento reduzido fica parado.
private struct FilmGrain: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    if let tile = FilmNoise.grain {
      if reduceMotion {
        layer(tile, frame: 0)
      } else {
        TimelineView(.periodic(from: .now, by: 1.0 / 4)) { context in
          layer(tile, frame: Int(context.date.timeIntervalSinceReferenceDate * 4))
        }
      }
    }
  }

  private func layer(_ tile: CGImage, frame: Int) -> some View {
    Image(decorative: tile, scale: FilmNoise.grainScale)
      .resizable(resizingMode: .tile)
      // Um ladrilho a mais de cada lado, para o salto nunca mostrar a borda.
      .padding(-FilmNoise.grainPoints)
      .offset(FilmNoise.jitter(frame: frame))
      .opacity(0.4)
      .allowsHitTesting(false)
  }
}

/// A serifada do web, a mesma fonte variável. O peso 465 fica entre os
/// nomeados, então a fonte sai do eixo `wght` e não de um nome.
enum HeroSerif {
  private static let wght = 0x7767_6874
  private static let opsz = 0x6f70_737a

  // O CTFontDescriptor é imutável, só não vem marcado como Sendable.
  nonisolated(unsafe) private static let descriptor: CTFontDescriptor? = {
    guard let url = Bundle.module.url(forResource: "AnthropicSerif", withExtension: "ttf") else {
      return nil
    }
    // Falha quando já está registrada, e aí a fonte continua valendo.
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    return (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first
  }()

  static func font(size: CGFloat) -> Font {
    guard let descriptor else { return .system(size: size, weight: .medium, design: .serif) }
    let variation = [wght: 465, opsz: 48] as CFDictionary
    let varied = CTFontDescriptorCreateCopyWithAttributes(
      descriptor, [kCTFontVariationAttribute: variation] as CFDictionary)
    return Font(CTFontCreateWithFontDescriptor(varied, size, nil))
  }
}

/// O título com cara de impresso: um desfoque de 0,4 ponto e furos esparsos na
/// tinta. A máscara só muda o desenho; o VoiceOver lê o texto normal.
struct FilmTitle: View {
  let text: String
  let size: CGFloat

  var body: some View {
    // A altura de linha exata deixa o quadro menor que a letra, e desfoque e
    // máscara só desenham dentro do quadro: a perna do "p" e o acento do "Á"
    // eram cortados. A folga cresce o quadro só para os dois, e a folga
    // negativa devolve o tamanho que o layout mede.
    let vertical = size * 0.4
    let horizontal = size * 0.1
    lettering
      .padding(.vertical, vertical)
      .padding(.horizontal, horizontal)
      .blur(radius: 0.4)
      .mask {
        if let specks = FilmNoise.specks {
          Image(decorative: specks, scale: FilmNoise.specksScale).resizable(resizingMode: .tile)
        } else {
          Rectangle()
        }
      }
      .padding(.vertical, -vertical)
      .padding(.horizontal, -horizontal)
  }

  /// Em 76 pontos "Superiores" não cabe num iPhone e o texto quebraria no
  /// meio da palavra. O tamanho desce até a palavra mais longa caber inteira;
  /// nomes de várias palavras continuam quebrando nos espaços.
  var lettering: some View {
    ViewThatFits(in: .horizontal) {
      ForEach([1, 0.85, 0.72, 0.6], id: \.self) { scale in
        fitted(size: size * scale)
      }
    }
  }

  /// A largura ideal é a da palavra mais longa, que o `ViewThatFits` compara
  /// com o cartão. O título de verdade não pede largura nenhuma.
  private func fitted(size: CGFloat) -> some View {
    let longest = text.split(separator: " ").map(String.init).max { $0.count < $1.count } ?? text
    return ZStack(alignment: .topLeading) {
      styled(longest, size: size).fixedSize().hidden()
      styled(text, size: size)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
  }

  private func styled(_ text: String, size: CGFloat) -> some View {
    Text(text)
      .font(HeroSerif.font(size: size))
      .tracking(-0.012 * size)
      .lineHeight(.exact(points: size * 1.05))
      .foregroundStyle(HeroInk.title)
  }
}

/// O botão de começar como recorte de papel colado: o contorno troca entre
/// três recortes a cada 0,2s, e uma sombra do contorno treme no próprio ritmo.
private struct PaperButton: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let label: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      if reduceMotion {
        paper(tick: 0)
      } else {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
          paper(tick: Int(context.date.timeIntervalSinceReferenceDate * 10))
        }
      }
    }
    .buttonStyle(StudyPressStyle())
  }

  private static let cuts: [(seed: UInt64, angle: Double, offset: CGSize)] = [
    (4, -0.6, .zero), (17, 0.4, CGSize(width: 0.6, height: -0.4)),
    (29, -0.2, CGSize(width: -0.5, height: 0.5)),
  ]
  private static let ghostOffsets = [
    CGSize(width: 1.8, height: 1.2), CGSize(width: -1.2, height: 1.6), CGSize(width: 1.4, height: -1),
  ]

  private func paper(tick: Int) -> some View {
    let cut = Self.cuts[(tick / 2) % 3]
    return Text(label)
      .font(.system(size: 15, weight: .semibold)).tracking(0.15)
      .foregroundStyle(HeroInk.cream)
      .padding(.horizontal, 24).frame(height: 48)
      .background {
        Capsule().stroke(HeroInk.cream, lineWidth: 1)
          .padding(-1.5).opacity(0.32)
          .offset(Self.ghostOffsets[(tick / 3) % 3])
      }
      .background { PaperCapsule(seed: cut.seed).stroke(HeroInk.cream, lineWidth: 1.5) }
      .contentShape(.capsule)
      .rotationEffect(.degrees(cut.angle))
      .offset(cut.offset)
  }
}

/// Uma cápsula com a borda de papel cortado à tesoura. O contorno anda pelo
/// perímetro e cada ponto sai na normal por uma soma de senoides de onda longa.
/// O número de ondas é inteiro para a borda fechar sem degrau.
struct PaperCapsule: Shape {
  let seed: UInt64
  var amplitude: CGFloat = 0.8

  func path(in rect: CGRect) -> Path {
    let r = rect.height / 2
    let straight = max(rect.width - 2 * r, 0)
    let length = 2 * straight + 2 * .pi * r
    let count = max(Int(length / 2), 24)
    var state = seed &+ 1
    func random() -> Double {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return Double(state >> 11) / Double(1 << 53)
    }
    // Ondas de uns 40 e 22 pontos, a frequência 0,045 do web.
    let waves = [(40.0, 0.65), (22.0, 0.35)].map { wavelength, weight in
      (cycles: max((Double(length) / wavelength).rounded(), 1), phase: random() * 2 * .pi, weight: weight)
    }
    var path = Path()
    for index in 0..<count {
      let s = length * CGFloat(index) / CGFloat(count)
      let (point, normal) = Self.point(at: s, rect: rect, radius: r, straight: straight)
      let t = Double(index) / Double(count)
      let shift = waves.reduce(0.0) { $0 + $1.weight * sin(2 * .pi * $1.cycles * t + $1.phase) }
      let moved = CGPoint(
        x: point.x + normal.dx * amplitude * shift, y: point.y + normal.dy * amplitude * shift)
      index == 0 ? path.move(to: moved) : path.addLine(to: moved)
    }
    path.closeSubpath()
    return path
  }

  /// O ponto a `s` do começo do lado de cima, andando no sentido horário.
  private static func point(at s: CGFloat, rect: CGRect, radius r: CGFloat, straight: CGFloat)
    -> (CGPoint, CGVector)
  {
    let arc = CGFloat.pi * r
    switch s {
    case ..<straight:
      return (CGPoint(x: rect.minX + r + s, y: rect.minY), CGVector(dx: 0, dy: -1))
    case ..<(straight + arc):
      let angle = -CGFloat.pi / 2 + (s - straight) / r
      let normal = CGVector(dx: cos(angle), dy: sin(angle))
      return (CGPoint(x: rect.maxX - r + r * normal.dx, y: rect.midY + r * normal.dy), normal)
    case ..<(2 * straight + arc):
      let t = s - straight - arc
      return (CGPoint(x: rect.maxX - r - t, y: rect.maxY), CGVector(dx: 0, dy: 1))
    default:
      let angle = CGFloat.pi / 2 + (s - 2 * straight - arc) / r
      let normal = CGVector(dx: cos(angle), dy: sin(angle))
      return (CGPoint(x: rect.minX + r + r * normal.dx, y: rect.midY + r * normal.dy), normal)
    }
  }
}
