import Testing

@testable import HenriqueCore

@Suite("O desenho do corpo")
struct BodyChartTests {
  @Test("todo ponto de cada vista cabe no quadro dela", arguments: [BodyChart.anterior, BodyChart.posterior])
  func pointsFitTheFrame(figure: BodyFigure) {
    let outside = figure.polygons.flatMap(\.points).filter {
      !(0...figure.frame.width).contains($0.x) || !(0...figure.frame.height).contains($0.y)
    }
    #expect(outside.isEmpty)
  }
}
