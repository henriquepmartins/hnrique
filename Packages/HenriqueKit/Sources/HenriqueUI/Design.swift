import SwiftUI

extension Color {
  static let canvas = Color(hex: 0xfaf9f7)
  static let ink = Color(hex: 0x1a1a19)
  static let mutedInk = Color(hex: 0x6b6b6a)
  static let surfaceMuted = Color(hex: 0xf0efed)
}

/// A paleta dos cards de treino. Um treino sem cor escolhida herda o tom do seu
/// primeiro dia, então o par também vem endereçado por índice. O tom escuro é o
/// único legível sobre os dois extremos do degradê.
struct WorkoutTone: Sendable, Hashable {
  let top: Color
  let bottom: Color
  let ink: Color
  /// `#rrggbb` do topo. Um treino novo nasce com o primeiro hex da paleta que
  /// nenhum outro treino usa.
  let hex: String
  /// O topo em matiz, saturação e brilho, o ponto de partida do seletor.
  let color: WorkoutColor

  static let all: [WorkoutTone] = [
    WorkoutTone(top: 0xf9_7316, bottom: 0xfd_ba74, ink: 0x43_1407),
    WorkoutTone(top: 0x3b_82f6, bottom: 0x93_c5fd, ink: 0x17_2554),
    WorkoutTone(top: 0x8b_5cf6, bottom: 0xc4_b5fd, ink: 0x2e_1065),
    WorkoutTone(top: 0xef_4444, bottom: 0xfc_a5a5, ink: 0x45_0a0a),
    WorkoutTone(top: 0x22_c55e, bottom: 0x86_efac, ink: 0x05_2e16),
    WorkoutTone(top: 0xec_4899, bottom: 0xf9_a8d4, ink: 0x50_0724),
  ]

  /// Dá a volta na lista sozinho, então quem chama nunca precisa saber que são
  /// seis nem tratar índice negativo.
  static func at(_ index: Int) -> WorkoutTone {
    all[((index % all.count) + all.count) % all.count]
  }

  /// O tom de uma cor qualquer do servidor. Nulo quando a string não é `#rrggbb`.
  static func from(hex: String) -> WorkoutTone? {
    WorkoutColor(hex: hex)?.tone
  }

  /// O primeiro tom da paleta fora de `used`. Com a paleta esgotada, dá a volta.
  static func unused(among used: [String]) -> WorkoutTone {
    let taken = Set(used.map { $0.lowercased() })
    return all.first { !taken.contains($0.hex) } ?? at(used.count)
  }

  private init(top: UInt32, bottom: UInt32, ink: UInt32) {
    self.top = Color(hex: top)
    self.bottom = Color(hex: bottom)
    self.ink = Color(hex: ink)
    hex = String(format: "#%06x", top)
    color = WorkoutColor(rgb: top)
  }

  fileprivate init(top: Color, bottom: Color, ink: Color, color: WorkoutColor) {
    self.top = top
    self.bottom = bottom
    self.ink = ink
    self.color = color
    hex = color.hex
  }
}

/// A cor do treino como o seletor mexe nela. Fica em matiz, saturação e brilho
/// porque é isso que o dedo arrasta; o hex só entra e sai na borda do servidor.
struct WorkoutColor: Hashable, Sendable {
  var hue: Double
  var saturation: Double
  var brightness: Double

  init(hue: Double, saturation: Double, brightness: Double) {
    self.hue = hue
    self.saturation = saturation
    self.brightness = brightness
  }

  init?(hex: String) {
    var digits = Substring(hex)
    if digits.hasPrefix("#") { digits = digits.dropFirst() }
    guard digits.count == 6, let rgb = UInt32(digits, radix: 16) else { return nil }
    self.init(rgb: rgb)
  }

  init(rgb: UInt32) {
    let r = Double((rgb >> 16) & 0xff) / 255
    let g = Double((rgb >> 8) & 0xff) / 255
    let b = Double(rgb & 0xff) / 255
    let high = max(r, g, b)
    let low = min(r, g, b)
    let delta = high - low
    brightness = high
    saturation = high == 0 ? 0 : delta / high
    if delta == 0 {
      hue = 0
    } else if high == r {
      hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6) / 6
    } else if high == g {
      hue = ((b - r) / delta + 2) / 6
    } else {
      hue = ((r - g) / delta + 4) / 6
    }
    if hue < 0 { hue += 1 }
  }

  var hex: String {
    let (r, g, b) = rgb
    return String(format: "#%02x%02x%02x", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
  }

  /// O par de degradê e a tinta, com a mesma fórmula que gerou a paleta fixa.
  /// Abaixo de 0.4 de brilho a tinta vira branca, porque tinta escura sobre
  /// bloco escuro some.
  var tone: WorkoutTone {
    WorkoutTone(
      top: Color(hue: hue, saturation: saturation, brightness: brightness),
      bottom: Color(hue: hue, saturation: saturation * 0.55, brightness: min(1, brightness * 0.25 + 0.75)),
      ink: brightness < 0.4
        ? .white
        : Color(hue: hue, saturation: min(1, saturation * 1.1), brightness: brightness * 0.26),
      color: self)
  }

  private var rgb: (Double, Double, Double) {
    let c = brightness * saturation
    let sector = hue * 6
    let x = c * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
    let m = brightness - c
    let (r, g, b): (Double, Double, Double) =
      switch Int(sector) % 6 {
      case 0: (c, x, 0)
      case 1: (x, c, 0)
      case 2: (0, c, x)
      case 3: (0, x, c)
      case 4: (x, 0, c)
      default: (c, 0, x)
      }
    return (r + m, g + m, b + m)
  }
}

/// O passo entre peças de uma tela. Dentro de uma peça (ícone e texto, número e
/// unidade) o 2 e o 6 continuam valendo; entre peças, só estes.
enum Space {
  static let xs: CGFloat = 4
  static let s: CGFloat = 8
  static let m: CGFloat = 12
  static let l: CGFloat = 16
  static let xl: CGFloat = 20
  static let xxl: CGFloat = 24
  static let page: CGFloat = 32
}

/// Os raios da academia. Estudos tem os seus em `StudyRadius`.
enum Radius {
  static let card: CGFloat = 32
  static let tile: CGFloat = 24
  static let field: CGFloat = 10
  /// O raio da linha de lista, menor que o do cartão porque ela é uma fatia
  /// e não uma superfície.
  static let row: CGFloat = 20

  /// O raio de fora de uma peça que abraça outra: o de dentro mais o respiro
  /// entre as duas. Acima de 24 de respiro as duas já leem como superfícies
  /// separadas e cada uma escolhe o seu.
  static func concentric(_ inner: CGFloat, padding: CGFloat) -> CGFloat { inner + padding }
}

extension View {
  /// Cartão sobre o papel. Anel de 1pt a 6% e duas sombras curtas no lugar da
  /// borda cinza: a sombra é transparente e funciona sobre qualquer fundo, a
  /// borda sólida só sobre o fundo para o qual foi pintada.
  func paperCard(radius: CGFloat = Radius.card, fill: Color = .white) -> some View {
    elevated(RoundedRectangle(cornerRadius: radius), fill: fill)
  }

  func elevated<S: InsettableShape>(_ shape: S, fill: Color = .white) -> some View {
    modifier(Elevated(shape: shape, fill: fill))
  }
}

private struct Elevated<S: InsettableShape>: ViewModifier {
  @Environment(\.colorScheme) private var scheme
  let shape: S
  let fill: Color

  func body(content: Content) -> some View {
    content
      .background {
        // Uma cópia da forma por sombra. Encadeadas, a segunda sombra também
        // sombrearia a primeira.
        ZStack {
          shape.fill(fill).shadow(color: .black.opacity(scheme == .dark ? 0 : 0.04), radius: 2, y: 2)
          shape.fill(fill).shadow(color: .black.opacity(scheme == .dark ? 0 : 0.06), radius: 1, y: 1)
        }
      }
      .overlay {
        shape.strokeBorder(scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
      }
  }
}

/// Botão só de ícone com alvo de 44pt. `glass` põe o disco de vidro de 32pt que
/// os cabeçalhos de calendário usavam; o alvo continua 44 em volta dele.
struct IconButton: View {
  @Environment(\.isEnabled) private var isEnabled
  let title: String
  let systemImage: String
  var size: CGFloat = 15
  var glass = false
  // Ajuste óptico: o chevron pesa para o lado que aponta.
  var nudge: CGSize = .zero
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: size, weight: .semibold))
        .foregroundStyle(.tint)
        .offset(nudge)
        .frame(width: 32, height: 32)
        .glassEffect(glass ? .regular.interactive() : .identity, in: .circle)
        .frame(width: 44, height: 44)
        .contentShape(.rect)
        // Um ButtonStyle próprio não apaga sozinho quando desabilitado.
        .opacity(isEnabled ? 1 : 0.35)
    }
    .buttonStyle(StudyPressStyle())
    .accessibilityLabel(title)
  }
}

extension Text {
  // O "1" tabular deixa um vão na margem; o primeiro dígito fica proporcional.
  static func clock(_ s: String) -> Text {
    Text(String(s.prefix(1))) + Text(String(s.dropFirst())).monospacedDigit()
  }
}

struct PageHeading: View {
  @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 40.0
  let title: String

  var body: some View {
    Text(title).font(.system(size: titleSize, weight: .medium)).tracking(-titleSize * 0.055)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityAddTraits(.isHeader)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Movimento

/// As curvas de todo o app. As molas de `smooth` e `snappy` são o mesmo modelo
/// que o iOS usa nos próprios controles, então o que o app move acompanha o
/// que o sistema move em volta dele. Números soltos por tela eram o que fazia
/// duas telas vizinhas entrarem em ritmos diferentes.
enum Motion {
  /// Entrada é só opacidade. Conteúdo que já estava ali não deveria chegar
  /// deslizando.
  static let subtleEntrance = Animation.easeOut(duration: 0.3)
  /// Conteúdo que chega e se acomoda: cascata de lista, cartão que nasce.
  static let entrance = Animation.smooth(duration: 0.4)
  /// A mesma entrada para quem cresce no lugar, com o repique quase no fim.
  static let grow = Animation.spring(duration: 0.45, bounce: 0.18)
  /// Resposta ao dedo, onde qualquer atraso aparece.
  static let tap = Animation.snappy(duration: 0.22)
  /// Troca de uma tela inteira por outra.
  static let crossfade = Animation.smooth(duration: 0.3)
  /// Troca de filtro, de aba ou de chip. Mais curta que `tap` porque nada se
  /// move de lugar, só o conteúdo troca embaixo do dedo.
  static let swap = Animation.easeOut(duration: 0.12)
  /// Confirmar. O visto de série e o de entrega correm nesta, e sem repique:
  /// um pulo no fim deixa dúvida se a marcação pegou ou voltou.
  static let confirm = Animation.spring(duration: 0.3, bounce: 0)
  /// Seção que abre ou fecha crescendo em altura, empurrando o resto.
  static let expand = Animation.spring(duration: 0.38, bounce: 0.1)
  /// O cartão crescendo até virar a tela da sessão, sem repique, e a tela
  /// encolhendo de volta para ele mais rápido do que cresceu.
  static let open = Animation.smooth(duration: 0.5)
  static let close = Animation.smooth(duration: 0.32)
  /// Com movimento reduzido só a opacidade muda, e rápido.
  static let plain = Animation.easeOut(duration: 0.15)
  /// O rolo de dígito, a mola do board convertida. Os K 280, C 18 e M 0.3 dele
  /// dão 30,55 rad/s e amortecimento 0,98, que em resposta e fração são estes.
  static let roll = Animation.spring(response: 0.21, dampingFraction: 0.98)
  /// A barra de progresso e a barra de descanso subindo. Sem repique, que é o
  /// que a curva (.22,1,.36,1) do board faz.
  static let glide = Animation.spring(response: 0.45, dampingFraction: 1)
  /// O quanto um botão encolhe sob o dedo. Abaixo de 0.95 o botão parece
  /// afundar, e aí o toque vira um evento em vez de uma resposta.
  static let press: CGFloat = 0.96
  /// De que tamanho e de quanto desfoque um ícone entra.
  static let iconScale: CGFloat = 0.25
  static let iconBlur: CGFloat = 4

  /// O passo entre um item e o seguinte. O atraso para de crescer no sétimo
  /// para a última linha de uma lista longa não esperar a lista inteira.
  static func delay(index: Int) -> Double { 0.05 * Double(min(index, 6)) }
}

/// Um ícone que entra. Opacidade, escala e desfoque ao mesmo tempo. Sem o
/// desfoque, um glifo crescendo de 0.25 lê como estalo; com ele, lê como uma
/// coisa entrando em foco, que é o que o iOS faz quando um ícone troca.
struct IconAppear: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content
      .scaleEffect(phase.isIdentity ? 1 : Motion.iconScale)
      .opacity(phase.isIdentity ? 1 : 0)
      .blur(radius: phase.isIdentity ? 0 : Motion.iconBlur)
  }
}

extension Transition where Self == IconAppear {
  static var iconAppear: IconAppear { IconAppear() }
}

struct StudyPressStyle: ButtonStyle {
  /// Quanto o alvo de toque cresce para cada lado sem mexer no layout. É o
  /// truque do quadrado de `StudyTaskCard`: o padding estende a área que o dedo
  /// acerta e o padding negativo devolve o espaço à linha.
  var slop: CGFloat = 0

  func makeBody(configuration: Configuration) -> some View {
    Press(configuration: configuration)
      .padding(slop)
      .contentShape(.rect)
      .padding(-slop)
  }

  private struct Press: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let configuration: ButtonStyleConfiguration

    var body: some View {
      configuration.label
        .scaleEffect(configuration.isPressed && !reduceMotion ? Motion.press : 1)
        .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
        // O encolher acontece no mesmo quadro do toque. Só a volta tem curva,
        // senão o botão parece responder atrasado ao dedo.
        .animation(configuration.isPressed ? nil : Motion.tap, value: configuration.isPressed)
    }
  }
}

extension View {
  func subtleEntrance() -> some View {
    modifier(SubtleEntrance())
  }

  /// Entrada em cascata da primeira montagem da lista. `isReady` é o momento em
  /// que os dados chegaram; o atraso para no sexto item para a última linha não
  /// esperar.
  ///
  /// `columns` é quantas colunas a grade que segura este item tem. A cascata só
  /// corre na vertical: duas peças lado a lado entram juntas, senão o olho lê
  /// uma varredura na diagonal em vez de um fade de baixo para cima.
  func staggeredEntrance(index: Int, columns: Int = 1, isReady: Bool) -> some View {
    modifier(StudyStaggeredEntrance(index: index / max(columns, 1), isReady: isReady))
  }

  func firstEntrance(index: Int, settled: Bool) -> some View {
    modifier(StudyStaggeredEntrance(index: index, isReady: true, settled: settled))
  }
}

private struct SubtleEntrance: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var shown = false

  func body(content: Content) -> some View {
    content
      // A curva fica só no fade, sem animar o layout da grade.
      .animation(reduceMotion ? Motion.plain : Motion.subtleEntrance) { view in
        view.opacity(shown ? 1 : 0)
      }
      .onAppear { shown = true }
  }
}

private struct StudyStaggeredEntrance: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var shown = false
  let index: Int
  let isReady: Bool
  var settled = false

  func body(content: Content) -> some View {
    content
      .animation(animation) { view in
        view.opacity(shown || settled ? 1 : 0)
      }
      .onChange(of: isReady, initial: true) { _, ready in
        if ready { shown = true }
      }
  }

  private var animation: Animation {
    reduceMotion ? Motion.plain : Motion.subtleEntrance.delay(Motion.delay(index: index))
  }
}

extension View {
  @ViewBuilder
  func decimalInput() -> some View {
    #if os(iOS)
    self.keyboardType(.decimalPad)
    #else
    self
    #endif
  }
}

#if os(iOS)
import UIKit
#endif

extension View {
  func keyboardDone() -> some View {
    modifier(KeyboardDone())
  }
}

private struct KeyboardDone: ViewModifier {
  func body(content: Content) -> some View {
    #if os(iOS)
    content
      .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          KeyboardDoneButton()
        }
      }
      .onSubmit { dismissKeyboard() }
    #else
    content
    #endif
  }
}

struct KeyboardDoneButton: View {
  var body: some View {
    Button("concluído", action: dismissKeyboard)
      .accessibilityIdentifier("keyboard.done")
  }
}

@MainActor
func dismissKeyboard() {
  #if os(iOS)
  UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
    to: nil, from: nil, for: nil)
  #endif
}

extension View {
  /// A entrada das telas que nascem inteiras, controlada por quem chama em vez de
  /// pelo `onAppear`. Cada peça só aparece, em cascata, sem crescer nem andar.
  func revealEntrance(index: Int, shown: Bool) -> some View {
    modifier(RevealEntrance(index: index, shown: shown))
  }
}

private struct RevealEntrance: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let index: Int
  let shown: Bool

  func body(content: Content) -> some View {
    content
      .animation(
        reduceMotion ? nil : Motion.subtleEntrance.delay(Motion.delay(index: index))
      ) { view in
        view.opacity(visible ? 1 : 0)
      }
  }

  private var visible: Bool { shown || reduceMotion }
}
