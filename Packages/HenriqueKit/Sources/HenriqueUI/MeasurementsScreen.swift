import Charts
import HenriqueCore
import SwiftUI

/// Uma medida do corpo. O editor pede as seis; a tela mostra cada uma que já
/// teve valor no histórico, com a variação desde o registro anterior.
enum BodyMetric: String, CaseIterable, Identifiable {
  case weight, bodyFat, leanMass, waist, chest, arm, thigh

  var id: Self { self }

  var title: String {
    switch self {
    case .weight: "peso"
    case .bodyFat: "gordura"
    case .leanMass: "massa magra"
    case .waist: "cintura"
    case .chest: "peito"
    case .arm: "braço"
    case .thigh: "coxa"
    }
  }

  var unit: String {
    switch self {
    case .weight, .leanMass: "kg"
    case .bodyFat: "%"
    case .waist, .chest, .arm, .thigh: "cm"
    }
  }

  var symbol: String {
    switch self {
    case .weight: "scalemass"
    case .bodyFat: "figure"
    case .leanMass: "figure.strengthtraining.traditional"
    case .waist: "ruler"
    case .chest: "ruler"
    case .arm: "figure.arms.open"
    case .thigh: "figure.walk"
    }
  }

  func value(in measurement: BodyMeasurement) -> Double? {
    switch self {
    case .weight: measurement.weightKg
    case .bodyFat: measurement.bodyFatPercent
    case .leanMass: measurement.bodyFatPercent.map { measurement.weightKg * (1 - $0 / 100) }
    case .waist: measurement.waistCm
    case .chest: measurement.chestCm
    case .arm: measurement.armCm
    case .thigh: measurement.thighCm
    }
  }

  /// Os valores da medida em ordem de data, só os dias que a têm.
  func series(_ measurements: [BodyMeasurement]) -> [(date: CalendarDate, value: Double)] {
    measurements.sorted { $0.date < $1.date }.compactMap { item in
      value(in: item).map { (date: item.date, value: $0) }
    }
  }

  func label(_ value: Double) -> String {
    let number = value.formatted(.number.precision(.fractionLength(0...1)))
    return unit == "%" ? "\(number)%" : "\(number) \(unit)"
  }
}

struct MeasurementsScreen: View {
  @Environment(AcademiaStore.self) private var store
  @State private var isAdding = false
  @State private var editing: BodyMeasurement?
  @State private var charted: BodyMetric = .weight
  @Environment(\.dynamicTypeSize) private var textSize

  private var measurements: [BodyMeasurement] {
    (store.dashboard?.measurements ?? []).sorted { $0.date > $1.date }
  }

  /// As medidas com pelo menos um valor no histórico. O peso é obrigatório e
  /// sempre entra.
  private var recorded: [BodyMetric] {
    BodyMetric.allCases.filter { metric in measurements.contains { metric.value(in: $0) != nil } }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        PageHeading(title: "medidas")
        Button("nova medida", systemImage: "plus") { isAdding = true }
          .buttonStyle(.glassProminent).controlSize(.large)
        if measurements.isEmpty {
          ContentUnavailableView("sem medidas", systemImage: "scalemass")
        } else {
          content
        }
      }.padding(16).padding(.bottom, 32)
    }
    // Sem título na barra, o voltar flutuava por cima do número rolado.
    .scrollEdgeEffectStyle(.soft, for: .top)
    .refreshable { await store.load() }
    .sheet(isPresented: $isAdding) { MeasurementEditor(previous: measurements.first) }
    .sheet(item: $editing) { MeasurementEditor(editing: $0) }
  }

  private var chartHeading: some View {
    SectionHeading(title: charted.title, systemImage: charted.symbol, font: .title2.weight(.medium), tracking: 0)
  }

  @ViewBuilder private var chartPicker: some View {
    if recorded.count > 1 {
      Picker("medida do gráfico", selection: $charted) {
        ForEach(recorded) { Text($0.title).tag($0) }
      }
      .pickerStyle(.menu)
    }
  }

  @ViewBuilder private var content: some View {
    let columns = textSize.isAccessibilitySize ? 1 : 2
    let recorded = recorded
    LazyVGrid(
      columns: Array(repeating: GridItem(.flexible(), spacing: Space.m), count: columns),
      spacing: Space.m
    ) {
      ForEach(Array(recorded.enumerated()), id: \.element) { index, metric in
        let series = metric.series(measurements)
        MeasurementMetric(
          metric: metric, value: series.last?.value,
          previous: series.count > 1 ? series[series.count - 2].value : nil)
          .staggeredEntrance(index: index, columns: columns, isReady: true)
      }
    }
    VStack(alignment: .leading, spacing: 16) {
      // Os dois lado a lado espremiam "peso" em "pes/o" no texto grande; sem
      // espaço, o seletor desce para baixo do título.
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline) {
          chartHeading.fixedSize()
          Spacer(minLength: Space.s)
          chartPicker.fixedSize()
        }
        VStack(alignment: .leading, spacing: Space.xs) {
          chartHeading
          chartPicker
        }
      }
      MeasurementChart(metric: charted, points: charted.series(measurements)).frame(height: 220)
    }.padding(Space.xl).paperCard()
      .staggeredEntrance(index: 2, isReady: true)
    VStack(alignment: .leading, spacing: 16) {
      SectionHeading(title: "histórico", systemImage: "clock.arrow.circlepath", font: .title2.weight(.medium), tracking: 0)
      ForEach(Array(measurements.enumerated()), id: \.element.id) { index, measurement in
        if index > 0 { Divider() }
        // O servidor guarda uma medida por dia, então salvar no mesmo dia
        // corrige a medida. Apagar ainda não tem rota.
        Button { editing = measurement } label: { MeasurementRow(measurement: measurement) }
          .buttonStyle(StudyPressStyle())
          .foregroundStyle(Color.ink)
          .contextMenu {
            Button("editar", systemImage: "square.and.pencil") { editing = measurement }
          }
      }
    }.padding(Space.xl).paperCard()
      .staggeredEntrance(index: 3, isReady: true)
  }
}

/// A porta das medidas dentro de progresso. Medidas deixou de ser aba, então o
/// resumo mostra o número mais recente e o toque abre a tela inteira.
struct MeasurementsLink: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accent) private var accent
  @Namespace private var cardSource
  let latest: BodyMeasurement?

  var body: some View {
    NavigationLink {
      MeasurementsScreen()
        .background(Color.canvas.ignoresSafeArea())
        .toolbarTitleDisplayMode(.inline)
        // O cartão cresce e vira a tela, o mesmo gesto do botão de começar
        // treino. Empurrar de lado fazia um resumo e o detalhe dele parecerem
        // duas telas sem parentesco.
        .navigationTransition(.zoom(sourceID: "medidas", in: cardSource))
    } label: {
      HStack(alignment: .top, spacing: 16) {
        VStack(alignment: .leading, spacing: 10) {
          Text("medidas").font(.caption).foregroundStyle(accent.base)
          if let latest {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
              value(weightLabel(latest.weightKg), caption: "peso")
              if let fat = latest.bodyFatPercent {
                value("\(fat.formatted(.number.precision(.fractionLength(0...1))))%",
                  caption: "gordura")
              }
            }
          } else {
            Text("–").font(.system(size: 30, weight: .medium)).foregroundStyle(Color.mutedInk)
              .accessibilityLabel("sem medidas")
          }
          if let latest {
            Text(Formatting.shortDate(latest.date))
              .font(.subheadline).foregroundStyle(Color.mutedInk)
          }
        }
        Spacer(minLength: 0)
        Image(systemName: "arrow.right")
          .font(.headline)
          .foregroundStyle(accent.base)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Space.xl)
      .paperCard()
      .contentShape(.rect(cornerRadius: Radius.card))
    }
    .buttonStyle(StudyPressStyle())
    .matchedTransitionSource(id: "medidas", in: cardSource)
    .foregroundStyle(Color.ink)
  }

  private func value(_ text: String, caption: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(text).font(.system(size: 30, weight: .medium)).monospacedDigit()
        .contentTransition(.numericText())
        .animation(reduceMotion ? nil : Motion.crossfade, value: text)
      Text(caption).font(.caption).foregroundStyle(Color.mutedInk)
    }
  }
}

struct MeasurementMetric: View {
  @Environment(\.accent) private var accent
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let metric: BodyMetric
  let value: Double?
  /// O registro anterior da mesma medida, para a variação.
  let previous: Double?

  private var delta: Double? {
    guard let value, let previous, abs(value - previous) >= 0.05 else { return nil }
    return value - previous
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Image(systemName: metric.symbol).foregroundStyle(accent.base).frame(height: 24)
      Text(metric.title).font(.caption).foregroundStyle(Color.mutedInk)
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(value.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "–")
          .font(.title2.weight(.medium)).monospacedDigit()
          .foregroundStyle(value == nil ? Color.mutedInk : Color.ink)
          .contentTransition(.numericText(value: value ?? 0))
          .animation(Motion.resolve(Motion.roll, reduceMotion), value: value)
        if value != nil { Text(metric.unit).font(.caption).foregroundStyle(Color.mutedInk) }
      }
      // Sem verde nem vermelho: descer é bom na cintura e ruim no braço.
      if let delta {
        Label {
          Text(delta.formatted(.number.sign(strategy: .always()).precision(.fractionLength(0...1))))
        } icon: {
          Image(systemName: delta < 0 ? "arrow.down.right" : "arrow.up.right")
        }
        .font(.caption.monospacedDigit()).foregroundStyle(Color.mutedInk)
      }
    }.frame(maxWidth: .infinity, minHeight: 110, alignment: .leading).padding(Space.l).paperCard(radius: Radius.tile)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(metric.title)
      .accessibilityValue(spokenValue)
  }

  private var spokenValue: String {
    guard let value else { return "sem registro" }
    let now = metric.label(value)
    guard let delta else { return now }
    let change = metric.label(abs(delta))
    return "\(now), \(delta < 0 ? "desceu" : "subiu") \(change) desde a anterior"
  }
}

struct MeasurementChart: View {
  @Environment(\.accent) private var accent
  @State private var selectedDate: Date?
  let metric: BodyMetric
  let points: [(date: CalendarDate, value: Double)]

  /// O eixo começa uma unidade abaixo do menor valor, e a área sobe dali. Com a
  /// área partindo do zero, ela descia por baixo do eixo.
  private var domain: ClosedRange<Double> {
    let values = points.map(\.value)
    let lower = ((values.min() ?? 0) - 1).rounded(.down)
    let upper = ((values.max() ?? 0) + 1).rounded(.up)
    return lower...upper
  }

  private var selected: (date: CalendarDate, value: Double)? {
    guard let selectedDate else { return nil }
    return points.min {
      abs($0.date.date().timeIntervalSince(selectedDate)) < abs($1.date.date().timeIntervalSince(selectedDate))
    }
  }

  var body: some View {
    let domain = domain
    Chart {
      ForEach(points, id: \.date) { point in
        AreaMark(
          x: .value("dia", point.date.date()),
          yStart: .value("base", domain.lowerBound), yEnd: .value(metric.title, point.value)
        )
        .interpolationMethod(.monotone)
        .foregroundStyle(accent.pale.opacity(0.4))

        LineMark(x: .value("dia", point.date.date()), y: .value(metric.title, point.value))
          .interpolationMethod(.monotone)
          .foregroundStyle(accent.base)

        // Com um registro só, a linha não tem o que ligar; o ponto mostra que ele existe.
        PointMark(x: .value("dia", point.date.date()), y: .value(metric.title, point.value))
          .symbolSize(30)
          .foregroundStyle(accent.base)
      }
      if let selected {
        RuleMark(x: .value("dia", selected.date.date()))
          .foregroundStyle(Color.ink.opacity(0.2))
          .annotation(
            position: .top, spacing: 4,
            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
          ) {
            ChartReadout(value: metric.label(selected.value), date: selected.date)
          }
      }
    }
    .chartYScale(domain: domain)
    .chartYAxisLabel(metric.unit)
    .chartXSelection(value: $selectedDate)
    .sensoryFeedback(.selection, trigger: selected?.date)
    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
  }
}

struct MeasurementRow: View {
  let measurement: BodyMeasurement

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(Formatting.shortDate(measurement.date))
        .font(.callout)
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
        Text(weightLabel(measurement.weightKg))
          .font(.callout.weight(.medium))
        if !extras.isEmpty {
          Text(extras).font(.footnote).foregroundStyle(Color.mutedInk)
            .multilineTextAlignment(.trailing)
        }
      }
      .monospacedDigit()
    }
    .frame(minHeight: 44)
    .contentShape(.rect)
  }

  private var extras: String {
    [BodyMetric.bodyFat, .waist, .chest, .arm, .thigh].compactMap { metric in
      metric.value(in: measurement).map {
        metric == .bodyFat ? metric.label($0) : "\(metric.title) \(metric.label($0))"
      }
    }.joined(separator: " · ")
  }
}

struct MeasurementEditor: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var weightKg: Double?
  @State private var date = Date.now
  @State private var isSaving = false
  @State private var saves = 0
  @State private var bodyFatPercent: Double?
  @State private var waistCm: Double?
  @State private var chestCm: Double?
  @State private var armCm: Double?
  @State private var thighCm: Double?

  /// O dia da medida que está sendo corrigida. Nulo numa medida nova.
  private let editingDate: CalendarDate?

  /// Começar da última medida poupa digitação: o peso muda pouco entre pesagens
  /// e as circunferências costumam ficar iguais por semanas.
  init(previous: BodyMeasurement?) {
    editingDate = nil
    weightKg = previous?.weightKg
    bodyFatPercent = previous?.bodyFatPercent
    waistCm = previous?.waistCm
    chestCm = previous?.chestCm
    armCm = previous?.armCm
    thighCm = previous?.thighCm
  }

  /// Corrige uma medida. O servidor guarda uma por dia, então salvar na mesma
  /// data substitui a anterior.
  init(editing measurement: BodyMeasurement) {
    editingDate = measurement.date
    _date = State(initialValue: measurement.date.date())
    weightKg = measurement.weightKg
    bodyFatPercent = measurement.bodyFatPercent
    waistCm = measurement.waistCm
    chestCm = measurement.chestCm
    armCm = measurement.armCm
    thighCm = measurement.thighCm
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          OptionalField(label: "peso", unit: "kg", range: Limits.bodyWeightKg, value: $weightKg)
          if editingDate == nil {
            DatePicker(selection: $date, in: ...Date.now, displayedComponents: .date) {
              Label("data", systemImage: "calendar")
            }
          }
        }
        Section {
          OptionalField(label: "gordura corporal", unit: "%", range: Limits.bodyFatPercent, value: $bodyFatPercent)
          OptionalField(label: "cintura", unit: "cm", range: Limits.waistCm, value: $waistCm)
          OptionalField(label: "peito", unit: "cm", range: Limits.chestCm, value: $chestCm)
          OptionalField(label: "braço", unit: "cm", range: Limits.armCm, value: $armCm)
          OptionalField(label: "coxa", unit: "cm", range: Limits.thighCm, value: $thighCm)
        }
      }
      .interactiveDismissDisabled(isSaving)
      .sensoryFeedback(.success, trigger: saves)
      .navigationTitle(editingDate == nil ? "nova medida" : "editar medida")
      .toolbarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("cancelar", systemImage: "xmark", role: .cancel) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          if isSaving {
            ProgressView()
          } else {
            Button("salvar", systemImage: "checkmark", role: .confirm) { save() }
              .disabled(!allWithinLimits)
          }
        }
      }
      .keyboardDone()
    }
  }

  /// O peso é obrigatório; os outros só contam quando preenchidos.
  private var allWithinLimits: Bool {
    guard let weightKg, Limits.bodyWeightKg.contains(weightKg) else { return false }
    let optionals: [(Double?, ClosedRange<Double>)] = [
      (bodyFatPercent, Limits.bodyFatPercent), (waistCm, Limits.waistCm), (chestCm, Limits.chestCm),
      (armCm, Limits.armCm), (thighCm, Limits.thighCm),
    ]
    return optionals.allSatisfy { value, range in value.map(range.contains) ?? true }
  }

  private func save() {
    guard allWithinLimits, let weightKg else { return }
    let input = AddMeasurementInput(
      date: editingDate ?? CalendarDate(date), weightKg: weightKg, bodyFatPercent: bodyFatPercent, waistCm: waistCm,
      chestCm: chestCm, armCm: armCm, thighCm: thighCm)
    isSaving = true
    Task {
      let saved = await store.addMeasurement(input)
      isSaving = false
      if saved {
        saves += 1
        dismiss()
      }
    }
  }
}

/// Um campo numérico com rótulo à esquerda e unidade à direita. Vazio, ele
/// mostra o traço; tocar em qualquer ponto da linha abre o teclado.
struct OptionalField: View {
  let label: String
  let unit: String
  let range: ClosedRange<Double>
  @Binding var value: Double?
  @FocusState private var focused: Bool?

  private var outOfRange: Bool { value.map { !range.contains($0) } ?? false }

  var body: some View {
    VStack(alignment: .trailing, spacing: 2) {
      HStack {
        Text(label)
        Spacer()
        // Lido a cada tecla: com `value:format:` o número só chegava ao valor
        // quando o campo perdia o foco, e salvar com o teclado aberto gravava
        // a medida da semana passada.
        TypedNumberField(
          placeholder: "–", value: $value, focus: $focused, field: true,
          parse: parseDecimal, format: formatPrepWeight
        )
          .submitLabel(.done)
          .decimalInput().multilineTextAlignment(.trailing)
          .foregroundStyle(outOfRange ? .red : .primary)
          .fixedSize()
          .frame(minWidth: 64, alignment: .trailing)
          .accessibilityLabel("\(label) em \(unit)")
        Text(unit).font(.caption).foregroundStyle(Color.mutedInk)
      }
      .contentShape(.rect)
      .onTapGesture { focused = true }
      if outOfRange { RangeHint(range: range, unit: unit) }
    }
  }
}

/// A faixa que o servidor aceita, mostrada só quando o valor saiu dela.
struct RangeHint: View {
  let range: ClosedRange<Double>
  let unit: String

  var body: some View {
    Text("entre \(bound(range.lowerBound)) e \(bound(range.upperBound)) \(unit)")
      .font(.caption2).foregroundStyle(Color.danger)
      .frame(maxWidth: .infinity, alignment: .trailing)
      .accessibilityAddTraits(.updatesFrequently)
  }

  private func bound(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)))
  }
}
