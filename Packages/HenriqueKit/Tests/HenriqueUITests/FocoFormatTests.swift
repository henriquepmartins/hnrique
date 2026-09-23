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
}
