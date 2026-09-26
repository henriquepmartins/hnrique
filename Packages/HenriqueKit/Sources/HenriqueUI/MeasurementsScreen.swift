import Charts
import HenriqueCore
import SwiftUI

struct MeasurementsScreen: View {
  @Environment(AcademiaStore.self) private var store
  @State private var isAdding = false
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
          Text("peso").font(.title2.weight(.medium))
          if measurements.isEmpty {
            Text("sem medidas").foregroundStyle(Color.mutedInk).frame(height: 220)
          } else {
            WeightChart(measurements: measurements.sorted { $0.date < $1.date }).frame(height: 220)
          }
        }.padding(Space.xl).paperCard()
          .staggeredEntrance(index: 2, isReady: true)
        VStack(alignment: .leading, spacing: 16) {
          Text("histórico").font(.title2.weight(.medium))
          ForEach(measurements) { measurement in
            MeasurementRow(measurement: measurement)
            Divider()
          }
        }.padding(Space.xl).paperCard()
          .staggeredEntrance(index: 3, isReady: true)
      }.padding(16).padding(.bottom, 32)
    }
    .refreshable { await store.load() }
    .sheet(isPresented: $isAdding) { MeasurementEditor(previous: measurements.first) }
  }
  private var leanMass: Double? {
    guard let item = measurements.first, let fat = item.bodyFatPercent else { return nil }
    return item.weightKg * (1 - fat / 100)
  }
}

/// A porta das medidas dentro de progresso. Medidas deixou de ser aba, então o
/// resumo mostra o número mais recente e o toque abre a tela inteira.
struct MeasurementsLink: View {
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
        .animation(Motion.crossfade, value: text)
      Text(caption).font(.caption).foregroundStyle(Color.mutedInk)
    }
  }
}

struct MeasurementMetric: View {
  @Environment(\.accent) private var accent
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
        if value != nil { Text(unit).font(.caption).foregroundStyle(Color.mutedInk) }
      }
    }.frame(maxWidth: .infinity, minHeight: 110, alignment: .leading).padding(Space.l).paperCard(radius: Radius.tile)
      .accessibilityElement(children: .combine)
  }
}

struct WeightChart: View {
  @Environment(\.accent) private var accent
  let measurements: [BodyMeasurement]

  var body: some View {
    Chart(measurements) { measurement in
      LineMark(
        x: .value("dia", measurement.date.date()), y: .value("peso", measurement.weightKg)
      )
      .interpolationMethod(.monotone)
      .foregroundStyle(accent.base)

      AreaMark(
        x: .value("dia", measurement.date.date()), y: .value("peso", measurement.weightKg)
      )
      .interpolationMethod(.monotone)
      .foregroundStyle(accent.pale.opacity(0.4))
    }
    .chartYScale(domain: .automatic(includesZero: false))
    .chartYAxisLabel("kg")
  }
}

struct MeasurementRow: View {
  let measurement: BodyMeasurement

  var body: some View {
    HStack {
      Text(measurement.date.date(), format: .dateTime.day().month(.abbreviated))
        .font(.callout)
      Spacer()
      Text(weightLabel(measurement.weightKg))
        .font(.callout.weight(.medium))
        .monospacedDigit()
    }
  }
}

struct MeasurementEditor: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var weightKg: Double?
  @State private var isSaving = false
  @State private var bodyFatPercent: Double?
  @State private var waistCm: Double?
  @State private var chestCm: Double?
  @State private var armCm: Double?
  @State private var thighCm: Double?

  /// Começar da última medida poupa digitação: o peso muda pouco entre pesagens
  /// e as circunferências costumam ficar iguais por semanas.
  init(previous: BodyMeasurement?) {
    weightKg = previous?.weightKg
    bodyFatPercent = previous?.bodyFatPercent
    waistCm = previous?.waistCm
    chestCm = previous?.chestCm
    armCm = previous?.armCm
    thighCm = previous?.thighCm
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("peso") {
          TextField("kg", value: $weightKg, format: .number.precision(.fractionLength(0...2)))
            .submitLabel(.done)
            .decimalInput()
          if let weightKg, !Limits.bodyWeightKg.contains(weightKg) {
            RangeHint(range: Limits.bodyWeightKg, unit: "kg")
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
      .navigationTitle("nova medida")
      .toolbarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("cancelar") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("salvar") { save() }.disabled(isSaving || !allWithinLimits)
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
      date: .today, weightKg: weightKg, bodyFatPercent: bodyFatPercent, waistCm: waistCm,
      chestCm: chestCm, armCm: armCm, thighCm: thighCm)
    isSaving = true
    Task {
      let saved = await store.addMeasurement(input)
      isSaving = false
      if saved { dismiss() }
    }
  }
}

/// Um campo que a pessoa pode simplesmente não preencher. O botão liga e desliga
/// o campo em vez de exigir apagar um número para dizer "não medi".
struct OptionalField: View {
  let label: String
  let unit: String
  let range: ClosedRange<Double>
  @Binding var value: Double?

  private var outOfRange: Bool { value.map { !range.contains($0) } ?? false }

  var body: some View {
    VStack(alignment: .trailing, spacing: 2) {
      HStack {
        Text(label)
        Spacer()
        TextField("", value: $value, format: .number.precision(.fractionLength(0...2)))
          .submitLabel(.done)
          .decimalInput().multilineTextAlignment(.trailing)
          .foregroundStyle(outOfRange ? .red : .primary)
          .accessibilityLabel(label)
        Text(unit).font(.caption).foregroundStyle(Color.mutedInk)
      }
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
