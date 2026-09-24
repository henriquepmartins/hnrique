import SwiftUI

/// A sessão de treino entrando por cima das abas. É o mesmo fade-in do resto do
/// app, com um desfoque que assenta e uma subida curta. Nada escala nem anda de
/// lado: o zoom do sistema encolhia o conteúdo junto com o cartão e puxava a
/// tela para o canto de onde ela saía.
struct SessionBloom: Transition {
  var reduceMotion: Bool

  func body(content: Content, phase: TransitionPhase) -> some View {
    let moving = !phase.isIdentity && !reduceMotion
    content
      .opacity(phase.isIdentity ? 1 : 0)
      .blur(radius: moving ? 14 : 0)
      .offset(y: moving ? (phase == .willAppear ? 20 : 8) : 0)
  }
}

/// A luz que acende nas bordas quando a sessão abre, como a Siri nova: ela sobe
/// pelos dois lados a partir de baixo e se apaga quando o conteúdo assenta.
struct SessionGlow: View {
  @Environment(\.accent) private var accent
  @State private var rise: CGFloat = 0
  @State private var lit = 1.0

  var body: some View {
    GeometryReader { geo in
      let shape = RoundedRectangle(cornerRadius: 52, style: .continuous)
      let light = AngularGradient(
        colors: [accent.signal, accent.base, accent.acid, accent.pale, accent.signal],
        center: .center)
      ZStack {
        shape.stroke(light, lineWidth: 18).blur(radius: 16)
        shape.stroke(light, lineWidth: 2.5).blur(radius: 1)
      }
      // A máscara é mais alta que a tela para a borda de cima dela, que é um
      // degradê, passar inteira antes de a luz se apagar.
      .mask(alignment: .bottom) {
        LinearGradient(
          stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.3)],
          startPoint: .top, endPoint: .bottom
        )
        .frame(height: geo.size.height * 1.4 * rise)
      }
      .opacity(lit)
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .onAppear {
      withAnimation(Motion.bloom) {
        rise = 1
      } completion: {
        withAnimation(.easeOut(duration: 0.6)) { lit = 0 }
      }
    }
  }
}
