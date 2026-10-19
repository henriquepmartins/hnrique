import Charts
import HenriqueCore
import SwiftUI

/// Os três tipos de meta que o editor cobre. Força é a de carga; as outras duas
/// são as sequências do painel, e a ponte com `StreakKind` fica aqui.
enum GoalKind: Hashable, CaseIterable, Identifiable {
  case strength, attendance, complete

  var id: Self { self }

  init(_ streak: StreakKind) {
    switch streak {
    case .attendance: self = .attendance
    case .complete: self = .complete
    }
  }

  var streakKind: StreakKind? {
    switch self {
    case .strength: nil
    case .attendance: .attendance
    case .complete: .complete
    }
  }

  var face: (label: String, systemImage: String) {
    switch self {
    case .strength: ("força", "dumbbell.fill")
    case .attendance: ("presença", "flame.fill")
    case .complete: ("completos", "checkmark.seal.fill")
    }
  }
}

struct ProgressScreen: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.accent) private var accent
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var editing: GoalKind?
  @State private var history: ExerciseHistoryTarget?
  var onWorkout: () -> Void = {}

  var body: some View {
    ScrollView {
      VStack(spacing: Space.xxl) {
        if let dashboard = store.dashboard {
          let streakGoals = dashboard.streakGoals ?? []
          HStack {
            SectionHeading(title: "metas", systemImage: "target", font: .title2.weight(.medium), tracking: -0.8)
            Spacer()
            IconButton(title: "nova meta", systemImage: "plus", glass: true) {
              editing = newGoalKind(in: dashboard)
            }
          }
          .subtleEntrance()
          if let goal = dashboard.strengthGoal {
            GoalCard(
              exerciseName: goal.exerciseName, targetValue: goal.targetValue,
              projection: dashboard.projection
            ) { editing = .strength }
              .subtleEntrance()
          }
          ForEach(streakGoals, id: \.kind) { goal in
            StreakGoalCard(
              kind: GoalKind(goal.kind), current: dashboard.streak(goal.kind), target: goal.target
            ) { editing = GoalKind(goal.kind) }
              .subtleEntrance()
          }
        }
        // Fora do painel de propósito. O mapa lê a própria frequência e carrega a
        // faixa visível sozinho, então esperar o painel só atrasaria a primeira
        // abertura da aba.
        AttendanceMap(attendance: store.attendance) { from, to in
          await store.loadAttendance(from: from, to: to)
        }
        if let dashboard = store.dashboard {
          VStack(alignment: .leading, spacing: 10) {
            Text("\(dashboard.consistencyPercent)%").font(.system(size: 48, weight: .medium)).monospacedDigit()
              .contentTransition(.numericText(value: Double(dashboard.consistencyPercent)))
              .animation(Motion.resolve(Motion.roll, reduceMotion), value: dashboard.consistencyPercent)
            Text("4 semanas").font(.subheadline)
          }
          .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("constância nas últimas 4 semanas")
          .accessibilityValue("\(dashboard.consistencyPercent)%")
          .padding(Space.xl).background(accent.deep, in: .rect(cornerRadius: Radius.card))
          .subtleEntrance()
          if let series = dashboard.strengthSeries {
            NavigationLink { MetricDetailScreen(onWorkout: onWorkout) } label: {
              OneRepMaxChart(
                title: series.exerciseName, points: series.points,
                target: dashboard.strengthGoal?.targetValue
              ) {
                history = ExerciseHistoryTarget(id: series.exerciseId, name: series.exerciseName)
              }
            }
            .buttonStyle(StudyPressStyle())
            .foregroundStyle(Color.ink)
            .subtleEntrance()
            VolumeChart(exerciseName: series.exerciseName, points: series.points)
              .subtleEntrance()
          } else {
            ContentUnavailableView {
              Label("sem histórico", systemImage: "chart.xyaxis.line")
            } actions: {
              Button("começar treino", systemImage: "play.fill", action: onWorkout)
                .buttonStyle(.glassProminent)
            }
            .subtleEntrance()
          }
          MeasurementsLink(latest: latest(in: dashboard))
            .subtleEntrance()
        } else {
          ProgressPlaceholder(phase: store.phase) { await store.load() }
        }
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 40)
    }
    .refreshable { await store.load() }
    .exerciseHistorySheet(item: $history, choices: store.dashboard?.historyTargets ?? [])
    .sheet(item: $editing) { kind in
      if let dashboard = store.dashboard {
        GoalEditor(kind: kind, dashboard: dashboard)
          .presentationDetents([.medium, .large])
      }
    }
  }

  /// O botão abre o editor no primeiro tipo ainda sem meta, começando pela de
  /// força. Com as três definidas, volta para a força.
  private func newGoalKind(in dashboard: Dashboard) -> GoalKind {
    if dashboard.strengthGoal == nil, !dashboard.exerciseCatalog.isEmpty { return .strength }
    return StreakKind.allCases.first { dashboard.goal($0) == nil }.map(GoalKind.init)
      ?? (dashboard.exerciseCatalog.isEmpty ? .attendance : .strength)
  }
}

/// A aba sem painel: o esqueleto no formato da constância, do gráfico de força e
/// das medidas enquanto carrega, e a nova tentativa quando falhou.
private struct ProgressPlaceholder: View {
  let phase: AcademiaStore.Phase
  let retry: () async -> Void

  var body: some View {
    switch phase {
    case .loading:
      VStack(spacing: Space.xxl) {
        ForEach([140, 260, 120], id: \.self) { height in
          RoundedRectangle(cornerRadius: Radius.card).frame(height: CGFloat(height))
        }
      }
      .foregroundStyle(Color.surfaceMuted)
      .modifier(SkeletonPulse())
      .accessibilityHidden(true)
      .transition(.opacity)
    case .failed(let message):
      LoadFailure(message: message, retry: retry)
        .transition(.opacity)
    case .idle, .ready:
      EmptyView()
    }
  }
}

struct StreakGoalCard: View {
  @Environment(\.accent) private var accent
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .headline) private var iconWidth = 24.0
  let kind: GoalKind
  let current: Int
  let target: Int
  let action: () -> Void

  private var progress: Double { min(1, Double(current) / Double(max(target, 1))) }
  private var reached: Bool { current >= target }

  /// A sequência tem cor própria em toda tela: a chama da presença no degradê
  /// dela e o selo dos completos na tinta do selo da folha da sequência.
  private var iconStyle: AnyShapeStyle {
    switch kind {
    case .attendance: AnyShapeStyle(streakGradient)
    case .complete: AnyShapeStyle(streakTone.ink)
    case .strength: AnyShapeStyle(Color.ink)
    }
  }

  private var barTint: Color {
    if reached { return accent.deep }
    switch kind {
    case .attendance: return streakTone.top
    case .complete: return streakTone.ink
    case .strength: return accent.signal
    }
  }

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: Space.m) {
        Label {
          Text(kind.face.label)
        } icon: {
          Image(systemName: kind.face.systemImage).foregroundStyle(iconStyle).frame(width: iconWidth)
        }
          .font(.headline)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text("\(current)")
            .font(.largeTitle.weight(.semibold))
            .foregroundStyle(accent.base)
            .contentTransition(.numericText(value: Double(current)))
            .animation(Motion.resolve(Motion.roll, reduceMotion), value: current)
          Text("/\(target)")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .monospacedDigit()
        ProgressView(value: progress)
          .tint(barTint)
          .animation(reduceMotion ? nil : Motion.crossfade, value: progress)
        if reached { GoalReachedSeal(reached: reached) }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Space.xl)
      .background(accent.pale, in: .rect(cornerRadius: Radius.card))
      .contentShape(.rect(cornerRadius: Radius.card))
    }
    .buttonStyle(StudyPressStyle())
    .foregroundStyle(Color.ink)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("meta de \(kind.face.label), \(current) de \(target)")
    .accessibilityValue(reached ? "meta batida" : "")
    .accessibilityAddTraits(.isButton)
    .sensoryFeedback(.success, trigger: reached) { old, new in !old && new }
  }
}

/// A meta batida é a conquista mais rara da aba. Selo no tom do acento, um
/// pulo do símbolo quando ela chega e nada de confete; com Reduzir Movimento
/// fica só a cor.
struct GoalReachedSeal: View {
  @Environment(\.accent) private var accent
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let reached: Bool

  var body: some View {
    Label("meta batida", systemImage: "checkmark.seal.fill")
      .font(.footnote.weight(.semibold))
      .foregroundStyle(accent.deep)
      .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : reached)
      .accessibilityHidden(true)
  }
}

extension Dashboard {
  /// A série de força da tela: a da meta quando existe, senão a do exercício
  /// que o servidor destaca. Nula quando nenhuma das duas tem ponto.
  fileprivate var strengthSeries: (exerciseId: String, exerciseName: String, points: [ProgressPoint])? {
    if let goal = strengthGoal, !progress.isEmpty { return (goal.exerciseId, goal.exerciseName, progress) }
    if let featured = featuredProgress, !featured.points.isEmpty {
      return (featured.exerciseId, featured.exerciseName, featured.points)
    }
    return nil
  }
}

/// A medida mais recente do painel. O servidor devolve a lista sem ordem
/// garantida, então a data decide.
private func latest(in dashboard: Dashboard) -> BodyMeasurement? {
  dashboard.measurements.max { $0.date < $1.date }
}

struct GoalCard: View {
  @Environment(\.accent) private var accent
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .headline) private var iconWidth = 24.0
  let exerciseName: String
  let targetValue: Double
  let projection: Projection?
  let action: () -> Void

  var body: some View {
    Button(action: action) { card }
      .buttonStyle(StudyPressStyle())
      .foregroundStyle(Color.ink)
      .sensoryFeedback(.success, trigger: reached) { old, new in !old && new }
  }

  private var reached: Bool { projection?.weeksRemaining == 0 }

  private var card: some View {
    VStack(alignment: .leading, spacing: Space.m) {
      Label { Text(exerciseName.lowercased()) } icon: { Image(systemName: "target").frame(width: iconWidth) }
        .font(.headline)
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        // Sem projeção ainda não há carga para mostrar, e um "0 kg" leria como dado.
        Text(projection.map { weightLabel($0.current) } ?? "–")
          .font(.largeTitle.weight(.semibold))
          .monospacedDigit()
          .foregroundStyle(accent.base)
          .contentTransition(.numericText(value: projection?.current ?? 0))
          .animation(Motion.resolve(Motion.roll, reduceMotion), value: projection?.current)
        Text("de \(weightLabel(targetValue))")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      if let projection {
        ProgressView(value: min(projection.current / max(projection.target, 1), 1))
          .tint(reached ? accent.deep : accent.signal)
        if reached {
          GoalReachedSeal(reached: reached)
        } else if let sentence = projectionSentence(projection) {
          Text(sentence).font(.footnote).foregroundStyle(.secondary)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Space.xl)
    .background(accent.pale, in: .rect(cornerRadius: Radius.card))
    .contentShape(.rect(cornerRadius: Radius.card))
  }

  private func projectionSentence(_ projection: Projection) -> String? {
    guard let weeks = projection.weeksRemaining, weeks > 0 else { return nil }
    return "em \(weeks) \(weeks == 1 ? "semana" : "semanas")"
  }
}

struct OneRepMaxChart: View {
  @Environment(\.accent) private var accent
  let title: String
  let points: [ProgressPoint]
  let target: Double?
  let onHistory: () -> Void

  var body: some View {
    ChartCard(title: title.lowercased(), opens: true, onHistory: onHistory) {
      Chart {
        ForEach(points) { point in
          LineMark(
            x: .value("dia", point.date.date()), y: .value("1RM", point.estimatedOneRepMax)
          )
          .interpolationMethod(.monotone)
          .foregroundStyle(accent.base)

          PointMark(
            x: .value("dia", point.date.date()), y: .value("1RM", point.estimatedOneRepMax)
          )
          .foregroundStyle(accent.base)
        }
        if let target {
          RuleMark(y: .value("meta", target))
            .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
            .foregroundStyle(accent.signal)
            .annotation(position: .top, alignment: .leading) {
              Text("meta").font(.caption2).foregroundStyle(.secondary)
            }
        }
      }
      .chartYAxisLabel("kg")
    }
  }
}

struct VolumeChart: View {
  @Environment(\.accent) private var accent
  @State private var selectedDate: Date?
  let exerciseName: String
  let points: [ProgressPoint]

  private var selected: ProgressPoint? {
    guard let selectedDate else { return nil }
    return points.min {
      abs($0.date.date().timeIntervalSince(selectedDate)) < abs($1.date.date().timeIntervalSince(selectedDate))
    }
  }

  var body: some View {
    ChartCard(title: "volume · \(exerciseName.lowercased())") {
      Chart {
        ForEach(points) { point in
          AreaMark(x: .value("dia", point.date.date()), y: .value("volume", point.volumeKg))
            .interpolationMethod(.monotone)
            .foregroundStyle(LinearGradient(colors: [accent.mint.opacity(0.8), accent.mint.opacity(0.08)], startPoint: .top, endPoint: .bottom))
          LineMark(x: .value("dia", point.date.date()), y: .value("volume", point.volumeKg))
            .interpolationMethod(.monotone).foregroundStyle(accent.base)
        }
        if let selected {
          RuleMark(x: .value("dia", selected.date.date()))
            .foregroundStyle(Color.ink.opacity(0.2))
            .annotation(
              position: .top, spacing: 4,
              overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
            ) {
              ChartReadout(value: weightLabel(selected.volumeKg), date: selected.date)
            }
        }
      }
      .chartYAxisLabel("kg")
      .chartXSelection(value: $selectedDate)
      .sensoryFeedback(.selection, trigger: selected?.date)
    }
  }
}

/// O valor e o dia do ponto sob o dedo, em cima da régua.
struct ChartReadout: View {
  let value: String
  let date: CalendarDate

  var body: some View {
    Text("\(value) · \(Formatting.shortDate(date))")
      .font(.caption.weight(.medium)).monospacedDigit()
      .foregroundStyle(Color.ink)
      .padding(.horizontal, 8).padding(.vertical, 4)
      .background(Color.surfaceMuted, in: .capsule)
  }
}

struct ChartCard<Content: View>: View {
  let title: String
  /// O cartão é o link para os detalhes, e o chevron é o que diz isso.
  var opens = false
  /// Abre o histórico do exercício do cartão. O desenho de seletor no título
  /// prometia trocar o gráfico, e abria outra coisa por cima.
  var onHistory: (() -> Void)?
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: Space.m) {
      HStack {
        Text(title).font(.headline)
          .lineLimit(2).minimumScaleFactor(0.7)
        Spacer(minLength: 8)
        if let onHistory {
          Button("histórico", systemImage: "clock.arrow.circlepath", action: onHistory)
            .labelStyle(.iconOnly)
            .font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
            .frame(width: 44, height: 44).contentShape(.rect)
            .buttonStyle(.plain)
        }
        if opens {
          Image(systemName: "chevron.right")
            .font(.subheadline.weight(.semibold)).foregroundStyle(Color.mutedInk)
        }
      }
      content
        .frame(height: 220)
        // O VoiceOver lê o gráfico pelo descritor; acima disso os rótulos dos
        // eixos encostavam uns nos outros e a área de desenho ficava pela metade.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Space.xl)
    .paperCard()
  }
}

/// Um editor para as três metas. O segmento de cima troca o formulário e o
/// salvar manda para a rota do tipo escolhido.
struct GoalEditor: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var kind: GoalKind
  @State private var exerciseId: String
  @State private var targetValue: Double
  @State private var streakTargets: [StreakKind: Int]
  @State private var isSaving = false
  @State private var saves = 0

  private let catalog: [ExerciseCatalogItem]
  private let streaks: [StreakKind: Int]

  init(kind: GoalKind, dashboard: Dashboard) {
    self.kind = kind
    catalog = dashboard.exerciseCatalog
    exerciseId = dashboard.strengthGoal?.exerciseId ?? dashboard.exerciseCatalog.first?.id ?? ""
    targetValue = dashboard.strengthGoal?.targetValue ?? 60
    streaks = Dictionary(uniqueKeysWithValues: StreakKind.allCases.map { ($0, dashboard.streak($0)) })
    streakTargets = Dictionary(
      uniqueKeysWithValues: StreakKind.allCases.map { streak in
        (streak, dashboard.goal(streak)?.target ?? max(dashboard.streak(streak) + 5, 7))
      })
  }

  private var canSave: Bool {
    switch kind {
    case .strength: !exerciseId.isEmpty && Limits.strengthTarget.contains(targetValue)
    case .attendance, .complete: true
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("tipo", selection: $kind) {
            // Força pede um exercício do catálogo; sem catálogo, o segmento sai.
            ForEach(GoalKind.allCases.filter { $0 != .strength || !catalog.isEmpty }) { kind in
              Text(kind.face.label).tag(kind)
            }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
        }
        if let streak = kind.streakKind {
          Section {
            StreakGoalFields(
              kind: kind, current: streaks[streak] ?? 0,
              target: Binding(
                get: { streakTargets[streak] ?? 7 }, set: { streakTargets[streak] = $0 }))
          }
        } else {
          Section {
            Picker("exercício", selection: $exerciseId) {
              ForEach(catalog) { item in
                Text(item.name).tag(item.id)
              }
            }
            .labelsHidden()
            .pickerStyle(.inline)
          }
          Section {
            WeightStepper(weightKg: $targetValue, range: Limits.strengthTarget)
          }
        }
      }
      .interactiveDismissDisabled(isSaving)
      .sensoryFeedback(.success, trigger: saves)
      // Na altura média a folha de vidro deixava o cartão verde de trás vazar
      // pela lista de exercícios.
      .scrollContentBackground(.hidden)
      .background(Color.canvas)
      .navigationTitle("meta")
      .toolbarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("cancelar", systemImage: "xmark", role: .cancel) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("salvar", systemImage: "checkmark", role: .confirm) { save() }
            .disabled(isSaving || !canSave)
        }
      }
    }
    .presentationBackground(Color.canvas)
  }

  private func save() {
    isSaving = true
    Task {
      let saved: Bool
      if let streak = kind.streakKind {
        saved = await store.setStreakGoal(
          SetStreakGoalInput(
            date: store.selectedDate, kind: streak, target: streakTargets[streak] ?? 7))
      } else {
        saved = await store.setStrengthGoal(
          SetStrengthGoalInput(
            date: store.selectedDate, exerciseId: exerciseId, targetValue: targetValue))
      }
      isSaving = false
      if saved {
        saves += 1
        dismiss()
      }
    }
  }
}

private struct StreakGoalFields: View {
  @Environment(\.accent) private var accent
  let kind: GoalKind
  let current: Int
  @Binding var target: Int

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: kind.face.systemImage).font(.title).foregroundStyle(accent.base)
      Text("\(current)").font(.system(size: 44, weight: .medium)).monospacedDigit()
      Spacer(minLength: 0)
    }
    .frame(minHeight: 64)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(kind.face.label) atual, \(current)")
    HStack(spacing: 12) {
      Text("alvo").font(.body)
      Spacer(minLength: 8)
      Text("\(target)").font(.body.weight(.semibold)).monospacedDigit()
        .frame(minWidth: 32, alignment: .trailing)
      Stepper("alvo", value: $target, in: Limits.streakTarget)
        .labelsHidden()
    }
    .frame(minHeight: 48)
  }
}

struct MetricDetailScreen: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.accent) private var accent
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var bodyTrack = false
  @State private var allHistory = false
  @State private var selectedDate: Date?

  private var values: [(date: CalendarDate, value: Double)] {
    guard let data = store.dashboard else { return [] }
    if bodyTrack {
      return data.measurements.compactMap { item in
        item.bodyFatPercent.map { (date: item.date, value: item.weightKg * (1 - $0 / 100)) }
      }.sorted { $0.date < $1.date }
    }
    return (data.strengthSeries?.points ?? []).map { (date: $0.date, value: $0.estimatedOneRepMax) }
      .sorted { $0.date < $1.date }
  }
  private var window: [(date: CalendarDate, value: Double)] {
    guard !allHistory, let last = values.last else { return values }
    return values.filter { $0.date >= last.date.adding(days: -56) }
  }
  /// O ponto sob o dedo no gráfico; sem toque, o último.
  private var shown: (date: CalendarDate, value: Double)? {
    guard let selectedDate else { return window.last }
    return window.min {
      abs($0.date.date().timeIntervalSince(selectedDate)) < abs($1.date.date().timeIntervalSince(selectedDate))
    }
  }

  @State private var isAddingMeasurement = false
  @State private var isEditingGoal = false
  var onWorkout: () -> Void = {}

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Space.xxl) {
        Picker("métrica em foco", selection: $bodyTrack) {
          Text("força").tag(false)
          Text("corpo").tag(true)
        }.pickerStyle(.segmented)
        VStack(spacing: Space.l) {
          if let latest = shown {
            Text(latest.date.date(), format: .dateTime.day().month(.wide).year()).font(.caption)
            Text(weightLabel(latest.value)).font(.system(size: 64, weight: .medium)).tracking(-3).monospacedDigit()
              .minimumScaleFactor(0.6).lineLimit(1)
              .contentTransition(.numericText(value: latest.value))
              .animation(Motion.resolve(Motion.roll, reduceMotion), value: latest.value)
              .accessibilityLabel(bodyTrack ? "massa magra" : "força")
              .accessibilityValue(weightLabel(latest.value))
            if let first = window.first, first.date != latest.date {
              let weeks = max(1, Int((latest.date.date().timeIntervalSince(first.date.date()) / 604800).rounded()))
              let delta = latest.value - first.value
              // "+0,0" no verde de ganho dizia que algo subiu.
              if abs(delta) < 0.05 {
                Text("igual há \(weeks) sem")
                  .font(.subheadline).foregroundStyle(Color.mutedInk)
              } else {
                Text("\(delta.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1)))) kg em \(weeks) sem")
                  .font(.subheadline).monospacedDigit().foregroundStyle(accent.base)
              }
            }
          } else {
            Text(bodyTrack ? "sem % de gordura" : "sem séries").font(.title2)
          }
        }.frame(maxWidth: .infinity, minHeight: 150).padding(.top, 8)
        if !window.isEmpty {
          VStack(spacing: Space.m) {
            Picker("período", selection: $allHistory) {
              Text("8 sem").tag(false)
              Text("tudo").tag(true)
            }
            .pickerStyle(.segmented)
            Chart {
              ForEach(window, id: \.date) { point in
                LineMark(x: .value("dia", point.date.date()), y: .value("kg", point.value))
                  .interpolationMethod(.monotone)
                  .foregroundStyle(accent.base)
                PointMark(x: .value("dia", point.date.date()), y: .value("kg", point.value))
                  .symbolSize(30)
                  .foregroundStyle(accent.base)
              }
              if selectedDate != nil, let shown {
                RuleMark(x: .value("dia", shown.date.date()))
                  .foregroundStyle(Color.ink.opacity(0.2))
              }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxisLabel("kg")
            .chartXSelection(value: $selectedDate)
            .sensoryFeedback(.selection, trigger: selectedDate == nil ? nil : shown?.date)
            .frame(height: 220)
          }
        }
        HStack(alignment: .top, spacing: 8) {
          action("registrar", symbol: "square.and.pencil") {
            if bodyTrack { isAddingMeasurement = true } else { onWorkout() }
          }
          action("meta", symbol: "target") { isEditingGoal = true }
        }
        if !bodyTrack, let last = store.dashboard?.strengthGoal?.lastSession {
          VStack(alignment: .leading, spacing: 20) {
            HStack {
              Text("última sessão").font(.headline)
              Spacer()
              Text(Formatting.shortDate(last.date)).font(.caption)
            }
            HStack(alignment: .top) {
              sessionValue("reps", value: last.reps.map(String.init).joined(separator: ", "))
              sessionValue("carga", value: weightLabel(last.weightKg))
              sessionValue("volume", value: weightLabel(last.volumeKg))
            }
          }.padding(Space.xl).paperCard(radius: 28)
            .padding(Space.s)
            .background(Color.surfaceMuted, in: .rect(cornerRadius: Radius.concentric(28, padding: Space.s)))
        }
      }.padding(16)
    }.background(Color.canvas.ignoresSafeArea())
      .navigationTitle(bodyTrack ? "corpo" : (store.dashboard?.strengthSeries?.exerciseName.lowercased() ?? "força"))
      .toolbarTitleDisplayMode(.inline)
      .onChange(of: bodyTrack) { selectedDate = nil }
      .onChange(of: allHistory) { selectedDate = nil }
      .sheet(isPresented: $isAddingMeasurement) { MeasurementEditor(previous: store.dashboard.flatMap(latest(in:))) }
      .sheet(isPresented: $isEditingGoal) {
        if let dashboard = store.dashboard {
          // Uma meta são dois campos. Subir até o topo dava peso de tela nova
          // a um ajuste, e escondia de onde ele saiu.
          GoalEditor(kind: .strength, dashboard: dashboard)
            .presentationDetents([.medium, .large])
        }
      }
  }

  private func action(_ title: String, symbol: String, perform: @escaping () -> Void) -> some View {
    VStack(spacing: 8) {
      Button(action: perform) {
        Image(systemName: symbol)
          .offset(symbol == "square.and.pencil" ? CGSize(width: -0.5, height: -0.5) : .zero)
      }
      .accessibilityLabel(title).buttonStyle(.glass).controlSize(.large)
      Text(title).font(.caption2)
    }.frame(maxWidth: .infinity)
  }
  private func sessionValue(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).font(.caption2).foregroundStyle(Color.mutedInk)
      Text(value).font(.subheadline.weight(.medium)).monospacedDigit()
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
