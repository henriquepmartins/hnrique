import HenriqueCore
import SwiftUI

// MARK: - A aparência de cada nível

/// Tudo o que muda de um nível para o outro. Cada nível tem mais peças que o
/// anterior, e a tabela em `StreakTier.style` é o único lugar que sabe disso.
struct BadgeStyle {
  var points: Int
  var layers: Int
  var neon: Bool
  var rays: Bool
  var spinningRays = false
  var sheen: Bool
  var confetti: Int
  var front: [Color]
  var middle: [Color]
  var back: [Color]
  var shiftsHue = false

  /// As faixas atrás da chama acendem junto com os raios.
  var fan: Bool { rays }
}

extension StreakTier {
  var style: BadgeStyle {
    switch self {
    case .ferro:
      BadgeStyle(
        points: 6, layers: 1, neon: false, rays: false, sheen: false, confetti: 0,
        front: [Color(hex: 0xA7AEB8), Color(hex: 0x5E656E)],
        middle: [], back: [])
    case .bronze:
      BadgeStyle(
        points: 7, layers: 2, neon: false, rays: false, sheen: false, confetti: 0,
        front: [Color(hex: 0xE0A06B), Color(hex: 0x8C4F2A)],
        middle: [], back: [Color(hex: 0xF3C79B), Color(hex: 0xB0703F)])
    case .prata:
      BadgeStyle(
        points: 8, layers: 2, neon: true, rays: false, sheen: false, confetti: 0,
        front: [Color(hex: 0xF2F5F8), Color(hex: 0x9AA4B0)],
        middle: [], back: [Color(hex: 0xC9D1DA), Color(hex: 0x6F7B88)])
    case .ouro:
      BadgeStyle(
        points: 8, layers: 3, neon: true, rays: true, sheen: false, confetti: 12,
        front: [Color(hex: 0xFFE27A), Color(hex: 0xE59B1B)],
        middle: [Color(hex: 0xF7B24A), Color(hex: 0xC56A12)],
        back: [Color(hex: 0xFFF1B8), Color(hex: 0xF2C14E)])
    case .platina:
      BadgeStyle(
        points: 10, layers: 3, neon: true, rays: true, sheen: true, confetti: 16,
        front: [Color(hex: 0xD8F3F0), Color(hex: 0x5FB3AE)],
        middle: [Color(hex: 0x8ED3CC), Color(hex: 0x3A8B86)],
        back: [Color(hex: 0xEFFBF9), Color(hex: 0xA6DCD7)])
    case .diamante:
      BadgeStyle(
        points: 12, layers: 3, neon: true, rays: true, sheen: true, confetti: 20,
        front: [Color(hex: 0xBFEFFF), Color(hex: 0x3A8DFF)],
        middle: [Color(hex: 0x6FC2FF), Color(hex: 0x2359D1)],
        back: [Color(hex: 0xE3F8FF), Color(hex: 0x8FD3FF)])
    case .epico:
      BadgeStyle(
        points: 12, layers: 3, neon: true, rays: true, sheen: true, confetti: 28,
        front: [Color(hex: 0xE08CFF), Color(hex: 0x7A2BD9)],
        middle: [Color(hex: 0xFF7BCB), Color(hex: 0xB8328F)],
        back: [Color(hex: 0xF4C9FF), Color(hex: 0xB070F0)])
    case .imortal:
      BadgeStyle(
        points: 14, layers: 3, neon: true, rays: true, sheen: true, confetti: 32,
        front: [Color(hex: 0xFF6B6B), Color(hex: 0xA3122E)],
        middle: [Color(hex: 0xFFD36B), Color(hex: 0xD9791A)],
        back: [Color(hex: 0xFF9E9E), Color(hex: 0xC23A4E)])
    case .surreal:
      BadgeStyle(
        points: 14, layers: 3, neon: true, rays: true, sheen: true, confetti: 36,
        front: [Color(hex: 0xFF7AD9), Color(hex: 0x7B5CFF)],
        middle: [Color(hex: 0x6FF0FF), Color(hex: 0x3A8CFF)],
        back: [Color(hex: 0xD4A8FF), Color(hex: 0xFF6FB5)],
        shiftsHue: true)
    case .radiante:
      // Oito pontas por camada, e não dezesseis: as oito da frente somadas às
      // oito de trás, giradas meia ponta, são as dezesseis que aparecem, como
      // na referência.
      BadgeStyle(
        points: 8, layers: 3, neon: true, rays: true, spinningRays: true, sheen: true,
        confetti: 48,
        front: [Color(hex: 0x6C3BFF), Color(hex: 0x8F45F5)],
        middle: [Color(hex: 0xEE5C9C), Color(hex: 0xD8437F)],
        back: [Color(hex: 0xFFE08A), Color(hex: 0xF59E42)])
    }
  }
}

/// Uma camada da insígnia: a forma, as cores e o tamanho em relação à da frente.
private struct BadgeLayer {
  var shape: StarShape
  var colors: [Color]
  var scale: CGFloat

  /// De trás para a frente. As de trás são mais pontudas e maiores, então
  /// aparecem só nas pontas; a do meio gira meia ponta e ocupa os vãos.
  static func all(for style: BadgeStyle) -> [BadgeLayer] {
    let points = style.points
    // Razões que encolhem com o número de pontas, para a ponta ter a mesma
    // largura aparente em seis ou em catorze.
    let ratio = { (depth: Double) in 1 - depth / Double(points) }
    let front = BadgeLayer(
      shape: StarShape(points: points, innerRatio: ratio(1.6), turn: 0, rounding: 0.05),
      colors: style.front, scale: 1)
    let half = 0.5
    switch style.layers {
    case 1:
      return [front]
    case 2:
      return [
        BadgeLayer(
          shape: StarShape(points: points, innerRatio: ratio(2.2), turn: half),
          colors: style.back, scale: 1.14),
        front,
      ]
    default:
      return [
        BadgeLayer(
          shape: StarShape(points: points, innerRatio: ratio(2.2), turn: 0),
          colors: style.back, scale: 1.2),
        BadgeLayer(
          shape: StarShape(points: points, innerRatio: ratio(2.4), turn: half),
          colors: style.middle, scale: 1.14),
        front,
      ]
    }
  }
}

// MARK: - As formas

/// Estrela de pontas e vãos arredondados, com a primeira ponta em cima. `turn`
/// gira a estrela em frações de ponta.
struct StarShape: Shape {
  var points: Int
  var innerRatio: CGFloat
  var turn: Double
  var rounding: CGFloat = 0.06

  func path(in rect: CGRect) -> Path {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let outer = min(rect.width, rect.height) / 2
    let step = Double.pi / Double(points)
    let vertices = (0..<(points * 2)).map { index in
      let angle = -Double.pi / 2 + step * (Double(index) + turn * 2)
      let radius = index.isMultiple(of: 2) ? outer : outer * innerRatio
      return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }
    return roundedPolygon(vertices, radius: outer * rounding)
  }
}

private func roundedPolygon(_ vertices: [CGPoint], radius: CGFloat) -> Path {
  var path = Path()
  let count = vertices.count
  for index in 0..<count {
    let previous = vertices[(index + count - 1) % count]
    let vertex = vertices[index]
    let next = vertices[(index + 1) % count]
    let toPrevious = hypot(previous.x - vertex.x, previous.y - vertex.y)
    let toNext = hypot(next.x - vertex.x, next.y - vertex.y)
    let cut = min(radius, toPrevious / 2, toNext / 2)
    let entry = CGPoint(
      x: vertex.x + (previous.x - vertex.x) * cut / toPrevious,
      y: vertex.y + (previous.y - vertex.y) * cut / toPrevious)
    let exit = CGPoint(
      x: vertex.x + (next.x - vertex.x) * cut / toNext,
      y: vertex.y + (next.y - vertex.y) * cut / toNext)
    if index == 0 { path.move(to: entry) } else { path.addLine(to: entry) }
    path.addQuadCurve(to: exit, control: vertex)
  }
  path.closeSubpath()
  return path
}

/// O disco escuro de borda ondulada que aparece antes das estrelas.
private struct ScallopShape: Shape {
  var waves = 14

  func path(in rect: CGRect) -> Path {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let radius = min(rect.width, rect.height) / 2
    var path = Path()
    let steps = waves * 12
    for index in 0...steps {
      let angle = Double(index) / Double(steps) * 2 * .pi
      let r = radius * (0.95 + 0.05 * cos(Double(waves) * angle))
      let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
      if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
  }
}

/// Brilho de quatro pontas.
private func sparklePath(center: CGPoint, radius: CGFloat) -> Path {
  var path = Path()
  let waist = radius * 0.22
  path.move(to: CGPoint(x: center.x, y: center.y - radius))
  path.addQuadCurve(
    to: CGPoint(x: center.x + radius, y: center.y),
    control: CGPoint(x: center.x + waist, y: center.y - waist))
  path.addQuadCurve(
    to: CGPoint(x: center.x, y: center.y + radius),
    control: CGPoint(x: center.x + waist, y: center.y + waist))
  path.addQuadCurve(
    to: CGPoint(x: center.x - radius, y: center.y),
    control: CGPoint(x: center.x - waist, y: center.y + waist))
  path.addQuadCurve(
    to: CGPoint(x: center.x, y: center.y - radius),
    control: CGPoint(x: center.x - waist, y: center.y - waist))
  path.closeSubpath()
  return path
}

/// As faixas que acendem atrás da chama, abrindo em leque a partir dela.
private struct FanShape: Shape {
  var wedges: [(Double, Double)]

  func path(in rect: CGRect) -> Path {
    let apex = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.6)
    let reach = rect.height
    var path = Path()
    for (from, to) in wedges {
      let a = (from - 90) * .pi / 180
      let b = (to - 90) * .pi / 180
      path.move(to: apex)
      path.addLine(to: CGPoint(x: apex.x + cos(a) * reach, y: apex.y + sin(a) * reach))
      path.addLine(to: CGPoint(x: apex.x + cos(b) * reach, y: apex.y + sin(b) * reach))
      path.closeSubpath()
    }
    return path
  }
}

// MARK: - A insígnia parada

/// Onde cada peça está num instante. A insígnia parada é `settled`; a camada
/// de comemoração calcula uma a cada quadro a partir do relógio.
struct BadgePose {
  struct Layer {
    var scale: Double = 1
    var spin: Double = 0
    var opacity: Double = 1
  }

  var layers = [Layer(), Layer(), Layer()]
  var fan: Double = 1
  var neon: Double = 1
  /// Posição do brilho diagonal de 0 a 1, nula fora da passada.
  var sheen: Double?

  static let settled = BadgePose()
}

struct InsigniaBadge: View {
  let tier: StreakTier
  var pose = BadgePose.settled
  let size: CGFloat
  var showsFlame = true
  /// Segundos desde a abertura. Só o surreal usa, para trocar de matiz.
  var time: Double = 0

  /// O quadro da chama dentro da insígnia, relativo ao centro dela. A chama que
  /// voa na comemoração pousa exatamente aqui.
  static func flameFrame(size: CGFloat) -> CGSize { CGSize(width: size * 0.34, height: size * 0.4) }
  static func flameOffset(size: CGFloat) -> CGFloat { size * 0.05 }

  var body: some View {
    let style = tier.style
    let layers = BadgeLayer.all(for: style)
    ZStack {
      ForEach(layers.indices, id: \.self) { index in
        let layer = layers[index]
        let layerPose = pose.layers[3 - layers.count + index]
        Group {
          if index == layers.count - 1 {
            front(layer, style: style)
          } else {
            plate(layer)
          }
        }
        .frame(width: size * layer.scale, height: size * layer.scale)
        .rotationEffect(.degrees(layerPose.spin))
        .scaleEffect(layerPose.scale)
        .opacity(layerPose.opacity)
      }
      if showsFlame {
        InsigniaFlame(litProgress: 1)
          .frame(
            width: Self.flameFrame(size: size).width, height: Self.flameFrame(size: size).height
          )
          .offset(y: Self.flameOffset(size: size))
          .scaleEffect(pose.layers[2].scale)
          .opacity(pose.layers[2].opacity)
      }
    }
    .hueRotation(.degrees(style.shiftsHue ? time * 50 : 0))
    .frame(width: size * 1.2, height: size * 1.2)
  }

  private func plate(_ layer: BadgeLayer) -> some View {
    layer.shape
      .fill(LinearGradient(colors: layer.colors, startPoint: .top, endPoint: .bottom))
      .overlay { rim(layer.shape) }
      .shadow(color: .black.opacity(0.22), radius: size * 0.03, y: size * 0.015)
  }

  /// A borda clara só do lado de dentro. Centrada na borda, a metade de fora
  /// caía no véu escuro e virava um contorno cinza.
  private func rim(_ shape: StarShape) -> some View {
    shape.stroke(.white.opacity(0.4), lineWidth: size * 0.024).clipShape(shape)
  }

  private func front(_ layer: BadgeLayer, style: BadgeStyle) -> some View {
    let shape = layer.shape
    let line = max(1.5, size * 0.014)
    return ZStack {
      shape.fill(LinearGradient(colors: layer.colors, startPoint: .top, endPoint: .bottom))
      if style.fan {
        fan(style: style).opacity(pose.fan)
      }
      if style.neon {
        let inset = StarShape(
          points: shape.points, innerRatio: shape.innerRatio, turn: shape.turn, rounding: 0.08)
        let trace = inset.trim(from: 0, to: pose.neon / 2)
          .stroke(.white, style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
        ZStack {
          trace
          trace.scaleEffect(x: -1, y: 1)
        }
        .padding(size * 0.1)
        .shadow(color: .white.opacity(0.9), radius: size * 0.012)
        .shadow(color: (layer.colors.last ?? .white).opacity(0.9), radius: size * 0.04)
      }
      if style.sheen, let sheen = pose.sheen {
        LinearGradient(
          colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading,
          endPoint: .trailing
        )
        .frame(width: size * 0.22, height: size * 1.6)
        .rotationEffect(.degrees(24))
        .offset(x: size * (sheen * 1.6 - 0.8))
      }
    }
    .clipShape(shape)
    .overlay { rim(shape) }
    .shadow(color: .black.opacity(0.3), radius: size * 0.04, y: size * 0.02)
  }

  private func fan(style: BadgeStyle) -> some View {
    let fade = { (colors: [Color]) in
      LinearGradient(colors: colors, startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.6))
    }
    let glow = RadialGradient(
      colors: [.white.opacity(0.95), .white.opacity(0)], center: UnitPoint(x: 0.5, y: 0.55),
      startRadius: 0, endRadius: size * 0.3)
    return ZStack {
      FanShape(wedges: [(-46, -24), (24, 46)])
        .fill(fade([.white.opacity(0.22), .white.opacity(0.7)]))
      FanShape(wedges: [(-19, 19)])
        .fill(
          LinearGradient(
            stops: [
              .init(color: style.middle[0], location: 0),
              .init(color: style.middle[1], location: 0.3),
              .init(color: .white, location: 0.62),
            ], startPoint: .top, endPoint: .bottom))
      FanShape(wedges: [(-23, -20), (20, 23)])
        .fill(fade([.white.opacity(0.35), .white.opacity(0.8)]))
      Rectangle().fill(glow)
      Path { path in
        path.addPath(
          sparklePath(center: CGPoint(x: size * 0.5, y: size * 0.2), radius: size * 0.055))
      }
      .fill(Color(hex: 0xFFE27A))
    }
    .frame(width: size, height: size)
  }
}

/// A chama do contador, em qualquer tamanho. `litProgress` acende o degradê
/// por cima do cinza, para a chama apagada do topo acender no voo.
struct InsigniaFlame: View {
  var litProgress: Double

  var body: some View {
    Image(systemName: "flame.fill")
      .resizable()
      .scaledToFit()
      .foregroundStyle(Color.mutedInk)
      .overlay {
        Image(systemName: "flame.fill")
          .resizable()
          .scaledToFit()
          .foregroundStyle(streakGradient)
          .opacity(litProgress)
      }
  }
}

// MARK: - A comemoração

/// O que a camada e o contador do topo dividem. Mora num objeto, e não em
/// valores passados ao contador, porque trocar um valor dentro da barra refaz o
/// item dela, e o número piscava três quadros ao abrir a insígnia.
@MainActor @Observable final class InsigniaStage {
  var show: InsigniaShow?
  @ObservationIgnored var flameFrame: CGRect?
}

/// A camada quando há comemoração aberta. Lê `stage.show` aqui dentro para só
/// ela redesenhar quando a comemoração abre e fecha.
struct InsigniaOverlay: View {
  let stage: InsigniaStage
  let onClose: () -> Void

  var body: some View {
    if let show = stage.show {
      InsigniaLayer(show: show, onClose: onClose)
    }
  }
}

/// Uma comemoração aberta. `origin` é o quadro global da chama do topo quando
/// ela abriu, nulo se o contador não estava na tela.
struct InsigniaShow: Equatable {
  var tier: StreakTier
  var months: Int
  var origin: CGRect?
  var wasLit: Bool
  var opened: Date
  var closed: Date?
}

extension StreakTier {
  func monthsLabel(_ months: Int) -> String {
    months == 1 ? "1 mês de presença" : "\(months) meses de presença"
  }
}

/// Quando cada peça entra, em segundos desde a abertura, e quanto dura o fechar.
enum InsigniaBeat {
  static let flight = 0.55
  static let disc = 0.25
  static let layers = 0.35
  static let layerStep = 0.08
  static let rings = 0.9
  static let burst = 1.0
  static let neon = 1.2
  static let sheen = 1.4
  static let text = 1.5

  static func closing(reduceMotion: Bool) -> Double { reduceMotion ? 0.3 : 0.55 }
}

/// A camada por cima das abas. Tudo nela é função do tempo desde a abertura e
/// desde o fechar, lidos de um `TimelineView` só.
struct InsigniaLayer: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let show: InsigniaShow
  let onClose: () -> Void

  var body: some View {
    GeometryReader { proxy in
      TimelineView(.animation) { context in
        scene(
          at: context.date, size: proxy.size, origin: localOrigin(proxy),
          layerOrigin: proxy.frame(in: .global).origin)
      }
    }
    .ignoresSafeArea()
    .contentShape(.rect)
    .onTapGesture(perform: onClose)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("insígnia \(show.tier.name), \(show.tier.monthsLabel(show.months))")
    .accessibilityHint("fechar")
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { onClose() }
  }

  private func localOrigin(_ proxy: GeometryProxy) -> CGRect {
    let global = proxy.frame(in: .global).origin
    if let origin = show.origin {
      return origin.offsetBy(dx: -global.x, dy: -global.y)
    }
    let top = proxy.safeAreaInsets.top > 0 ? proxy.safeAreaInsets.top : 62
    return CGRect(x: 24, y: top + 12, width: 17, height: 20)
  }

  @ViewBuilder
  private func scene(at now: Date, size: CGSize, origin: CGRect, layerOrigin: CGPoint) -> some View {
    let clock = InsigniaClock(show: show, now: now, reduceMotion: reduceMotion)
    let badge = min(size.width * 0.58, 250)
    let center = CGPoint(x: size.width / 2, y: size.height * 0.42)
    let style = show.tier.style
    let flame = clock.flame(from: origin, to: landing(center: center, badge: badge))

    ZStack(alignment: .topLeading) {
      Color.black.opacity(0.9 * clock.veil)

      Canvas { context, _ in
        drawRays(in: &context, center: center, badge: badge, style: style, clock: clock)
        drawRings(in: &context, center: center, badge: badge, style: style, clock: clock)
      }

      ScallopShape()
        .fill(Color(hex: 0x1E1E24))
        .overlay { ScallopShape().stroke(.white.opacity(0.08), lineWidth: 1) }
        .frame(width: badge * 1.1, height: badge * 1.1)
        .scaleEffect(clock.disc.scale)
        .opacity(clock.disc.opacity)
        .position(center)

      InsigniaBadge(
        tier: show.tier, pose: clock.badge, size: badge, showsFlame: false, time: clock.t
      )
      .position(center)

      Canvas { context, _ in
        drawConfetti(in: &context, center: center, badge: badge, style: style, clock: clock)
        drawSparkles(in: &context, center: center, badge: badge, clock: clock)
      }

      InsigniaFlame(litProgress: show.wasLit ? 1 : clock.lit)
        .frame(width: flame.rect.width, height: flame.rect.height)
        .scaleEffect(x: flame.squash.width, y: flame.squash.height, anchor: .bottom)
        .shadow(color: .orange.opacity(0.5 * clock.flameGlow), radius: badge * 0.06)
        .opacity(flame.opacity)
        .position(x: flame.rect.midX, y: flame.rect.midY)

      VStack(spacing: 6) {
        Text(show.tier.name)
          .font(.system(size: 40, weight: .heavy, design: .rounded))
          .foregroundStyle(.white)
        Text(show.tier.monthsLabel(show.months))
          .font(.headline)
          .foregroundStyle(.white.opacity(0.72))
      }
      .opacity(clock.text)
      .frame(width: size.width)
      .position(x: center.x, y: center.y + badge * 0.9)
    }
    .frame(width: size.width, height: size.height)
  }

  private func landing(center: CGPoint, badge: CGFloat) -> CGRect {
    let flame = InsigniaBadge.flameFrame(size: badge)
    return CGRect(
      x: center.x - flame.width / 2,
      y: center.y + InsigniaBadge.flameOffset(size: badge) - flame.height / 2,
      width: flame.width, height: flame.height)
  }

  // MARK: Canvas

  private func drawRays(
    in context: inout GraphicsContext, center: CGPoint, badge: CGFloat, style: BadgeStyle,
    clock: InsigniaClock
  ) {
    guard style.rays, clock.rays > 0 else { return }
    let count = style.spinningRays ? 22 : 16
    let spin = style.spinningRays ? clock.t * 0.18 : 0
    let inner = badge * 0.42
    for index in 0..<count {
      let seed = Particle.unit(index, salt: 11)
      let angle = Double(index) / Double(count) * 2 * .pi + spin + (seed - 0.5) * 0.12
      let pulse = clock.reduceMotion ? 1 : 0.7 + 0.3 * sin(clock.t * 2.2 + Double(index) * 1.7)
      let outer = inner + badge * (0.45 + 0.35 * seed) * clock.rays
      let width = 0.03 + 0.02 * Particle.unit(index, salt: 12)
      var wedge = Path()
      wedge.move(to: point(center, angle - width, inner))
      wedge.addLine(to: point(center, angle - width * 0.4, outer))
      wedge.addLine(to: point(center, angle + width * 0.4, outer))
      wedge.addLine(to: point(center, angle + width, inner))
      wedge.closeSubpath()
      context.fill(
        wedge,
        with: .radialGradient(
          Gradient(colors: [
            Color(hex: 0xFFE3A3).opacity(0.5 * pulse * clock.rays * clock.fadeOut),
            Color(hex: 0xFFE3A3).opacity(0),
          ]), center: center, startRadius: inner, endRadius: outer))
    }
  }

  private func drawRings(
    in context: inout GraphicsContext, center: CGPoint, badge: CGFloat, style: BadgeStyle,
    clock: InsigniaClock
  ) {
    let rings: [(progress: Double, from: CGFloat, to: CGFloat, color: Color)] = [
      (clock.goldRing, 0.62, 1.02, Color(hex: 0xFFD66B)),
      (clock.pinkRing, 0.66, 1.18, style.middle.first ?? style.front[0]),
    ]
    for ring in rings where ring.progress > 0 && ring.progress < 1 {
      let grown = easeOut(ring.progress)
      let radius = badge * (ring.from + (ring.to - ring.from) * grown)
      let circle = Path(
        ellipseIn: CGRect(
          x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
      context.stroke(
        circle, with: .color(ring.color.opacity((1 - ring.progress) * clock.fadeOut)),
        lineWidth: badge * 0.014 * (1.4 - grown))
    }
  }

  private func drawConfetti(
    in context: inout GraphicsContext, center: CGPoint, badge: CGFloat, style: BadgeStyle,
    clock: InsigniaClock
  ) {
    guard !clock.reduceMotion, style.confetti > 0 else { return }
    let palette = [
      style.front[0], style.middle.first ?? style.front[1], style.back.first ?? .white,
      Color(hex: 0xFFD66B), .white,
    ]
    for index in 0..<style.confetti {
      let particle = Particle(index)
      let age = clock.t - InsigniaBeat.burst - particle.delay
      guard age > 0, age < particle.life else { continue }
      let drag = 3.0
      let travel = particle.speed * badge / drag * (1 - exp(-drag * age))
      let start = badge * 0.3
      let position = CGPoint(
        x: center.x + cos(particle.angle) * (start + travel),
        y: center.y + sin(particle.angle) * (start + travel) + 0.5 * 90 * age * age)
      let fade = 1 - min(1, max(0, (age - (particle.life - 0.5)) / 0.5))
      var piece = context
      piece.opacity = fade * clock.fadeOut
      piece.translateBy(x: position.x, y: position.y)
      piece.rotate(by: .radians(particle.spin * age + particle.angle))
      piece.scaleBy(x: cos(particle.flutter * age), y: 1)
      let rect = CGRect(
        x: -particle.width / 2, y: -particle.height / 2, width: particle.width,
        height: particle.height)
      piece.fill(
        Path(roundedRect: rect, cornerRadius: 1),
        with: .color(palette[index % palette.count]))
    }
  }

  private func drawSparkles(
    in context: inout GraphicsContext, center: CGPoint, badge: CGFloat, clock: InsigniaClock
  ) {
    guard !clock.reduceMotion, clock.t > InsigniaBeat.burst else { return }
    let count = 4 + show.tier.rawValue
    for index in 0..<count {
      let angle = Particle.unit(index, salt: 21) * 2 * .pi
      let distance = badge * (0.62 + 0.55 * Particle.unit(index, salt: 22))
      let period = 1.3 + Particle.unit(index, salt: 23)
      let phase = Particle.unit(index, salt: 24)
      let age = clock.t - InsigniaBeat.burst
      let wave = max(0, sin(2 * .pi * (age / period + phase)))
      let twinkle = pow(wave, 3)
      guard twinkle > 0.01 else { continue }
      let color = index.isMultiple(of: 3) ? Color.white : Color(hex: 0xFFD66B)
      context.fill(
        sparklePath(center: point(center, angle, distance), radius: badge * 0.035 * twinkle),
        with: .color(color.opacity(twinkle * clock.fadeOut)))
    }
  }

  private func point(_ center: CGPoint, _ angle: Double, _ radius: CGFloat) -> CGPoint {
    CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
  }
}

/// Um pedaço de confete, sorteado pelo índice. Sorteado a cada quadro, o mesmo
/// pedaço pularia de lugar; pelo índice ele é o mesmo em toda pintura.
private struct Particle {
  var angle: Double
  var speed: Double
  var delay: Double
  var life: Double
  var spin: Double
  var flutter: Double
  var width: CGFloat
  var height: CGFloat

  init(_ index: Int) {
    angle = Particle.unit(index, salt: 1) * 2 * .pi
    speed = 1.2 + 1.8 * Particle.unit(index, salt: 2)
    delay = 0.1 * Particle.unit(index, salt: 3)
    life = 1.6 + 1.2 * Particle.unit(index, salt: 4)
    spin = (Particle.unit(index, salt: 5) - 0.5) * 12
    flutter = 4 + 8 * Particle.unit(index, salt: 6)
    width = 3 + 2.5 * Particle.unit(index, salt: 7)
    height = 7 + 6 * Particle.unit(index, salt: 8)
  }

  /// Um número de 0 a 1 que depende só do índice e da semente.
  static func unit(_ index: Int, salt: UInt64) -> Double {
    var z = UInt64(index) &* 0x9E37_79B9_7F4A_7C15 &+ salt &* 0xD1B5_4A32_D192_ED03
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    z ^= z >> 31
    return Double(z >> 11) / Double(1 << 53)
  }
}

// MARK: - O relógio

private func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
private func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
private func easeInOut(_ x: Double) -> Double {
  x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
}

/// Cada peça da comemoração como função do tempo. Molas avaliadas no instante,
/// sem estado: o mesmo `t` desenha sempre o mesmo quadro.
struct InsigniaClock {
  let t: Double
  let reduceMotion: Bool
  /// De 0 a 1 ao longo do fechar; 0 enquanto a camada está aberta.
  let closing: Double
  /// O instante da abertura em que o fechar começou, para a chama voltar de onde estava.
  let closedAt: Double?

  init(show: InsigniaShow, now: Date, reduceMotion: Bool) {
    self.reduceMotion = reduceMotion
    t = max(0, now.timeIntervalSince(show.opened))
    if let closed = show.closed {
      closing = clamp(now.timeIntervalSince(closed) / InsigniaBeat.closing(reduceMotion: reduceMotion))
      closedAt = closed.timeIntervalSince(show.opened)
    } else {
      closing = 0
      closedAt = nil
    }
  }

  private func ramp(_ start: Double, _ duration: Double) -> Double { clamp((t - start) / duration) }

  private func spring(_ start: Double, duration: Double, bounce: Double) -> Double {
    let elapsed = t - start
    guard elapsed > 0 else { return 0 }
    return Spring(duration: duration, bounce: bounce).value(target: 1.0, time: elapsed)
  }

  /// O que some junto no fechar: véu, raios, confete e brilhos.
  var fadeOut: Double { 1 - easeInOut(closing) }

  /// Com movimento reduzido tudo entra e sai só em opacidade.
  private var fade: Double { ramp(0, 0.3) * fadeOut }

  var veil: Double { reduceMotion ? fade : easeOut(ramp(0, 0.5)) * fadeOut }

  var disc: (scale: Double, opacity: Double) {
    guard !reduceMotion else { return (1, 0) }
    let grown = spring(InsigniaBeat.disc, duration: 0.45, bounce: 0.25)
    return (0.6 + 0.4 * grown, ramp(InsigniaBeat.disc, 0.1) * (1 - ramp(0.7, 0.3)))
  }

  /// A insígnia recolhe no primeiro terço do fechar, antes da chama partir.
  private var collapse: Double { 1 - easeInOut(clamp(closing / 0.45)) }

  var badge: BadgePose {
    if reduceMotion {
      let layer = BadgePose.Layer(scale: 1, spin: 0, opacity: fade)
      return BadgePose(layers: [layer, layer, layer], fan: fade, neon: 1, sheen: nil)
    }
    let layers = (0..<3).map { index in
      let start = InsigniaBeat.layers + InsigniaBeat.layerStep * Double(index)
      let grown = spring(start, duration: 0.6, bounce: 0.34)
      let turn = index.isMultiple(of: 2) ? -150.0 : 120.0
      return BadgePose.Layer(
        scale: grown * collapse, spin: (1 - grown) * turn, opacity: ramp(start, 0.1))
    }
    let sheen = ramp(InsigniaBeat.sheen, 0.7)
    return BadgePose(
      layers: layers,
      fan: easeOut(ramp(InsigniaBeat.rings, 0.4)),
      neon: easeInOut(ramp(InsigniaBeat.neon, 0.55)),
      sheen: sheen > 0 && sheen < 1 ? easeInOut(sheen) : nil)
  }

  var goldRing: Double { reduceMotion ? 0 : ramp(InsigniaBeat.rings, 0.7) }
  var pinkRing: Double { reduceMotion ? 0 : ramp(InsigniaBeat.rings + 0.12, 0.85) }
  var rays: Double { reduceMotion ? fade : easeOut(ramp(InsigniaBeat.burst, 0.5)) }
  var text: Double {
    reduceMotion ? fade : ramp(InsigniaBeat.text, 0.35) * (1 - clamp(closing / 0.3))
  }
  /// Acende no voo de ida e apaga no de volta, para pousar igual à chama do topo.
  var lit: Double {
    reduceMotion ? 1 : ramp(0.05, 0.3) * (1 - easeInOut(clamp((closing - 0.3) / 0.7)))
  }
  var flameGlow: Double { ramp(InsigniaBeat.rings, 0.4) * fadeOut }

  struct Flame {
    var rect: CGRect
    var squash = CGSize(width: 1, height: 1)
    var opacity = 1.0
  }

  func flame(from origin: CGRect, to landing: CGRect) -> Flame {
    if reduceMotion {
      return Flame(rect: landing, opacity: fade)
    }
    let arrived = entranceFlame(at: t, from: origin, to: landing)
    guard let closedAt else { return arrived }
    // Volta de onde estava quando o toque chegou, que pode ser no meio do voo.
    let from = entranceFlame(at: closedAt, from: origin, to: landing).rect
    let back = easeInOut(clamp((closing - 0.15) / 0.85))
    return Flame(rect: lerp(from, origin, back))
  }

  private func entranceFlame(at time: Double, from origin: CGRect, to landing: CGRect) -> Flame {
    let travel =
      time <= 0 ? 0 : Spring(duration: InsigniaBeat.flight, bounce: 0).value(target: 1.0, time: time)
    let grow =
      time <= 0
      ? 0 : Spring(duration: InsigniaBeat.flight + 0.1, bounce: 0.28).value(target: 1.0, time: time)
    // Arco: sai para o lado pela altura do topo e desce no fim, em vez de ir reto.
    let start = CGPoint(x: origin.midX, y: origin.midY)
    let end = CGPoint(x: landing.midX, y: landing.midY)
    let control = CGPoint(x: end.x, y: start.y)
    let u = 1 - travel
    let center = CGPoint(
      x: u * u * start.x + 2 * u * travel * control.x + travel * travel * end.x,
      y: u * u * start.y + 2 * u * travel * control.y + travel * travel * end.y)
    let width = origin.width + (landing.width - origin.width) * grow
    let height = origin.height + (landing.height - origin.height) * grow
    // O pouso achata a chama um instante, como quem cai num colchão.
    let landed = clamp((time - InsigniaBeat.flight * 0.85) / 0.3)
    let bump = sin(landed * .pi) * 0.12
    return Flame(
      rect: CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height),
      squash: CGSize(width: 1 + bump * 0.7, height: 1 - bump))
  }

  private func lerp(_ a: CGRect, _ b: CGRect, _ x: Double) -> CGRect {
    CGRect(
      x: a.minX + (b.minX - a.minX) * x, y: a.minY + (b.minY - a.minY) * x,
      width: a.width + (b.width - a.width) * x, height: a.height + (b.height - a.height) * x)
  }
}
