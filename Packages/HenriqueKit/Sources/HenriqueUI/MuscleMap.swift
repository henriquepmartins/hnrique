import HenriqueCore
import SwiftUI

/// Mapa de carga por grupo muscular, numa janela de sete ou de vinte e oito dias.
/// A escala é relativa ao grupo mais treinado da janela escolhida: uma escala fixa
/// deixaria o mês inteiro no degrau de cima e a semana inteira no de baixo.
struct MuscleMap: View {
  @Environment(\.accent) private var accent
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .body) private var nameSize = 16.0
  @ScaledMetric(relativeTo: .footnote) private var valueSize = 13.5
  @ScaledMetric(relativeTo: .caption2) private var captionSize = 11.0
  @ScaledMetric(relativeTo: .caption2) private var legendSize = 11.5
  @State private var period: MusclePeriod = .week
  @State private var picked: MuscleSlug?
  let load: [MuscleLoad]
  let today: CalendarDate

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("músculos").font(.title3.weight(.medium)).tracking(-0.6)
        Spacer()
        Picker("período do mapa", selection: $period) {
          ForEach(MusclePeriod.allCases, id: \.self) { option in
            Text(option.label).tag(option).accessibilityIdentifier("musculos.\(option.rawValue)")
          }
        }
        .pickerStyle(.segmented)
        .frame(width: 136)
      }
      .padding(.bottom, Space.m)
      // As curvas ficam daqui para baixo, e não em volta do cabeçalho. Trocar o
      // período redesenha o corpo e o aviso, e o seletor que disparou a troca não
      // deve se mexer junto com o que ele mandou mudar.
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 0) {
          HStack(spacing: 10) {
            figure(BodyChart.anterior, caption: "frente")
            figure(BodyChart.posterior, caption: "costas")
          }
          readout
          legend
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.xl).padding(.top, Space.xl).padding(.bottom, Space.l)
        .paperCard(radius: Radius.tile)
        if let gap { GapNote(text: gap).padding(.top, 10) }
      }
      .animation(reduceMotion ? Motion.plain : Motion.crossfade, value: period)
      .animation(reduceMotion ? Motion.plain : Motion.tap, value: picked)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var byGroup: [MuscleSlug: MuscleLoad] {
    Dictionary(uniqueKeysWithValues: load.map { ($0.group, $0) })
  }

  private var peak: Int {
    load.map { $0.sets(in: period) }.max() ?? 0
  }

  private func figure(_ polygons: [BodyPolygon], caption: String) -> some View {
    VStack(spacing: 8) {
      ZStack {
        BodyShape(polygons.filter { $0.group == nil }).fill(Color.ink.opacity(0.14))
        ForEach(MuscleSlug.allCases, id: \.self) { group in
          let shape = BodyShape(polygons.filter { $0.group == group })
          shape
            .fill(heat(for: group))
            .opacity(picked == nil || picked == group ? 1 : 0.5)
            .overlay {
              if picked == group { shape.stroke(Color.ink, lineWidth: 1) }
            }
            // Sem o recorte de acessibilidade junto, cada músculo ocupa o
            // retângulo inteiro para o VoiceOver e o toque exploratório lê
            // sempre o último do empilhamento.
            .contentShape([.interaction, .accessibility], shape)
            .onTapGesture { picked = picked == group ? nil : group }
            .accessibilityElement()
            .accessibilityLabel(group.label)
            .accessibilityValue("\(byGroup[group]?.sets(in: period) ?? 0) séries em \(period.span)")
            .accessibilityAddTraits(picked == group ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { picked = picked == group ? nil : group }
        }
      }
      .aspectRatio(BodyChart.frame.width / BodyChart.frame.height, contentMode: .fit)
      .frame(maxWidth: 136)
      Text(caption).font(.system(size: captionSize, design: .monospaced)).tracking(captionSize * 0.01)
        .foregroundStyle(Color.mutedInk)
    }
    .frame(maxWidth: .infinity)
  }

  /// Lê a mesma tabela da legenda. Duas listas de cor separadas dão certo no dia
  /// em que são escritas e depois divergem, e aí a régua passa a mentir.
  private func heat(for group: MuscleSlug) -> Color {
    let sets = byGroup[group]?.sets(in: period) ?? 0
    guard sets > 0, peak > 0 else { return swatch(0) }
    return swatch(max(1, min(4, Int(ceil(Double(sets) / Double(peak) * 4)))))
  }

  private var readout: some View {
    VStack(spacing: 14) {
      Rectangle().fill(Color.ink.opacity(0.08)).frame(height: 1)
      // O espaçamento da pilha vale dos dois lados do Spacer, então com ele em 12
      // a folga mínima aqui seria 36 e o número quebraria em duas linhas antes da
      // hora. O Spacer sozinho carrega a folga.
      HStack(spacing: 0) {
        Text(picked.map { $0.label } ?? "toque num músculo")
          .font(.system(size: nameSize, weight: .medium))
        Spacer(minLength: 12)
        Text(readoutValue)
          .font(.system(size: valueSize)).monospacedDigit().foregroundStyle(Color.mutedInk)
          .multilineTextAlignment(.trailing)
      }
      .frame(minHeight: 44)
      .accessibilityElement(children: .combine)
    }
    .padding(.top, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var readoutValue: String {
    guard let picked, let item = byGroup[picked] else { return "volume dos últimos \(period.span)" }
    return "\(item.sets(in: period)) séries em \(period.span) · \(lastLabel(item))"
  }

  /// A escala é relativa, então sem a régua quatro verdes não dizem o que separa um
  /// do outro. A legenda é a régua.
  private var legend: some View {
    HStack(spacing: 5) {
      Spacer()
      Text("menos").font(.system(size: legendSize)).foregroundStyle(Color.mutedInk)
      ForEach(0..<5) { level in
        RoundedRectangle(cornerRadius: 4)
          .fill(swatch(level))
          .frame(width: 13, height: 13)
      }
      Text("mais").font(.system(size: legendSize)).foregroundStyle(Color.mutedInk)
    }
    .padding(.top, 12)
    .accessibilityHidden(true)
  }

  private func swatch(_ level: Int) -> Color {
    switch level {
    case 0: Color.ink.opacity(0.08)
    case 1: accent.base.opacity(0.20)
    case 2: accent.base.opacity(0.45)
    case 3: accent.base.opacity(0.80)
    default: accent.base
    }
  }

  /// O grupo mais esquecido do mês, quando o esquecimento já passou de dez dias. É o
  /// que o mapa serve para descobrir, e ele não deveria depender de o olho notar.
  private var gap: String? {
    let stale = load
      .filter { $0.setsMonth == 0 || ($0.lastTrainedDate.map { today.daysSince($0) } ?? 99) >= 10 }
      .max { a, b in days(a) < days(b) }
    guard let stale, days(stale) >= 10 else { return nil }
    guard let last = stale.lastTrainedDate else {
      return "\(stale.group.label) sem estímulo nos últimos 28 dias."
    }
    return "\(stale.group.label) sem estímulo há \(today.daysSince(last)) dias."
  }

  private func days(_ item: MuscleLoad) -> Int {
    guard let last = item.lastTrainedDate else { return 99 }
    return today.daysSince(last)
  }

  private func lastLabel(_ item: MuscleLoad) -> String {
    guard let last = item.lastTrainedDate else { return "sem estímulo no período" }
    let days = today.daysSince(last)
    return switch days {
    case ..<1: "treinado hoje"
    case 1: "treinado ontem"
    default: "último estímulo há \(days) dias"
    }
  }
}

/// O aviso de grupo parado. Vermelho suave, e não o verde do cartão: é a única linha
/// do mapa que pede uma mudança no plano.
struct GapNote: View {
  let text: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
      Image(systemName: "exclamationmark.circle")
        .font(.footnote.weight(.medium))
      Text(text).font(.footnote).fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(Color(red: 0.54, green: 0.18, blue: 0.18))
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, Space.l).padding(.vertical, 13)
    .background(Color(red: 0.99, green: 0.95, blue: 0.95), in: .rect(cornerRadius: 18))
    .accessibilityIdentifier("musculos.lacuna")
  }
}

/// Um grupo muscular como uma forma só. O desenho vem num quadro de 100 por 200 e
/// é reescalado para o retângulo que a tela deu.
struct BodyShape: Shape {
  let polygons: [BodyPolygon]

  init(_ polygons: [BodyPolygon]) {
    self.polygons = polygons
  }

  func path(in rect: CGRect) -> Path {
    let scale = min(rect.width / BodyChart.frame.width, rect.height / BodyChart.frame.height)
    let originX = rect.midX - BodyChart.frame.width * scale / 2
    let originY = rect.midY - BodyChart.frame.height * scale / 2
    var path = Path()
    for polygon in polygons where polygon.points.count > 2 {
      let points = polygon.points.map {
        CGPoint(x: originX + $0.x * scale, y: originY + $0.y * scale)
      }
      path.move(to: points[0])
      path.addLines(Array(points.dropFirst()))
      path.closeSubpath()
    }
    return path
  }
}
