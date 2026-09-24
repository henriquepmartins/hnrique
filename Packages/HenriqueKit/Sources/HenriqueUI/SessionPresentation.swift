import SwiftUI

/// De onde a sessão cresce: o quadro do cartão tocado, na tela inteira, e a
/// cara dele. O chip de descanso não tem cartão, e aí ela só aparece.
enum SessionOrigin: Equatable {
  enum Fill: Equatable {
    case hero
    case day
  }

  case card(frame: CGRect, fill: Fill)
  case nowhere
}

/// O quadro de um cartão, guardado fora do estado da view. A rolagem muda o
/// quadro a cada quadro de tela, e num `@State` isso redesenharia o cartão.
@MainActor
final class SessionSourceFrame {
  var value = CGRect.zero
}

extension View {
  /// Mede onde este cartão está na tela inteira, para a sessão crescer dele.
  func sessionSource(_ frame: SessionSourceFrame) -> some View {
    onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame.value = $0 }
  }
}

/// A sessão de treino crescendo do cartão até tomar a tela, e voltando para
/// ele ao fechar. Um único valor de 0 a 1 dirige tudo, então máscara, véu e
/// degradê andam sempre na mesma mola: a máscara e o fundo do cartão crescem
/// do quadro do cartão até a tela, a camada ganha corpo no primeiro terço e o
/// fundo se dissolve na tela do meio para o fim, quando as peças começam a
/// aparecer. A tela da sessão já nasce no tamanho final; nada nela anda nem
/// cresce. Sem cartão de origem, e com movimento reduzido, só a opacidade muda.
struct SessionExpansion: View {
  @Environment(\.accent) private var accent
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var progress = 0.0
  let origin: SessionOrigin
  let onClosed: () -> Void

  var body: some View {
    GeometryReader { proxy in
      let card = reduceMotion ? nil : card(in: proxy)
      WorkoutSessionScreen(onClose: close)
        .modifier(SessionGrowth(
          progress: progress, card: card?.frame,
          screen: CGRect(origin: .zero, size: proxy.size)
        ) {
          if let card { fill(card.fill) }
        })
    }
    .ignoresSafeArea()
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isModal)
    .onAppear {
      withAnimation(reduceMotion ? Motion.plain : Motion.open) { progress = 1 }
    }
  }

  /// O cartão de origem no espaço desta camada, que cobre a tela inteira.
  private func card(in proxy: GeometryProxy) -> (frame: CGRect, fill: SessionOrigin.Fill)? {
    guard case .card(let frame, let fill) = origin else { return nil }
    let screen = proxy.frame(in: .global)
    return (frame.offsetBy(dx: -screen.minX, dy: -screen.minY), fill)
  }

  @ViewBuilder
  private func fill(_ fill: SessionOrigin.Fill) -> some View {
    switch fill {
    case .hero: HeroBackground(accent: accent, grain: false)
    case .day: accent.acid
    }
  }

  private func close() {
    withAnimation(reduceMotion ? Motion.plain : Motion.close) {
      progress = 0
    } completion: {
      onClosed()
    }
  }
}

/// O crescimento em função de `progress`. Sem cartão, só o véu.
private struct SessionGrowth<Fill: View>: ViewModifier, Animatable {
  var progress: Double
  let card: CGRect?
  let screen: CGRect
  @ViewBuilder let fill: Fill

  nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  func body(content: Content) -> some View {
    let rect = card.map { lerp($0, screen) } ?? screen
    let radius = card == nil ? 0 : (1 - progress) * Radius.card
    content
      // Por cima da tela, porque ela pinta o próprio fundo; as peças dela
      // ainda estão transparentes enquanto o degradê se dissolve.
      .overlay {
        fill
          .frame(width: rect.width, height: rect.height)
          .position(x: rect.midX, y: rect.midY)
          .opacity(1 - ramp(from: 0.3, to: 0.8))
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
      .opacity(ramp(from: 0, to: 0.3))
      .mask {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .frame(width: rect.width, height: rect.height)
          .position(x: rect.midX, y: rect.midY)
      }
  }

  private func ramp(from start: Double, to end: Double) -> Double {
    min(max((progress - start) / (end - start), 0), 1)
  }

  private func lerp(_ a: CGRect, _ b: CGRect) -> CGRect {
    let t = progress
    return CGRect(
      x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
      width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
  }
}
