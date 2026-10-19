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
      // A alça fica fora do recorte para não ser cortada ao meio nas bordas.
      .overlay {
        ColorThumb(fill: color.tone.top)
          .position(x: color.saturation * size.width, y: (1 - color.brightness) * size.height)
      }
      .contentShape(.rect)
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { drag in
            color.saturation = min(1, max(0, drag.location.x / size.width))
            color.brightness = min(1, max(0, 1 - drag.location.y / size.height))
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
            .position(x: color.hue * width, y: proxy.size.height / 2)
        }
        .contentShape(.rect)
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { drag in
              color.hue = min(1, max(0, drag.location.x / width))
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
  let fill: Color

  var body: some View {
    Circle()
      .fill(fill)
      .frame(width: 28, height: 28)
      .overlay(Circle().strokeBorder(.white, lineWidth: 3))
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
        WorkoutFolderCard(name: "peito e tríceps", tone: color.tone, hasDays: true)
          .frame(width: 240)
        WorkoutColorPicker(color: $color)
        Text(color.hex).font(.caption.monospaced())
      }
      .padding(24)
      .background(Color.canvas)
    }
  }
#endif
