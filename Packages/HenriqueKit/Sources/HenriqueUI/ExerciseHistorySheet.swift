import Accessibility
import Charts
import HenriqueCore
import SwiftUI

/// O exercício que a folha mostra. O nome vem de quem abre, para o título
/// aparecer antes da resposta do servidor.
struct ExerciseHistoryTarget: Identifiable, Hashable {
  let id: String
  let name: String
}

extension View {
  /// Com `choices`, a folha ganha o menu para trocar de exercício sem fechar.
  func exerciseHistorySheet(
    item: Binding<ExerciseHistoryTarget?>, choices: [ExerciseHistoryTarget] = []
  ) -> some View {
    sheet(item: item) { ExerciseHistorySheet(target: $0, choices: choices) }
      .sensoryFeedback(.selection, trigger: item.wrappedValue) { _, new in new != nil }
  }
}

extension Dashboard {
  /// Os exercícios do plano e do treino do dia, um de cada, em ordem de nome.
  var historyTargets: [ExerciseHistoryTarget] {
    let names = Dictionary(exerciseCatalog.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    var seen = Set<String>()
    let planned = weekPlan.flatMap(\.exercises).map { ($0.exerciseId, names[$0.exerciseId] ?? $0.name) }
    let today = (workout?.exercises ?? []).map { ($0.id, Optional($0.name)) }
    return (planned + today).compactMap { id, name in
      guard let name, seen.insert(id).inserted else { return nil }
      return ExerciseHistoryTarget(id: id, name: name)
    }
    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
}

/// A carga atual, a carga do topo sessão a sessão e cada sessão com as séries.
struct ExerciseHistorySheet: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var phase: Phase = .loading
  @State private var attempt = 0
  @State private var selectedDate: Date?
  @State private var target: ExerciseHistoryTarget
  let choices: [ExerciseHistoryTarget]

  init(target: ExerciseHistoryTarget, choices: [ExerciseHistoryTarget] = []) {
    _target = State(initialValue: target)
    self.choices = choices
  }

  private enum Phase: Equatable {
    case loading
    case loaded(ExerciseHistory)
    /// O servidor ainda sem a rota. A folha mostra a última vez que o painel já tem.
    case unsupported
    case failed(String)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Space.l) {
          content
        }
        .padding(.horizontal, Space.l).padding(.top, Space.s).padding(.bottom, Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Motion.resolve(Motion.crossfade, reduceMotion), value: phase)
      }
      .background(Color.canvas.ignoresSafeArea())
      .navigationTitle(target.name.lowercased())
      .toolbarTitleDisplayMode(.inline)
      .toolbar {
        if choices.count > 1 {
          ToolbarItem(placement: .topBarLeading) {
            Menu("exercício", systemImage: "list.bullet") {
              Picker("exercício", selection: $target) {
                ForEach(choices) { choice in
                  Text(choice.name.lowercased()).tag(choice)
                }
              }
            }
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button(role: .close) { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
    .task(id: "\(target.id)#\(attempt)") { await load() }
    .onChange(of: target) {
      phase = .loading
      selectedDate = nil
    }
  }

  @ViewBuilder private var content: some View {
    switch phase {
    case .loading:
      LoadHero(kilograms: store.dashboard?.loadKg(exerciseId: target.id))
      skeleton
    case .loaded(let history):
      LoadHero(kilograms: history.load.workWeightKg)
      if history.entries.isEmpty {
        emptyView
      } else {
        // Um ponto só não é curva: o eixo virava horas de um dia e o ponto
        // ficava sem data. A carga atual em cima e a linha da sessão bastam.
        if history.entries.count > 1 {
          LoadChart(entries: history.entries, selectedDate: $selectedDate)
        }
        VStack(spacing: 0) {
          ForEach(history.entries) { entry in
            sessionRow(
              date: entry.date, sets: setsText(entry), workout: entry.workoutName,
              highlighted: selectedEntry(in: history.entries)?.id == entry.id
            ) { selectedDate = entry.date.date() }
            if entry.id != history.entries.last?.id { Divider() }
          }
        }
        .padding(.horizontal, Space.l).paperCard(radius: Radius.row)
      }
    case .unsupported:
      LoadHero(kilograms: store.dashboard?.loadKg(exerciseId: target.id))
      if let last = lastTime {
        sessionRow(date: last.date, sets: setsText(last), workout: nil, highlighted: false, onTap: nil)
          .padding(.horizontal, Space.l).paperCard(radius: Radius.row)
      } else {
        emptyView
      }
    case .failed(let message):
      ContentUnavailableView {
        Label("não carregou", systemImage: "exclamationmark.icloud")
      } description: {
        Text(message)
      } actions: {
        Button("tentar de novo", systemImage: "arrow.clockwise") { attempt += 1 }
          .buttonStyle(.glass)
          .sensoryFeedback(.impact(weight: .light), trigger: attempt)
      }
    }
  }

  private var emptyView: some View {
    ContentUnavailableView("nenhuma sessão ainda", systemImage: "chart.line.uptrend.xyaxis")
  }

  private var skeleton: some View {
    VStack(alignment: .leading, spacing: Space.l) {
      RoundedRectangle(cornerRadius: Radius.row).fill(Color.surfaceMuted).frame(height: 236)
      VStack(spacing: 0) {
        ForEach(0..<3, id: \.self) { _ in
          sessionRow(
            date: .today, sets: "00 × 0, 00 × 0", workout: "treino", highlighted: false, onTap: nil)
        }
      }
      .padding(.horizontal, Space.l).paperCard(radius: Radius.row)
      .redacted(reason: .placeholder)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("carregando o histórico")
  }

  /// "12 out · 55 × 8, 55 × 7", com o treino embaixo.
  private func sessionRow(
    date: CalendarDate, sets: String, workout: String?, highlighted: Bool, onTap: (() -> Void)?
  ) -> some View {
    let row = HStack(alignment: .firstTextBaseline, spacing: Space.m) {
      Text(Formatting.shortDate(date))
        .font(.subheadline).foregroundStyle(Color.mutedInk)
        .frame(minWidth: 52, alignment: .leading)
      VStack(alignment: .leading, spacing: 2) {
        Text(sets).font(.subheadline.weight(.medium)).monospacedDigit()
        if let workout {
          Text(workout.lowercased()).font(.caption).foregroundStyle(Color.mutedInk).lineLimit(1)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .background { Color.surfaceMuted.opacity(highlighted ? 1 : 0).padding(.horizontal, -Space.l) }
    .contentShape(.rect)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(spokenDate(date))
    .accessibilityValue([sets.spokenSets, workout?.lowercased()].compactMap { $0 }.joined(separator: ", "))
    return Group {
      if let onTap {
        Button(action: onTap) { row }.buttonStyle(StudyPressStyle()).foregroundStyle(Color.ink)
      } else {
        row
      }
    }
  }

  private func selectedEntry(in entries: [ExerciseHistory.Entry]) -> ExerciseHistory.Entry? {
    LoadChart.nearest(to: selectedDate, in: entries)
  }

  private var lastTime: PreviousWorkSets? {
    let dashboard = store.dashboard
    return dashboard?.workout?.exercises.first { $0.id == target.id }?.previous
      ?? dashboard?.strengthGoal.flatMap { $0.exerciseId == target.id ? $0.lastSession : nil }
  }

  private func load() async {
    if let cached = store.cachedHistory(of: target.id) {
      phase = .loaded(cached)
      return
    }
    if case .failed = phase { phase = .loading }
    do {
      phase = .loaded(try await store.history(of: target.id))
    } catch is CancellationError {
    } catch APIError.http(status: 404, _) {
      phase = .unsupported
    } catch {
      phase = .failed((error as? APIError)?.message ?? APIError.offlineMessage)
    }
  }
}

/// A carga de agora em destaque. O número rola quando a resposta do servidor
/// troca a carga que o painel já sabia.
private struct LoadHero: View {
  @Environment(\.accent) private var accent
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .largeTitle) private var loadSize = 44.0
  let kilograms: Double?

  var body: some View {
    if let kilograms, kilograms > 0 {
      VStack(alignment: .leading, spacing: 0) {
        Text("carga atual").font(.caption).foregroundStyle(Color.mutedInk)
        Text(weightLabel(kilograms))
          .font(.system(size: loadSize, weight: .semibold)).monospacedDigit()
          .foregroundStyle(accent.deep)
          .contentTransition(.numericText(value: kilograms))
          .animation(Motion.resolve(Motion.roll, reduceMotion), value: kilograms)
      }
      .accessibilityElement(children: .combine)
    }
  }
}

/// A carga do topo de cada sessão. Arrastar sobre o gráfico mostra a sessão
/// mais perto do dedo.
private struct LoadChart: View, AXChartDescriptorRepresentable {
  @Environment(\.accent) private var accent
  let entries: [ExerciseHistory.Entry]
  @Binding var selectedDate: Date?

  private var selected: ExerciseHistory.Entry? { Self.nearest(to: selectedDate, in: entries) }

  static func nearest(to date: Date?, in entries: [ExerciseHistory.Entry]) -> ExerciseHistory.Entry? {
    guard let date else { return nil }
    return entries.min {
      abs($0.date.date().timeIntervalSince(date)) < abs($1.date.date().timeIntervalSince(date))
    }
  }

  var body: some View {
    Chart {
      ForEach(entries) { entry in
        LineMark(x: .value("dia", entry.date.date(), unit: .day), y: .value("kg", entry.topWeightKg))
          .interpolationMethod(.monotone)
          .foregroundStyle(accent.base)
        PointMark(x: .value("dia", entry.date.date(), unit: .day), y: .value("kg", entry.topWeightKg))
          .foregroundStyle(accent.base)
          .symbolSize(entry.id == selected?.id ? 100 : 36)
      }
      if let selected {
        RuleMark(x: .value("dia", selected.date.date(), unit: .day))
          .foregroundStyle(Color.mutedInk.opacity(0.35))
          .annotation(
            position: .top, spacing: 4,
            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
          ) {
            VStack(alignment: .leading, spacing: 1) {
              Text(Formatting.shortDate(selected.date)).foregroundStyle(Color.mutedInk)
              Text(setsText(selected)).fontWeight(.medium).monospacedDigit()
            }
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.white, in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.ink.opacity(0.08)))
          }
      }
    }
    .chartYScale(domain: .automatic(includesZero: false))
    .chartYAxisLabel("kg")
    .chartXAxis {
      AxisMarks(values: .automatic(desiredCount: 4)) { value in
        AxisGridLine()
        AxisValueLabel {
          if let date = value.as(Date.self) { Text(Formatting.shortDate(CalendarDate(date))) }
        }
      }
    }
    .chartXSelection(value: $selectedDate)
    .sensoryFeedback(.selection, trigger: selected?.id)
    .frame(height: 200)
    .padding(.top, 36)
    .padding(Space.l)
    .paperCard(radius: Radius.row)
    .accessibilityChartDescriptor(self)
  }

  nonisolated func makeChartDescriptor() -> AXChartDescriptor {
    let ordered = entries.sorted { $0.date < $1.date }
    let times = ordered.map { $0.date.date().timeIntervalSince1970 }
    let weights = ordered.map(\.topWeightKg)
    let low = weights.min() ?? 0
    let high = weights.max() ?? 0
    let xAxis = AXNumericDataAxisDescriptor(
      title: "data", range: (times.min() ?? 0)...(times.max() ?? 0), gridlinePositions: []
    ) { spokenDate(CalendarDate(Date(timeIntervalSince1970: $0))) }
    let yAxis = AXNumericDataAxisDescriptor(
      title: "carga do topo", range: low...high, gridlinePositions: []
    ) { "\(Formatting.trim($0)) quilos" }
    let series = AXDataSeriesDescriptor(
      name: "carga do topo", isContinuous: true,
      dataPoints: ordered.map {
        AXDataPoint(
          x: $0.date.date().timeIntervalSince1970, y: $0.topWeightKg, additionalValues: [],
          label: setsText($0).spokenSets)
      })
    let sessions = ordered.count == 1 ? "1 sessão" : "\(ordered.count) sessões"
    return AXChartDescriptor(
      title: "carga do topo por sessão",
      summary: "de \(Formatting.trim(low)) a \(Formatting.trim(high)) quilos em \(sessions)",
      xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
  }
}

private func spokenDate(_ date: CalendarDate) -> String {
  date.date().formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "pt_BR")))
}

private func setsText(_ entry: ExerciseHistory.Entry) -> String {
  guard !entry.sets.isEmpty else { return "\(Formatting.trim(entry.topWeightKg)) × \(entry.topReps)" }
  return entry.sets.sorted { $0.index < $1.index }
    .map { "\(Formatting.trim($0.weightKg)) × \($0.reps)" }.joined(separator: ", ")
}

private func setsText(_ previous: PreviousWorkSets) -> String {
  if let sets = previous.sets, !sets.isEmpty {
    return sets.sorted { $0.index < $1.index }
      .map { "\(Formatting.trim($0.weightKg)) × \($0.reps)" }.joined(separator: ", ")
  }
  return previous.reps.map { "\(Formatting.trim(previous.weightKg)) × \($0)" }.joined(separator: ", ")
}

extension String {
  /// "55 × 8" lido como "55 quilos por 8".
  fileprivate var spokenSets: String {
    replacingOccurrences(of: " × ", with: " quilos por ")
  }
}

/// O sinal de que a linha abre o histórico. O VoiceOver já ouve o botão.
struct HistoryGlyph: View {
  var body: some View {
    Image(systemName: "chart.line.uptrend.xyaxis")
      .font(.footnote.weight(.semibold)).foregroundStyle(Color.mutedInk)
      .padding(.leading, Space.s)
      .accessibilityHidden(true)
  }
}
