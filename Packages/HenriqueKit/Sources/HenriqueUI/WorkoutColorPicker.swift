import SwiftUI

/// Quadrado de saturação e brilho mais a régua de matiz, na própria tela. O
/// `ColorPicker` do sistema abre uma folha por cima, que não é o desenho.
struct WorkoutColorPicker: View {
  @Binding var color: WorkoutColor

  var body: some View {
    VStack(spacing: 16) {
      SaturationBrightnessPad(color: $color)
      HueBar(color: $color)
    }
  }
}

private struct SaturationBrightnessPad: View {
  @Binding var color: WorkoutColor

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      ZStack {
        LinearGradient(
          colors: [.white, Color(hue: color.hue, saturation: 1, brightness: 1)],
          startPoint: .leading, endPoint: .trailing)
        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
      }
      .clipShape(.rect(cornerRadius: 16))
      // A alça anda meio diâmetro para dentro de cada borda, então nas pontas
      // ela fica inteira dentro do quadro em vez de metade para fora.
      .overlay {
        ColorThumb(fill: color.tone.top)
          .position(
            x: ColorThumb.inset(color.saturation, in: size.width),
            y: ColorThumb.inset(1 - color.brightness, in: size.height))
      }
      .contentShape(.rect)
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { drag in
            color.saturation = ColorThumb.fraction(drag.location.x, in: size.width)
            color.brightness = 1 - ColorThumb.fraction(drag.location.y, in: size.height)
          })
    }
    .frame(height: 260)
    // Vibrar a cada ponto do arraste vira zumbido. O gatilho é o valor em
    // vinte degraus, então só muda quando o dedo andou de verdade.
    .sensoryFeedback(.selection, trigger: Int(color.saturation * 20) * 100 + Int(color.brightness * 20))
    .accessibilityElement()
    .accessibilityLabel("saturação e brilho")
    .accessibilityValue("saturação \(Int(color.saturation * 100)) por cento, brilho \(Int(color.brightness * 100)) por cento")
    // Sem arrastar, o VoiceOver muda o brilho deslizando para cima ou para
    // baixo e a saturação pelas ações.
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment: color.brightness = min(1, color.brightness + 0.05)
      case .decrement: color.brightness = max(0, color.brightness - 0.05)
      @unknown default: break
      }
    }
    .accessibilityAction(named: "mais saturação") { color.saturation = min(1, color.saturation + 0.05) }
    .accessibilityAction(named: "menos saturação") { color.saturation = max(0, color.saturation - 0.05) }
  }
}

private struct HueBar: View {
  @Binding var color: WorkoutColor

  private static let wheel: [Color] = (0...6).map { Color(hue: Double($0) / 6, saturation: 1, brightness: 1) }

  var body: some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      LinearGradient(colors: Self.wheel, startPoint: .leading, endPoint: .trailing)
        .clipShape(.capsule)
        .overlay {
          ColorThumb(fill: Color(hue: color.hue, saturation: 1, brightness: 1))
            .position(x: ColorThumb.inset(color.hue, in: width), y: proxy.size.height / 2)
        }
        .contentShape(.rect)
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { drag in
              color.hue = ColorThumb.fraction(drag.location.x, in: width)
            })
    }
    .frame(height: 44)
    .sensoryFeedback(.selection, trigger: Int(color.hue * 36))
    .accessibilityElement()
    .accessibilityLabel("matiz")
    .accessibilityValue("\(Int(color.hue * 360)) graus")
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment: color.hue = min(1, color.hue + 1.0 / 36)
      case .decrement: color.hue = max(0, color.hue - 1.0 / 36)
      @unknown default: break
      }
    }
  }
}

private struct ColorThumb: View {
  static let size: CGFloat = 28
  let fill: Color

  /// Onde fica o centro da alça para a fração `value` de um trilho de
  /// `length`, com meio diâmetro de folga em cada ponta.
  static func inset(_ value: Double, in length: CGFloat) -> CGFloat {
    size / 2 + value * max(0, length - size)
  }

  /// O inverso de `inset`: a fração para o ponto onde o dedo está.
  static func fraction(_ position: CGFloat, in length: CGFloat) -> Double {
    guard length > size else { return 0 }
    return min(1, max(0, (position - size / 2) / (length - size)))
  }

  /// O anel escuro de fora separa a alça de um fundo branco ou da mesma cor.
  var body: some View {
    Circle()
      .fill(fill)
      .frame(width: Self.size, height: Self.size)
      .overlay(Circle().strokeBorder(.white, lineWidth: 3))
      .overlay(Circle().strokeBorder(.black.opacity(0.2), lineWidth: 1).padding(-1))
      .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
      .allowsHitTesting(false)
  }
}

#if DEBUG
  #Preview("Seletor de cor") {
    WorkoutColorPickerPreview()
  }

  private struct WorkoutColorPickerPreview: View {
    @State private var color = WorkoutColor(hex: WorkoutTone.all[0].hex)!

    var body: some View {
      VStack(spacing: 24) {
        WorkoutFolderCard(name: "peito e tríceps", tone: color.tone, weekdays: [1, 4])
          .frame(width: 240)
        WorkoutColorPicker(color: $color)
        Text(color.hex).font(.caption.monospaced())
      }
      .padding(24)
      .background(Color.canvas)
    }
  }
#endif
