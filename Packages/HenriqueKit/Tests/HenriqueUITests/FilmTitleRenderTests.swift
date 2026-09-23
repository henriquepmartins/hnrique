import SwiftUI
import Testing

@testable import HenriqueUI

#if canImport(UIKit)
  import UIKit
#endif

/// O título do cartão passa por desfoque e máscara. Com a altura de linha
/// exata o quadro do texto é menor que a letra, e os dois cortavam o que
/// passava dele: a perna do "p" e o acento do "Á".
@MainActor
struct FilmTitleRenderTests {
  private let size: CGFloat = 76
  private let width: CGFloat = 342
  /// Folga em volta dos dois desenhos para o que sai do quadro aparecer.
  private let margin: CGFloat = 40

  @Test(arguments: ["Superiores", "Álgebra"])
  func drawsTheWholeGlyph(word: String) throws {
    let title = try ink(of: FilmTitle(text: word, size: size), named: "\(word)-titulo")
    // A mesma letra sem desfoque nem máscara: é até onde a tinta deveria ir.
    let plain = try ink(
      of: FilmTitle(text: word, size: size).lettering, named: "\(word)-referencia")
    #expect(title.size == plain.size)
    // O desfoque espalha meio ponto para cada lado, e a escala é 2.
    #expect(abs(title.top - plain.top) <= 3)
    #expect(abs(title.bottom - plain.bottom) <= 3)
  }

  private func ink(of view: some View, named name: String) throws
    -> (top: Int, bottom: Int, size: CGSize)
  {
    let renderer = ImageRenderer(
      content: view.foregroundStyle(.black)
        .frame(width: width, alignment: .leading)
        .padding(margin))
    renderer.scale = 2
    let image = try #require(renderer.cgImage)
    save(image, name: name)
    let rows = inkedRows(image)
    return (
      try #require(rows.first), try #require(rows.last), CGSize(width: image.width, height: image.height)
    )
  }

  private func inkedRows(_ image: CGImage) -> [Int] {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    pixels.withUnsafeMutableBytes { buffer in
      let context = CGContext(
        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return (0..<height).filter { row in
      (0..<width).contains { column in pixels[(row * width + column) * 4 + 3] > 40 }
    }
  }

  /// `FILM_TITLE_OUT` guarda os PNGs para olhar de fora do simulador.
  private func save(_ image: CGImage, name: String) {
    guard let folder = ProcessInfo.processInfo.environment["FILM_TITLE_OUT"] else { return }
    #if canImport(UIKit)
      let url = URL(filePath: folder).appending(path: "\(name).png")
      try? UIImage(cgImage: image).pngData()?.write(to: url)
    #endif
  }
}
