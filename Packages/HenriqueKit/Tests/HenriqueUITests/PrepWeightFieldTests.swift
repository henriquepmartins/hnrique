import Testing

@testable import HenriqueUI

struct PrepWeightFieldTests {
  @Test("o texto do campo vira carga a cada tecla, com vírgula ou ponto")
  func parses() {
    #expect(parsePrepWeight("12") == 12)
    #expect(parsePrepWeight("12,5") == 12.5)
    #expect(parsePrepWeight("12.25") == 12.25)
    #expect(parsePrepWeight("") == nil)
    #expect(parsePrepWeight("abc") == nil)
    #expect(parsePrepWeight("1500") == 1000)
  }

  @Test("a carga mostrada volta igual ao ler de novo")
  func roundTrips() {
    for value in [0, 12, 12.5, 12.25, 1000] {
      #expect(parsePrepWeight(formatPrepWeight(value)) == value)
    }
    #expect(formatPrepWeight(1000) == "1000")
    #expect(formatPrepWeight(12.25) == "12,25")
  }
}
