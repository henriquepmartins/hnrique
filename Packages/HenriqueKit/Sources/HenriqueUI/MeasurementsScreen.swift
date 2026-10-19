import Charts
import HenriqueCore
import SwiftUI

struct MeasurementsScreen: View {
  @Environment(AcademiaStore.self) private var store
  @State private var isAdding = false
  @State private var editing: BodyMeasurement?
  @Environment(\.dynamicTypeSize) private var textSize

  private var measurements: [BodyMeasurement] {
    (store.dashboard?.measurements ?? []).sorted { $0.date > $1.date }
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
    .refreshable { await store.load() }
    .sheet(isPresented: $isAdding) { MeasurementEditor(previous: measurements.first) }
    .sheet(item: $editing) { MeasurementEditor(editing: $0) }
  }

  @ViewBuilder private var content: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.m), count: textSize.isAccessibilitySize ? 1 : 2), spacing: Space.m) {
      MeasurementMetric(title: "peso", value: measurements.first?.weightKg, unit: "kg", symbol: "scalemass")
        .staggeredEntrance(index: 0, columns: textSize.isAccessibilitySize ? 1 : 2, isReady: true)
      MeasurementMetric(title: "gordura", value: measurements.first?.bodyFatPercent, unit: "%", symbol: "figure")
        .staggeredEntrance(index: 1, columns: textSize.isAccessibilitySize ? 1 : 2, isReady: true)
      MeasurementMetric(title: "cintura", value: measurements.first?.waistCm, unit: "cm", symbol: "ruler")
        .staggeredEntrance(index: 2, columns: textSize.isAccessibilitySize ? 1 : 2, isReady: true)
      MeasurementMetric(title: "massa magra", value: leanMass, unit: "kg", symbol: "figure.strengthtraining.traditional")
        .staggeredEntrance(index: 3, columns: textSize.isAccessibilitySize ? 1 : 2, isReady: true)
    }
    VStack(alignment: .leading, spacing: 16) {
      SectionHeading(title: "peso", systemImage: "scalemass", font: .title2.weight(.medium), tracking: 0)
      WeightChart(measurements: measurements.sorted { $0.date < $1.date }).frame(height: 220)
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
  private var leanMass: Double? {
    guard let item = measurements.first, let fat = item.bodyFatPercent else { return nil }
    return item.weightKg * (1 - fat / 100)
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
        .navigationTitle("")
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
            Text(latest.date.date(), format: .dateTime.day().month(.wide))
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
  let title: String
  let value: Double?
  let unit: String
  let symbol: String
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Image(systemName: symbol).foregroundStyle(accent.base).frame(height: 24)
      Text(title).font(.caption).foregroundStyle(Color.mutedInk)
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(value.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "sem registro")
          .font(.title2.weight(.medium)).monospacedDigit()
          .contentTransition(.numericText(value: value ?? 0))
          .animation(Motion.resolve(Motion.roll, reduceMotion), value: value)
        if value != nil { Text(unit).font(.caption).foregroundStyle(Color.mutedInk) }
      }
    }.frame(maxWidth: .infinity, minHeight: 110, alignment: .leading).padding(Space.l).paperCard(radius: Radius.tile)
      .accessibilityElement(children: .combine)
  }
}

struct WeightChart: View {
  @Environment(\.accent) private var accent
  @State private var selectedDate: Date?
  let measurements: [BodyMeasurement]

  /// O eixo começa um quilo abaixo da menor pesagem, e a área sobe dali. Com a
  /// área partindo do zero, ela descia por baixo do eixo.
  private var domain: ClosedRange<Double> {
    let weights = measurements.map(\.weightKg)
    let lower = ((weights.min() ?? 0) - 1).rounded(.down)
    let upper = ((weights.max() ?? 0) + 1).rounded(.up)
    return lower...upper
  }

  private var selected: BodyMeasurement? {
    guard let selectedDate else { return nil }
    return measurements.min {
      abs($0.date.date().timeIntervalSince(selectedDate)) < abs($1.date.date().timeIntervalSince(selectedDate))
    }
  }

  var body: some View {
    let domain = domain
    Chart {
      ForEach(measurements) { measurement in
        AreaMark(
          x: .value("dia", measurement.date.date()),
          yStart: .value("base", domain.lowerBound), yEnd: .value("peso", measurement.weightKg)
        )
        .interpolationMethod(.monotone)
        .foregroundStyle(accent.pale.opacity(0.4))

        LineMark(
          x: .value("dia", measurement.date.date()), y: .value("peso", measurement.weightKg)
        )
        .interpolationMethod(.monotone)
        .foregroundStyle(accent.base)

        // Com uma pesagem só, a linha não tem o que ligar; o ponto mostra que ela existe.
        PointMark(
          x: .value("dia", measurement.date.date()), y: .value("peso", measurement.weightKg)
        )
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
            ChartReadout(value: selected.weightKg, date: selected.date)
          }
      }
    }
    .chartYScale(domain: domain)
    .chartYAxisLabel("kg")
    .chartXSelection(value: $selectedDate)
    .sensoryFeedback(.selection, trigger: selected?.date)
  }
}

struct MeasurementRow: View {
  let measurement: BodyMeasurement

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(measurement.date.date(), format: .dateTime.day().month(.abbreviated))
        .font(.callout)
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
        Text(weightLabel(measurement.weightKg))
          .font(.callout.weight(.medium))
        if !extras.isEmpty {
          Text(extras).font(.footnote).foregroundStyle(Color.mutedInk)
        }
      }
      .monospacedDigit()
    }
    .frame(minHeight: 44)
    .contentShape(.rect)
  }

  private var extras: String {
    let number = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))
    return [
      measurement.bodyFatPercent.map { "\($0.formatted(number))%" },
      measurement.waistCm.map { "\($0.formatted(number)) cm de cintura" },
    ].compactMap { $0 }.joined(separator: " · ")
  }
}

struct MeasurementEditor: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var weightKg: Double?
  @State private var date = Date.now
  @State private var isSaving = false
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
      .navigationTitle(editingDate == nil ? "nova medida" : "editar medida")
      .toolbarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("cancelar") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          if isSaving {
            ProgressView()
          } else {
            Button("salvar") { save() }.disabled(!allWithinLimits)
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
      if saved { dismiss() }
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
  @FocusState private var focused: Bool

  private var outOfRange: Bool { value.map { !range.contains($0) } ?? false }

  var body: some View {
    VStack(alignment: .trailing, spacing: 2) {
      HStack {
        Text(label)
        Spacer()
        TextField("–", value: $value, format: .number.precision(.fractionLength(0...2)))
          .submitLabel(.done)
          .decimalInput().multilineTextAlignment(.trailing)
          .foregroundStyle(outOfRange ? .red : .primary)
          .focused($focused)
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
      .font(.caption2).foregroundStyle(.red)
      .frame(maxWidth: .infinity, alignment: .trailing)
      .accessibilityAddTraits(.updatesFrequently)
  }

  private func bound(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)))
  }
}
