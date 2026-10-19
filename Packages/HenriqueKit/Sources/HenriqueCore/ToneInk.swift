import Foundation

/// Uma cor em sRGB, de 0 a 1 por canal. Mora no núcleo porque o app e a Live
/// Activity precisam da mesma conta de contraste sobre a cor do treino.
public struct ToneRGB: Hashable, Sendable {
  public var red: Double
  public var green: Double
  public var blue: Double

  public init(red: Double, green: Double, blue: Double) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  /// `#rrggbb` ou `rrggbb`. Nulo para qualquer outra coisa.
  public init?(hex: String) {
    var digits = Substring(hex)
    if digits.hasPrefix("#") { digits = digits.dropFirst() }
    guard digits.count == 6, let rgb = UInt32(digits, radix: 16) else { return nil }
    self.init(
      red: Double((rgb >> 16) & 0xff) / 255, green: Double((rgb >> 8) & 0xff) / 255,
      blue: Double(rgb & 0xff) / 255)
  }

  public init(hue: Double, saturation: Double, brightness: Double) {
    let h = (hue - hue.rounded(.down)) * 6
    let c = brightness * saturation
    let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
    let (r, g, b): (Double, Double, Double) =
      switch Int(h) {
      case 0: (c, x, 0)
      case 1: (x, c, 0)
      case 2: (0, c, x)
      case 3: (0, x, c)
      case 4: (x, 0, c)
      default: (c, 0, x)
      }
    let m = brightness - c
    self.init(red: r + m, green: g + m, blue: b + m)
  }

  public static let white = ToneRGB(red: 1, green: 1, blue: 1)

  public var hsb: (hue: Double, saturation: Double, brightness: Double) {
    let high = max(red, green, blue)
    let delta = high - min(red, green, blue)
    var hue: Double =
      if delta == 0 { 0 }
      else if high == red { ((green - blue) / delta).truncatingRemainder(dividingBy: 6) / 6 }
      else if high == green { ((blue - red) / delta + 2) / 6 }
      else { ((red - green) / delta + 4) / 6 }
    if hue < 0 { hue += 1 }
    return (hue, high == 0 ? 0 : delta / high, high)
  }
}

public enum ToneContrast {
  /// A tinta que vai por cima da cor: escura do mesmo matiz ou branca, a que
  /// tiver mais contraste. O contraste é o do APCA, que pesa como o olho lê cor
  /// saturada; pela conta do WCAG 2 o vermelho ficava com a tinta escura, que
  /// some nele.
  public static func ink(on fill: ToneRGB) -> ToneRGB {
    let (hue, saturation, brightness) = fill.hsb
    let dark = ToneRGB(hue: hue, saturation: min(1, saturation * 1.1), brightness: brightness * 0.26)
    return abs(apca(text: dark, on: fill)) > abs(apca(text: .white, on: fill)) ? dark : .white
  }

  /// A mesma cor, escurecida no próprio matiz até ter `minimum` de contraste
  /// WCAG sobre `background`. Cor que já passa volta igual.
  public static func legible(_ color: ToneRGB, on background: ToneRGB, minimum: Double) -> ToneRGB {
    let (hue, saturation, brightness) = color.hsb
    var candidate = color
    var step = brightness
    while wcag(candidate, background) < minimum, step > 0 {
      step = max(0, step - 0.02)
      candidate = ToneRGB(hue: hue, saturation: saturation, brightness: step)
    }
    return candidate
  }

  /// A razão do WCAG 2, de 1 a 21.
  public static func wcag(_ a: ToneRGB, _ b: ToneRGB) -> Double {
    func channel(_ value: Double) -> Double {
      value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    func luminance(_ color: ToneRGB) -> Double {
      0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
    }
    let (high, low) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
    return (high + 0.05) / (low + 0.05)
  }

  /// O Lc do APCA 0.0.98G: positivo para texto escuro em fundo claro, negativo ao contrário.
  public static func apca(text: ToneRGB, on background: ToneRGB) -> Double {
    func luminance(_ color: ToneRGB) -> Double {
      let y = 0.2126729 * pow(color.red, 2.4) + 0.7151522 * pow(color.green, 2.4)
        + 0.0721750 * pow(color.blue, 2.4)
      return y > 0.022 ? y : y + pow(0.022 - y, 1.414)
    }
    let text = luminance(text)
    let background = luminance(background)
    if background > text {
      let contrast = (pow(background, 0.56) - pow(text, 0.57)) * 1.14
      return contrast < 0.1 ? 0 : (contrast - 0.027) * 100
    }
    let contrast = (pow(background, 0.65) - pow(text, 0.62)) * 1.14
    return contrast > -0.1 ? 0 : (contrast + 0.027) * 100
  }
}
