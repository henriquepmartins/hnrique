import Testing

@testable import HenriqueUI

struct FocoFormatTests {
  @Test(arguments: [
    (1.0, "1 segundo"),
    (42.0, "42 segundos"),
    (60.0, "1 minuto"),
    (125.0, "2 minutos"),
    (3600.0, "1 hora"),
    (3660.0, "1 hora e 1 minuto"),
    (7500.0, "2 horas e 5 minutos"),
  ])
  func spokenAgreesInNumber(seconds: Double, expected: String) {
    #expect(FocoFormat.spoken(seconds) == expected)
  }

  @Test func countAgreesInNumber() {
    #expect(FocoFormat.count(1, "dia", "dias") == "1 dia")
    #expect(FocoFormat.count(0, "dia", "dias") == "0 dias")
    #expect(FocoFormat.count(12, "dia seguido", "dias seguidos") == "12 dias seguidos")
  }
}
