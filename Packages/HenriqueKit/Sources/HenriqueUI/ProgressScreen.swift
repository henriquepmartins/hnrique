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
  @State private var editing: GoalKind?
  var onWorkout: () -> Void = {}

  var body: some View {
    ScrollView {
      VStack(spacing: Space.xxl) {
        if let dashboard = store.dashboard {
          let streakGoals = dashboard.streakGoals ?? []
          HStack {
            Text("metas").font(.title2.weight(.medium)).tracking(-0.8)
            Spacer()
            IconButton(title: "nova meta", systemImage: "plus", glass: true) {
              editing = newGoalKind(in: dashboard)
            }
            .disabled(dashboard.exerciseCatalog.isEmpty)
          }
          .subtleEntrance()
          if let goal = dashboard.strengthGoal {
            GoalCard(
              exerciseName: goal.exerciseName, targetValue: goal.targetValue,
              projection: dashboard.projection)
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
                target: dashboard.strengthGoal?.targetValue)
            }
            .buttonStyle(StudyPressStyle())
            .foregroundStyle(Color.ink)
            .subtleEntrance()
            VolumeChart(points: series.points)
              .subtleEntrance()
          } else {
            Image(systemName: "chart.xyaxis.line")
              .font(.system(size: 44)).foregroundStyle(Color.mutedInk)
              .padding(.vertical, 40)
              .accessibilityLabel("sem histórico")
              .subtleEntrance()
          }
          MeasurementsLink(latest: latest(in: dashboard))
            .subtleEntrance()
        }
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 40)
    }
    .refreshable { await store.load() }
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
    if dashboard.strengthGoal == nil { return .strength }
    return StreakKind.allCases.first { dashboard.goal($0) == nil }.map(GoalKind.init) ?? .strength
  }
}

struct StreakGoalCard: View {
  @Environment(\.accent) private var accent
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let kind: GoalKind
  let current: Int
  let target: Int
  let action: () -> Void

  private var progress: Double { min(1, Double(current) / Double(max(target, 1))) }

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: Space.m) {
        Label { Text(kind.face.label) } icon: { Image(systemName: kind.face.systemImage).frame(width: 24) }
          .font(.headline)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text("\(current)")
            .font(.largeTitle.weight(.semibold))
            .foregroundStyle(accent.base)
          Text("/\(target)")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .monospacedDigit()
        ProgressView(value: progress)
          .tint(accent.signal)
          .animation(reduceMotion ? nil : Motion.crossfade, value: progress)
        if current >= target {
          Text("meta batida").font(.footnote).foregroundStyle(.secondary)
        }
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
    .accessibilityAddTraits(.isButton)
  }
}

extension Dashboard {
  /// A série de força da tela: a da meta quando existe, senão a do exercício
  /// que o servidor destaca. Nula quando nenhuma das duas tem ponto.
  fileprivate var strengthSeries: (exerciseName: String, points: [ProgressPoint])? {
    if let goal = strengthGoal, !progress.isEmpty { return (goal.exerciseName, progress) }
    if let featured = featuredProgress, !featured.points.isEmpty {
      return (featured.exerciseName, featured.points)
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
  let exerciseName: String
  let targetValue: Double
  let projection: Projection?

  var body: some View {
    VStack(alignment: .leading, spacing: Space.m) {
      Label { Text(exerciseName) } icon: { Image(systemName: "target").frame(width: 24) }
        .font(.headline)
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(weightLabel(projection?.current ?? 0))
          .font(.largeTitle.weight(.semibold))
          .monospacedDigit()
          .foregroundStyle(accent.base)
        Text("de \(weightLabel(targetValue))")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      if let projection {
        ProgressView(value: min(projection.current / max(projection.target, 1), 1))
          .tint(accent.signal)
        if let sentence = projectionSentence(projection) {
          Text(sentence).font(.footnote).foregroundStyle(.secondary)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Space.xl)
    .background(accent.pale, in: .rect(cornerRadius: Radius.card))
  }

  private func projectionSentence(_ projection: Projection) -> String? {
    guard let weeks = projection.weeksRemaining else { return nil }
    if weeks == 0 { return "meta batida" }
    return "em \(weeks) \(weeks == 1 ? "semana" : "semanas")"
  }
}

struct OneRepMaxChart: View {
  @Environment(\.accent) private var accent
  let title: String
  let points: [ProgressPoint]
  let target: Double?

  var body: some View {
    ChartCard(title: title.lowercased(), opens: true) {
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
  let points: [ProgressPoint]

  var body: some View {
    ChartCard(title: "volume") {
      Chart(points) { point in
        AreaMark(x: .value("dia", point.date.date()), y: .value("volume", point.volumeKg))
          .interpolationMethod(.monotone)
          .foregroundStyle(LinearGradient(colors: [accent.mint.opacity(0.8), accent.mint.opacity(0.08)], startPoint: .top, endPoint: .bottom))
        LineMark(x: .value("dia", point.date.date()), y: .value("volume", point.volumeKg))
          .interpolationMethod(.monotone).foregroundStyle(accent.base)
      }
      .chartYAxisLabel("kg")
    }
  }
}

struct ChartCard<Content: View>: View {
  let title: String
  /// O cartão é o link para os detalhes, e o chevron é o que diz isso.
  var opens = false
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: Space.m) {
      HStack {
        Text(title).font(.headline)
        Spacer(minLength: 8)
        if opens {
          Image(systemName: "chevron.right")
            .font(.subheadline.weight(.semibold)).foregroundStyle(Color.mutedInk)
        }
      }
      content
        .frame(height: 220)
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
            ForEach(GoalKind.allCases) { Text($0.face.label).tag($0) }
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
      .navigationTitle("meta")
      .toolbarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("cancelar") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("salvar") { save() }.disabled(isSaving || !canSave)
        }
      }
    }
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
      if saved { dismiss() }
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
  @State private var bodyTrack = false
  @State private var allHistory = false

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

  @State private var isAddingMeasurement = false
  @State private var isEditingGoal = false
  var onWorkout: () -> Void = {}

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Space.xxl) {
        Picker("Métrica em foco", selection: $bodyTrack) {
          Text("força").tag(false)
          Text("corpo").tag(true)
        }.pickerStyle(.segmented)
        VStack(spacing: Space.l) {
          if let latest = window.last {
            Text(latest.date.date(), format: .dateTime.day().month(.wide).year()).font(.caption)
            Text(weightLabel(latest.value)).font(.system(size: 64, weight: .medium)).tracking(-3).monospacedDigit()
              .minimumScaleFactor(0.6).lineLimit(1)
              .accessibilityLabel(bodyTrack ? "massa magra" : "força")
              .accessibilityValue(weightLabel(latest.value))
            if let first = window.first, first.date != latest.date {
              let weeks = max(1, Int((latest.date.date().timeIntervalSince(first.date.date()) / 604800).rounded()))
              Text("\((latest.value - first.value).formatted(.number.sign(strategy: .always()).precision(.fractionLength(1)))) kg em \(weeks) sem")
                .font(.subheadline).monospacedDigit().foregroundStyle(accent.base)
            }
          } else {
            Text(bodyTrack ? "sem % de gordura" : "sem séries").font(.title2)
          }
        }.frame(maxWidth: .infinity, minHeight: 230).padding(.vertical, 24)
        HStack(alignment: .top, spacing: 8) {
          action("registrar", symbol: "square.and.pencil") {
            if bodyTrack { isAddingMeasurement = true } else { onWorkout() }
          }
          action(allHistory ? "tudo" : "8 sem", symbol: "calendar") { allHistory.toggle() }
          action("meta", symbol: "target") { isEditingGoal = true }
        }
        if !bodyTrack, let last = store.dashboard?.strengthGoal?.lastSession {
          VStack(alignment: .leading, spacing: 20) {
            HStack {
              Text("última sessão").font(.headline)
              Spacer()
              Text(last.date.date(), format: .dateTime.day().month(.abbreviated)).font(.caption)
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
      .sheet(isPresented: $isAddingMeasurement) { MeasurementEditor(previous: store.dashboard?.measurements.first) }
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
