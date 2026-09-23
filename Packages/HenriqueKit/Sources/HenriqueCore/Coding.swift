import Foundation

extension JSONDecoder {
  /// O decodificador que o app inteiro usa. Fica em um lugar só para o teste de
  /// contrato exercitar exatamente o mesmo caminho que a tela.
  public static func henrique() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let text = try decoder.singleValueContainer().decode(String.self)
      guard let date = parseTimestamp(text) else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "instante inválido: \(text)"))
      }
      return date
    }
    return decoder
  }
}

extension JSONEncoder {
  /// O codificador que o app inteiro usa. O instante sai com milissegundos
  /// porque `review.grade` compara o `expectedDueAt` enviado com o `dueAt` do
  /// banco nessa precisão; truncar o segundo faria o servidor ver conflito onde
  /// não há.
  public static func henrique() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(withFraction.string(from: date))
    }
    return encoder
  }
}

/// O Postgres devolve o instante com milissegundos e o Foundation só aceita os
/// dois formatos se cada um tiver seu parser.
public func parseTimestamp(_ text: String) -> Date? {
  withFraction.date(from: text) ?? plain.date(from: text)
}

// Criar os dois formatadores a cada instante custava 0,6 ms por data, e o
// histórico de foco decodifica duas por sessão. Compartilhados, 5 vezes menos.
// O `ISO8601DateFormatter` é seguro entre threads. O `ISO8601FormatStyle` seria
// mais rápido, mas arredonda o milissegundo diferente, e o `expectedDueAt` da
// revisão precisa voltar ao servidor igual ao que veio.
nonisolated(unsafe) private let withFraction: ISO8601DateFormatter = {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return formatter
}()

nonisolated(unsafe) private let plain: ISO8601DateFormatter = {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime]
  return formatter
}()
