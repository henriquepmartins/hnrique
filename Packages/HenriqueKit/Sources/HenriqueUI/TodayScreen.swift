import HenriqueCore
import SwiftUI

public struct TodayScreen: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var compact = false
  @State private var openIds: Set<String> = []
  @State private var notch: CGFloat = 0.5
  @State private var enteredDates: Set<String> = []
  @State private var showingSession = false
  @State private var editing: WeekPlanItem?
  @Namespace private var sessionSource
  @Binding var sessionRequested: Bool
  let onPlan: () -> Void
  let onProgress: () -> Void

  init(
    sessionRequested: Binding<Bool> = .constant(false),
    onPlan: @escaping () -> Void = {}, onProgress: @escaping () -> Void = {}
  ) {
    _sessionRequested = sessionRequested
    self.onPlan = onPlan
    self.onProgress = onProgress
  }

  public var body: some View {
    ScrollView {
      VStack(spacing: Space.page) {
        VStack(spacing: Space.m) {
          DayStrip(selected: store.selectedDate, notch: $notch)
            .staggeredEntrance(index: 0, isReady: hasData)
          if let rest = store.rest, rest.key.date == store.selectedDate, !showingSession {
            RestChip(rest: rest) { showingSession = true }
              .frame(maxWidth: .infinity, alignment: .leading)
              .transition(.opacity)
          }
          SyncStatusLine()
          WorkoutHero(
            workout: store.dashboard?.workout, date: store.selectedDate,
            finished: store.dashboard?.workout.map { store.finishedAt($0.id, on: store.selectedDate) != nil } ?? false
              || stoppedTiming != nil,
            duration: stoppedTiming.map { $0.elapsed(at: .now) },
            tone: store.dashboard?.workout.flatMap { workout in
              store.weekPlan.first { $0.id == workout.id }?.tone
            },
            notch: notch,
            sessionSource: sessionSource,
            onStart: { showingSession = true }
          )
          .animation(reduceMotion ? Motion.plain : Motion.tap) { view in
            view.opacity(fresh ? 1 : 0.5)
          }
          // Enquanto o painel é de outro dia, abrir a sessão daria um treino
          // que o store recusa gravar, porque `record` compara com a data
          // escolhida. O hero já aparece apagado, então também não responde.
          .disabled(!fresh)
          .overlay {
            if store.dashboard != nil && !fresh {
              ProgressView()
                .padding(12)
                .background(.regularMaterial, in: .capsule)
            }
          }
          // O hero fica montado desde o primeiro quadro, com "descanso" no
          // lugar do nome do treino, então sem isto ele apareceria pronto por
          // baixo do esqueleto e só o resto da tela entraria. Ele é a primeira
          // coisa que o dono olha, então é ele que abre a cascata.
          .staggeredEntrance(index: 1, isReady: hasData)
        }
        if let data = store.dashboard, let workout = data.workout {
          VStack(spacing: Space.m) {
            HStack {
              Text("exercícios").font(.title2.weight(.medium)).tracking(-0.8)
              Spacer()
              Picker("Modo de exibição", selection: $compact) {
                Image(systemName: "list.bullet").tag(true).accessibilityLabel("lista")
                Image(systemName: "rectangle.grid.1x2").tag(false).accessibilityLabel("cartões")
              }.pickerStyle(.segmented).frame(width: 96)
              .onChange(of: compact) { openIds = defaultOpenIds() }
            }
            HStack {
              IconButton(title: "progresso", systemImage: "chart.xyaxis.line", glass: true, nudge: CGSize(width: 0.5, height: -0.5), action: onProgress)
              Spacer()
              IconButton(title: "editar plano", systemImage: "square.and.pencil", glass: true, nudge: CGSize(width: -0.5, height: -0.75)) {
                editPlan(workoutId: workout.id)
              }
            }
            .firstEntrance(index: 2, settled: enteredDates.contains(data.date.iso))
            ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { index, exercise in
              ExerciseCard(exercise: exercise, date: data.date, templateId: workout.id, isOpen: openIds.contains(exercise.id)) {
                withAnimation(reduceMotion ? nil : Motion.expand) {
                  if !openIds.insert(exercise.id).inserted { openIds.remove(exercise.id) }
                }
              }
              .firstEntrance(index: index + 3, settled: enteredDates.contains(data.date.iso))
            }
          }.id(store.dashboard?.date).disabled(!fresh)
          .task(id: data.date.iso) {
            guard !enteredDates.contains(data.date.iso) else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            enteredDates.insert(data.date.iso)
          }
        }
      }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 32)
    }
    .scrollBounceBehavior(.basedOnSize)
    .refreshable { await store.load() }
    .overlay { TodayPlaceholder(phase: store.phase, isEmpty: store.dashboard == nil) }
    .onChange(of: store.dashboard?.workout?.id, initial: true) {
      openIds = defaultOpenIds()
    }
    .onChange(of: sessionRequested, initial: true) {
      guard sessionRequested else { return }
      sessionRequested = false
      if store.dashboard?.workout != nil { showingSession = true }
    }
    #if os(iOS)
      .fullScreenCover(isPresented: $showingSession) {
        WorkoutSessionScreen(onClose: { showingSession = false })
          .navigationTransition(.zoom(sourceID: "sessao", in: sessionSource))
      }
    #endif
    .sheet(item: $editing) { item in
      WorkoutEditor(
        item: item, weekdays: Set(item.weekdays), tone: item.tone,
        catalog: store.dashboard?.exerciseCatalog ?? [], startingAt: .exercicios)
    }
    .animation(Motion.tap, value: store.rest == nil)
  }

  /// O treino do dia abre direto no editor, nos exercícios. Um treino que só
  /// existe na sessão, fora do plano, cai na aba do plano.
  private func editPlan(workoutId: String) {
    if let item = store.weekPlan.first(where: { $0.id == workoutId }) {
      editing = item
    } else {
      onPlan()
    }
  }

  /// O relógio da sessão do dia, só quando já parou: no "encerrar" ou na
  /// última série valendo. É o tempo real que substitui a estimativa no hero.
  private var stoppedTiming: WorkoutSessionTiming? {
    guard let workout = store.dashboard?.workout else { return nil }
    let timing = WorkoutSessionTiming(
      workout, anchor: store.startedAt(workout.id, on: store.selectedDate),
      finishedAt: store.finishedAt(workout.id, on: store.selectedDate))
    return timing?.finishedAt == nil ? nil : timing
  }

  /// O painel na tela é do dia escolhido, e não de um anterior ainda na troca.
  private var fresh: Bool { store.dashboard?.date == store.selectedDate }

  /// O primeiro painel chegou. É o que solta a cascata de abertura, depois do
  /// esqueleto sair.
  private var hasData: Bool { store.dashboard != nil }

  /// Quais cartões nascem abertos. "cartões" é o modo que mostra as séries, e o
  /// seletor já começa nele, então abrir só depois que o dedo troca o modo faz
  /// o primeiro desenho contradizer o que o seletor diz.
  private func defaultOpenIds() -> Set<String> {
    guard !compact, let exercises = store.dashboard?.workout?.exercises else { return [] }
    return Set(exercises.map(\.id))
  }
}

/// O aviso cobre a tela enquanto não há painel. A troca para o conteúdo é só
/// opacidade, então ele mesmo guarda o `isEmpty` que a anima nos dois usos.
struct TodayPlaceholder: View {
  let phase: AcademiaStore.Phase
  let isEmpty: Bool

  var body: some View {
    ZStack {
      if isEmpty {
        switch phase {
        case .loading:
          TodaySkeleton().transition(.opacity)
        case .failed(let message):
          ContentUnavailableView(
            "não carregou", systemImage: "wifi.exclamationmark", description: Text(message))
            .transition(.opacity)
        case .idle, .ready:
          EmptyView()
        }
      }
    }
    .animation(Motion.crossfade, value: isEmpty)
  }
}

/// Esqueleto da primeira pintura: hero e fileiras no formato do conteúdo. O
/// spinner era a primeira coisa que o dono via; o esqueleto ocupa o mesmo
/// espaço do que vai entrar, então a troca é só opacidade.
struct TodaySkeleton: View {
  var body: some View {
    // Os mesmos raios do hero e do ExerciseCard que vão ocupar o lugar.
    VStack(spacing: Space.m) {
      RoundedRectangle(cornerRadius: 32).fill(Color.surfaceMuted).frame(height: 408)
      ForEach(0..<3) { _ in
        RoundedRectangle(cornerRadius: 30).fill(Color.surfaceMuted).frame(height: 92)
      }
    }
    .padding(.horizontal, 16).padding(.top, 12)
    .redacted(reason: .placeholder)
    .accessibilityHidden(true)
  }
}

struct HeroNotch: Shape {
  var center: CGFloat
  var animatableData: CGFloat {
    get { center }
    set { center = newValue }
  }
  func path(in rect: CGRect) -> Path {
    let x = rect.width * center
    var path = Path()
    path.move(to: .zero)
    path.addLine(to: CGPoint(x: x - 50, y: 0))
    path.addCurve(to: CGPoint(x: x - 4, y: 24), control1: CGPoint(x: x - 25, y: 0), control2: CGPoint(x: x - 18, y: 24))
    path.addLine(to: CGPoint(x: x + 4, y: 24))
    path.addCurve(to: CGPoint(x: x + 50, y: 0), control1: CGPoint(x: x + 18, y: 24), control2: CGPoint(x: x + 25, y: 0))
    path.addLine(to: CGPoint(x: rect.width, y: 0))
    path.closeSubpath()
    return path
  }
}
