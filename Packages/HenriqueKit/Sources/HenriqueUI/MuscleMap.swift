import HenriqueCore
import SwiftUI

/// Mapa de carga por grupo muscular, numa janela de sete ou de vinte e oito dias.
/// A escala é relativa ao grupo mais treinado da janela escolhida: uma escala fixa
/// deixaria o mês inteiro no degrau de cima e a semana inteira no de baixo.
struct MuscleMap: View {
  @Environment(\.accent) private var accent
  @State private var period: MusclePeriod = .week
  @State private var picked: MuscleSlug?
  let load: [MuscleLoad]
  let today: CalendarDate

  var body: some View {
    VStack(alignment: .leading, spacing: Space.l) {
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
      HStack(spacing: Space.s) {
        figure(BodyChart.anterior, caption: "frente")
        figure(BodyChart.posterior, caption: "costas")
      }
      readout
      legend
      if let gap { GapNote(text: gap) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Space.xl)
    .paperCard()
    .animation(Motion.crossfade, value: period)
    .animation(Motion.tap, value: picked)
  }

  private var byGroup: [MuscleSlug: MuscleLoad] {
    Dictionary(uniqueKeysWithValues: load.map { ($0.group, $0) })
  }

  private var peak: Int {
    load.map { $0.sets(in: period) }.max() ?? 0
  }

  private func figure(_ polygons: [BodyPolygon], caption: String) -> some View {
    VStack(spacing: Space.s) {
      ZStack {
        BodyShape(polygons.filter { $0.group == nil }).fill(Color.ink.opacity(0.07))
        ForEach(MuscleSlug.allCases, id: \.self) { group in
          let shape = BodyShape(polygons.filter { $0.group == group })
          shape
            .fill(heat(for: group))
            .opacity(picked == nil || picked == group ? 1 : 0.45)
            .overlay {
              if picked == group { shape.stroke(Color.ink, lineWidth: 1) }
            }
            .contentShape(shape)
            .onTapGesture { picked = picked == group ? nil : group }
            .accessibilityLabel(group.label)
        }
      }
      .aspectRatio(BodyChart.frame.width / BodyChart.frame.height, contentMode: .fit)
      .frame(maxWidth: 150)
      .padding(.top, Space.s)
      Text(caption).font(.caption2).foregroundStyle(Color.mutedInk)
    }
    .frame(maxWidth: .infinity)
    .padding(.bottom, Space.s)
    .background(Color.surfaceMuted.opacity(0.5), in: .rect(cornerRadius: Radius.tile))
  }

  private func heat(for group: MuscleSlug) -> Color {
    let sets = byGroup[group]?.sets(in: period) ?? 0
    guard sets > 0, peak > 0 else { return Color.ink.opacity(0.13) }
    let level = max(1, min(4, Int(ceil(Double(sets) / Double(peak) * 4))))
    return switch level {
    case 1: accent.base.opacity(0.22)
    case 2: accent.base.opacity(0.46)
    case 3: accent.base.opacity(0.74)
    default: accent.deep
    }
  }

  private var readout: some View {
    VStack(alignment: .leading, spacing: 3) {
      if let picked, let item = byGroup[picked] {
        Text(picked.label).font(.subheadline.weight(.medium))
        Text("\(item.sets(in: period)) séries em \(period.span) · \(lastLabel(item))")
          .font(.caption).monospacedDigit().foregroundStyle(Color.mutedInk)
      } else {
        Text("toque num músculo").font(.subheadline.weight(.medium))
        Text("volume dos últimos \(period.span)")
          .font(.caption).foregroundStyle(Color.mutedInk)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, Space.m).padding(.vertical, Space.m)
    .background(Color.surfaceMuted, in: .rect(cornerRadius: Radius.tile))
  }

  /// A escala é relativa, então sem a régua quatro verdes não dizem o que separa um
  /// do outro. A legenda é a régua.
  private var legend: some View {
    HStack(spacing: 5) {
      Spacer()
      Text("menos").font(.caption2).foregroundStyle(Color.mutedInk)
      ForEach(0..<5) { level in
        RoundedRectangle(cornerRadius: 4)
          .fill(swatch(level))
          .frame(width: 13, height: 13)
      }
      Text("mais").font(.caption2).foregroundStyle(Color.mutedInk)
    }
    .accessibilityHidden(true)
  }

  private func swatch(_ level: Int) -> Color {
    switch level {
    case 0: Color.ink.opacity(0.13)
    case 1: accent.base.opacity(0.22)
    case 2: accent.base.opacity(0.46)
    case 3: accent.base.opacity(0.74)
    default: accent.deep
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
    HStack(alignment: .top, spacing: Space.s) {
      Image(systemName: "exclamationmark.circle")
        .font(.footnote.weight(.medium))
      Text(text).font(.footnote).fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(Color(red: 0.54, green: 0.18, blue: 0.18))
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, Space.m).padding(.vertical, Space.m)
    .background(Color(red: 0.99, green: 0.95, blue: 0.95), in: .rect(cornerRadius: Radius.tile))
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
