import HenriqueCore
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

public enum AcademiaTab: String, Hashable, Sendable, CaseIterable {
  case hoje, semana, treino, progresso, apps

  /// "medidas" deixou de ser aba e virou uma seção de progresso. O nome antigo
  /// continua valendo na linha de comando para as capturas antigas abrirem.
  public init?(named name: String) {
    if name == "medidas" {
      self = .progresso
    } else {
      self.init(rawValue: name)
    }
  }
}

public enum AppSection: String, CaseIterable, Sendable {
  case academia, estudos, idiomas

  var label: String {
    switch self {
    case .academia: "academia"
    case .estudos: "estudos"
    case .idiomas: "idiomas"
    }
  }

  var symbol: String {
    switch self {
    case .academia: "dumbbell"
    case .estudos: "book"
    case .idiomas: "globe"
    }
  }
}

public struct RootView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage("henrique.accent") private var accent: Accent = .verde
  @AppStorage("henrique.app") private var section: AppSection = .academia
  @State private var tab: AcademiaTab
  @State private var estudosTab: EstudosTab
  @State private var idiomasTab: IdiomasTab
  @State private var appliedInitialSection = false
  @State private var showingApps = false
  @State private var sessionRequested = false
  @State private var sawSignIn = false
  private let foco: FocoStore
  private let store: AcademiaStore
  private let estudos: EstudosStore
  private let idiomas: IdiomasStore
  private let initialSection: AppSection?
  private let openSession: Bool
  private let openWrite: Bool

  public init(
    store: AcademiaStore, estudos: EstudosStore, idiomas: IdiomasStore, foco: FocoStore,
    initialSection: AppSection? = nil,
    initialTab: AcademiaTab = .hoje, initialEstudosTab: EstudosTab = .hoje,
    initialIdiomasTab: IdiomasTab = .rotina,
    openSession: Bool = false, openWrite: Bool = false
  ) {
    self.store = store
    self.estudos = estudos
    self.idiomas = idiomas
    self.initialSection = initialSection
    self.openSession = openSession
    self.openWrite = openWrite
    tab = initialTab
    estudosTab = initialEstudosTab
    idiomasTab = initialIdiomasTab
    self.foco = foco
  }

  public var body: some View {
    Group {
      if !store.sessionChecked {
        LaunchCurtain()
      } else if store.isSignedIn {
        switch section {
        case .academia:
          AcademiaTabs(
            accent: $accent, tab: $tab, showingApps: $showingApps,
            sessionRequested: $sessionRequested)
            .transition(.opacity)
        case .estudos:
          EstudosTabs(
            tab: $estudosTab, showingApps: $showingApps,
            openSession: openSession, openWrite: openWrite)
            .transition(.opacity)
        case .idiomas:
          IdiomasTabs(tab: $idiomasTab, showingApps: $showingApps)
            .transition(.opacity)
        }
      } else {
        SignInScreen(phase: store.phase).transition(.opacity).onAppear { sawSignIn = true }
      }
    }
    // Escalar a tela inteira na troca afastava o vidro das bordas do aparelho e
    // abria uma fresta branca da janela, com a barra de abas subindo junto. Um
    // fundo atrás do crossfade fecha o que sobra de branco entre os dois apps.
    .background(background.ignoresSafeArea())
    .animation(reduceMotion ? nil : Motion.crossfade, value: section)
    // As transições acima são ignoradas sem alguém animando o valor que troca a
    // tela. Sem estas duas linhas a abertura era um corte seco da cortina para
    // as abas, e o login entrava no app da mesma forma abrupta.
    .animation(reduceMotion ? nil : Motion.crossfade, value: store.sessionChecked)
    .animation(reduceMotion ? nil : Motion.crossfade, value: store.isSignedIn)
    // O painel mora aqui, e não dentro de cada app, para a troca não levar embora
    // a árvore em que ele vive antes de ele tocar a própria saída.
    .appSwitcher(current: section, isPresented: $showingApps) { section = $0 }
    #if os(iOS)
      .fullScreenCover(isPresented: .init(get: { foco.isShowingRun }, set: { foco.isShowingRun = $0 })) {
        FocoRunningScreen()
      }
    #endif
    .focoPresenceCheck(inCover: false)
    .onOpenURL { url in
      guard url.scheme == "henrique", url.host() == "sessao" else { return }
      section = .academia
      tab = .treino
      sessionRequested = true
    }
    .environment(store)
    .environment(estudos)
    .environment(idiomas)
    .environment(foco)
    .environment(\.accent, accent)
    .environment(\.locale, Locale(identifier: "pt_BR"))
    .preferredColorScheme(.light)
    .tint(accent.base)
    .onAppear {
      // O valor padrão do AppStorage só vale quando a chave ainda não existe,
      // então a seção pedida no lançamento precisa ser gravada por cima.
      guard !appliedInitialSection else { return }
      appliedInitialSection = true
      if let initialSection { section = initialSection }
    }
    .task {
      estudos.onUnauthorized = { store.expireSession() }
      idiomas.onUnauthorized = { store.expireSession() }
      await store.start()
    }
    .onChange(of: store.isSignedIn) {
      if !store.isSignedIn {
        estudos.reset()
        idiomas.reset()
      }
    }
    .onChange(of: scenePhase, initial: true) {
      switch scenePhase {
      case .active: foco.appBecameActive()
      case .background: foco.appWentBackground()
      default: break
      }
    }
    .task(id: isOffline) {
      // A faixa promete tentar de novo. O painel da academia é a leitura mais
      // barata; quando ela passa, a faixa some e o app atual recarrega.
      while isOffline, !Task.isCancelled {
        try? await Task.sleep(for: .seconds(15))
        guard !Task.isCancelled else { return }
        await store.load()
      }
    }
    .onChange(of: isOffline) { wasOffline, offline in
      guard wasOffline, !offline else { return }
      Task { await reloadAfterReconnect() }
    }
    .failureAlert(Bindable(store).banner) { await store.load() }
    .failureAlert(Bindable(estudos).banner) { await estudos.refresh() }
    .failureAlert(Bindable(idiomas).banner) { await idiomas.refresh() }
    .sensoryFeedback(.success, trigger: store.isSignedIn) { _, signedIn in signedIn && sawSignIn }
    .sensoryFeedback(.error, trigger: store.notice) { _, notice in notice != nil }
  }

  /// O primeiro quadro é o da tela de lançamento, que tem o `canvas`. O papel
  /// de estudos só entra depois, no crossfade da cortina para o app.
  private var background: Color {
    store.sessionChecked && section != .academia ? .studyPaper : .canvas
  }

  private var isOffline: Bool {
    store.isSignedIn && estudos.client.connectivity.isOffline
  }

  private func reloadAfterReconnect() async {
    await foco.sync()
    switch section {
    case .academia: await store.load()
    case .estudos: await estudos.refresh()
    case .idiomas: await idiomas.refresh()
    }
  }
}

/// O que fica na tela entre a tela de lançamento e a primeira tela do app,
/// enquanto a sessão é lida do chaveiro. A leitura leva milissegundos, e um
/// spinner que pisca por dois quadros é pior do que nenhum, então ele só entra
/// se a espera passar de meio segundo. O fundo é o da raiz, que enquanto a
/// cortina está de pé é o mesmo da tela de lançamento.
private struct LaunchCurtain: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var slow = false

  var body: some View {
    Color.clear
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .overlay {
        if slow {
          ProgressView().controlSize(.large).transition(.opacity)
        }
      }
      .animation(Motion.resolve(Motion.crossfade, reduceMotion), value: slow)
      .task {
        try? await Task.sleep(for: .milliseconds(500))
        slow = true
      }
  }
}

struct AcademiaTabs: View {
  @Environment(AcademiaStore.self) private var store
  @State private var showingSetup = false
  @State private var showingStreak = false
  @State private var stage = InsigniaStage()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Binding var accent: Accent
  @Binding var tab: AcademiaTab
  @Binding var showingApps: Bool
  @Binding var sessionRequested: Bool

  var body: some View {
    TabView(selection: appSwitcherSelection($tab, isPresented: $showingApps, bubble: .apps)) {
      Tab("hoje", systemImage: "house", value: AcademiaTab.hoje) {
        shell {
          OverviewScreen(
            onWorkout: {
              tab = .treino
              sessionRequested = true
            },
            onPlan: { tab = .semana },
            onDay: { date in
              Task { await store.select(date: date) }
              tab = .treino
            })
        }
      }
      Tab("plano", systemImage: "list.clipboard", value: AcademiaTab.semana) {
        shell {
          WeekScreen { weekday in
            let delta = (weekday - store.selectedDate.weekday() + 7) % 7
            Task { await store.select(date: store.selectedDate.adding(days: delta)) }
            tab = .treino
          }
        }
      }
      Tab("treino", systemImage: "dumbbell", value: AcademiaTab.treino) {
        shell {
          TodayScreen(
            sessionRequested: $sessionRequested,
            onPlan: { tab = .semana }, onProgress: { tab = .progresso })
        }
      }
      Tab("progresso", systemImage: "chart.xyaxis.line", value: AcademiaTab.progresso) {
        shell { ProgressScreen(onWorkout: { tab = .treino }) }
      }
      // A bolha é o botão do painel, então ela mostra o x enquanto o painel
      // está aberto, do mesmo jeito que um menu marca que está aberto.
      Tab(
        "apps", systemImage: showingApps ? "xmark" : "square.grid.2x2",
        value: AcademiaTab.apps, role: appHubTabRole
      ) {
        Color.clear
      }
    }
    .focoAccessory()
    .overlay { InsigniaOverlay(stage: stage, onClose: closeInsignia) }
    .task(id: store.dashboard?.date) { await store.refreshInsignia() }
    .task(id: store.pendingInsignia) {
      guard let pending = store.pendingInsignia, stage.show == nil else { return }
      // A chama do topo precisa estar na tela antes de sair voando dela.
      try? await Task.sleep(for: .seconds(0.6))
      guard !Task.isCancelled else { return }
      stage.show = InsigniaShow(
        tier: pending.tier, months: store.tenure?.months ?? pending.tier.rawValue,
        origin: stage.flameFrame, wasLit: store.dashboard?.hasAttended(on: .today) ?? false,
        opened: .now)
      store.insigniaOpened(pending)
    }
    .sheet(isPresented: $showingSetup) { SetupScreen() }
    .sheet(isPresented: $showingStreak) {
      if let data = store.dashboard {
        StreakScreen(dashboard: data)
      }
    }
    .onChange(of: store.dashboard?.onboardingCompleted, initial: true) {
      if store.dashboard?.onboardingCompleted == false { showingSetup = true }
    }
    .onAppear { if tab == .apps { tab = .hoje; showingApps = true } }
  }

  private func closeInsignia() {
    guard var show = stage.show, show.closed == nil else { return }
    show.closed = .now
    stage.show = show
    Task {
      try? await Task.sleep(for: .seconds(InsigniaBeat.closing(reduceMotion: reduceMotion)))
      stage.show = nil
    }
  }

  private func shell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    NavigationStack {
      content()
        .offlineInset()
        .keyboardDone()
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(Color.canvas.ignoresSafeArea())
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .navigationLeading) {
            if let data = store.dashboard {
              StreakCounter(
                count: data.streak(.attendance), isLit: data.hasAttended(on: .today),
                stage: stage
              ) { showingStreak = true }
            }
          }.sharedBackgroundVisibility(.hidden)
          ToolbarItem(placement: .primaryAction) {
            Menu {
              Button("primeiros passos", systemImage: "slider.horizontal.3") { showingSetup = true }
              Picker("cor", selection: $accent) {
                ForEach(Accent.allCases) { color in
                  Label { Text(color.label) } icon: { swatch(color.base) }
                    .tag(color)
                }
              }
              .pickerStyle(.palette)
            } label: { Label("configurar", systemImage: "gearshape") }
            .sensoryFeedback(.selection, trigger: accent)
          }
          ToolbarItem(placement: .primaryAction) { AccountMenu() }
        }
    }
  }
}

/// O menu da conta das três casas. Sair esbarra na fila de séries que não
/// subiram, e a pergunta precisa aparecer em qualquer app em que se toque
/// "sair", senão o menu fecha e nada acontece.
struct AccountMenu: View {
  @Environment(AcademiaStore.self) private var store
  @State private var confirmingSignOut = false

  var body: some View {
    Menu {
      Button("sair", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
        Task { confirmingSignOut = !(await store.signOut()) }
      }
    } label: { Image(systemName: "person.crop.circle") }
    .accessibilityLabel("sua conta")
    .confirmationDialog(unsentTitle, isPresented: $confirmingSignOut, titleVisibility: .visible) {
      Button("sair e perder", role: .destructive) {
        Task { await store.signOut(discardingUnsent: true) }
      }
      Button("cancelar", role: .cancel) {}
    }
  }

  private var unsentTitle: String {
    let count = store.unsentCount
    return count == 1 ? "1 série ainda não subiu" : "\(count) séries ainda não subiram"
  }
}

/// A bolinha da cor no menu. O menu pinta imagem de molde com a cor do texto,
/// então a cor vai gravada na própria imagem.
private func swatch(_ color: Color) -> Image {
  #if canImport(UIKit)
    let symbol = UIImage(systemName: "circle.fill") ?? UIImage()
    return Image(uiImage: symbol.withTintColor(UIColor(color), renderingMode: .alwaysOriginal))
  #else
    return Image(systemName: "circle.fill")
  #endif
}

/// A bolha redonda separada da barra é o papel `prominent`, novo no iOS 27. No
/// iOS 26 o papel de busca é o que desenha a mesma bolha.
var appHubTabRole: TabRole {
  if #available(iOS 27, macOS 27, *) { .prominent } else { .search }
}

/// A bolha não leva a lugar nenhum, ela abre o painel de apps. Escolher a aba
/// dela vira abrir o painel e a seleção fica onde estava.
@MainActor func appSwitcherSelection<Tab: Hashable & Sendable>(
  _ tab: Binding<Tab>, isPresented: Binding<Bool>, bubble: Tab
) -> Binding<Tab> {
  Binding(
    get: { tab.wrappedValue },
    set: { picked in
      if picked == bubble {
        isPresented.wrappedValue = true
      } else {
        tab.wrappedValue = picked
      }
    })
}

extension View {
  /// O painel de apps que a bolha abre. Fica na raiz, acima dos dois apps, e
  /// veste a pele do app atual, então `current` escolhe o estilo e marca a linha.
  func appSwitcher(
    current: AppSection, isPresented: Binding<Bool>,
    onSelect: @escaping @MainActor (AppSection) -> Void
  ) -> some View {
    modifier(AppSwitcher(current: current, isPresented: isPresented, onSelect: onSelect))
  }
}

private struct AppSwitcher: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(FocoStore.self) private var foco
  let current: AppSection
  @Binding var isPresented: Bool
  let onSelect: @MainActor (AppSection) -> Void

  func body(content: Content) -> some View {
    content
      // Véu e painel entram como camadas separadas para o véu só aparecer e o
      // painel crescer do canto da bolha.
      .overlay {
        if isPresented {
          Color.ink.opacity(0.12)
            .ignoresSafeArea()
            .contentShape(.rect)
            .onTapGesture { isPresented = false }
            .transition(.opacity)
        }
      }
      .overlay(alignment: .bottomTrailing) {
        if isPresented {
          AppSwitcherPanel(current: current) { app in
            isPresented = false
            if app != current { onSelect(app) }
          }
          .accessibilityAddTraits(.isModal)
          .accessibilityAction(.escape) { isPresented = false }
          .padding(.trailing, 14)
          .padding(.bottom, 72 + accessoryLift)
          .transition(
            reduceMotion
              ? .opacity
              : .scale(scale: Motion.panelScale, anchor: .bottomTrailing).combined(with: .opacity))
        }
      }
      .animation(Motion.resolve(Motion.expand, reduceMotion), value: isPresented)
      .sensoryFeedback(.selection, trigger: current)
  }

  /// A faixa do foco sobe a barra de abas, e a bolha junto com ela.
  private var accessoryLift: CGFloat {
    guard foco.isRunning else { return 0 }
    if #available(iOS 26.1, macOS 26.1, *) { return 56 }
    return 0
  }
}

private struct AppSwitcherPanel: View {
  let current: AppSection
  let onSelect: @MainActor (AppSection) -> Void

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, app in
        if index > 0 { Divider().padding(.leading, AppSwitcherRow.textInset) }
        AppSwitcherRow(app: app, style: current, isCurrent: app == current) { onSelect(app) }
      }
    }
    .frame(width: 228)
    .glassEffect(in: .rect(cornerRadius: 24))
    .shadow(color: Color.ink.opacity(0.18), radius: 22, y: 10)
    .tint(switcherTint(current))
  }
}

private func switcherTint(_ current: AppSection) -> Color? {
  switch current {
  case .estudos: .studyBlue
  case .idiomas: .idiomasTeal
  case .academia: nil
  }
}

private struct AppSwitcherRow: View {
  @Environment(\.accent) private var accent
  let app: AppSection
  let style: AppSection
  let isCurrent: Bool
  let action: @MainActor () -> Void

  static let iconWidth: CGFloat = 24
  /// Onde o nome começa, que é onde o divisor entre linhas começa.
  static let textInset = Space.l + iconWidth + Space.m

  private var tint: Color {
    switch style {
    case .estudos: .studyBlue
    case .idiomas: .idiomasTeal
    case .academia: accent.base
    }
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: Space.m) {
        Image(systemName: app.symbol).font(.system(size: 17)).frame(width: Self.iconWidth, height: 20)
        Text(app.label).font(.body.weight(.medium))
        Spacer(minLength: 0)
        if isCurrent {
          Image(systemName: "checkmark")
            .font(.footnote.weight(.semibold))
            .accessibilityLabel("app atual")
        }
      }
      .foregroundStyle(isCurrent ? tint : Color.ink)
      .padding(.horizontal, Space.l)
      .padding(.vertical, 14)
      .contentShape(.rect)
    }
    .buttonStyle(StudyPressStyle())
    .accessibilityAddTraits(isCurrent ? .isSelected : [])
  }
}

/// A home responde uma pergunta só, o que eu faço agora, e depois desce para o
/// diagnóstico. A ordem é essa: ação, o que vem a seguir, o que mudou, quanto do
/// plano da semana saiu, quais músculos ficaram sem estímulo. Presença e
/// constância moram em "progresso".
struct OverviewScreen: View {
  @Environment(AcademiaStore.self) private var store
  let onWorkout: () -> Void
  let onPlan: () -> Void
  let onDay: (CalendarDate) -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Space.xxl) {
        DateHeader(date: store.selectedDate)
        if let data = store.dashboard {
          DayCard(
            workout: data.workout, choices: DaySwapChoices(data), onWorkout: onWorkout,
            onPlan: onPlan, onSwap: { await store.swapDay(workoutTemplateId: $0) })
            .staggeredEntrance(index: 0, isReady: true)
          NextDaysStrip(
            days: plannedDays(from: data.date, schedule: data.schedule), onPlan: onPlan,
            onDay: onDay)
            .staggeredEntrance(index: 1, isReady: true)
          if let records = data.records, !records.isEmpty {
            RecordsCard(records: records, today: data.date)
              .staggeredEntrance(index: 2, isReady: true)
          }
          if let week = store.trainingWeek(today: data.date), week.planned > 0 {
            WeeklyAdherenceCard(week: week, today: data.date, onPlan: onPlan)
              .staggeredEntrance(index: 3, isReady: true)
          }
          if let load = data.muscleLoad, load.contains(where: { $0.setsMonth > 0 }) {
            MuscleMap(load: load, today: data.date, onPlan: onPlan)
              .staggeredEntrance(index: 4, isReady: true)
          }
        } else if store.phase.awaitsDashboard {
          OverviewSkeleton().transition(.opacity)
        }
      }.padding(Space.l).padding(.bottom, Space.page)
    }
    .refreshable { await store.load() }
    .overlay {
      TodayPlaceholder(phase: store.phase, isEmpty: store.dashboard == nil) { EmptyView() }
    }
  }
}

/// A forma da home sem dados, embaixo da data, que já é a de verdade: cartão do
/// dia, faixa dos próximos dias e um cartão de diagnóstico.
private struct OverviewSkeleton: View {
  var body: some View {
    VStack(alignment: .leading, spacing: Space.xxl) {
      RoundedRectangle(cornerRadius: Radius.card).fill(Color.surfaceMuted).frame(height: 220)
      HStack(spacing: Space.s) {
        ForEach(0..<3, id: \.self) { _ in
          RoundedRectangle(cornerRadius: Radius.tile).fill(Color.surfaceMuted)
            .frame(width: 104, height: 96)
        }
      }
      RoundedRectangle(cornerRadius: Radius.card).fill(Color.surfaceMuted).frame(height: 160)
    }
    .accessibilityHidden(true)
  }
}

extension AcademiaStore.Phase {
  /// Ainda vem painel: carregando, ou sem rede com a faixa do topo prometendo
  /// tentar de novo. Nos dois casos a tela fica no esqueleto.
  var awaitsDashboard: Bool {
    switch self {
    case .loading: true
    case .failed(let message): message == APIError.offlineMessage
    case .idle, .ready: false
    }
  }
}

/// O aviso cobre a tela enquanto não há painel. A troca para o conteúdo é só
/// opacidade, então ele mesmo guarda o `isEmpty` que a anima nos dois usos.
struct TodayPlaceholder<Skeleton: View>: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let phase: AcademiaStore.Phase
  let isEmpty: Bool
  @ViewBuilder let skeleton: Skeleton

  var body: some View {
    ZStack {
      if isEmpty {
        if phase.awaitsDashboard {
          skeleton.transition(.opacity)
        } else if case .failed(let message) = phase {
          LoadFailure(message: message) { await store.load() }
            .transition(.opacity)
        }
      }
    }
    .animation(Motion.resolve(Motion.crossfade, reduceMotion), value: isEmpty)
  }
}

extension TodayPlaceholder where Skeleton == TodaySkeleton {
  init(phase: AcademiaStore.Phase, isEmpty: Bool) {
    self.init(phase: phase, isEmpty: isEmpty) { TodaySkeleton() }
  }
}

extension View {
  /// O alerta de uma falha que não é falta de rede, que já mora na faixa do
  /// topo e voltaria a cada tela que tentasse carregar. O título é fixo e a
  /// frase do erro vai no corpo, com uma saída para recarregar.
  func failureAlert(
    _ banner: Binding<String?>, reload: @escaping @MainActor () async -> Void
  ) -> some View {
    modifier(FailureAlert(banner: banner, reload: reload))
  }
}

private struct FailureAlert: ViewModifier {
  @Binding var banner: String?
  let reload: @MainActor () async -> Void

  private var message: String? {
    banner == APIError.offlineMessage ? nil : banner
  }

  func body(content: Content) -> some View {
    content.alert(
      "não deu certo",
      isPresented: Binding(get: { message != nil }, set: { if !$0 { banner = nil } }),
      presenting: message
    ) { message in
      // Com a sessão vencida o app já voltou para o login e não há o que recarregar.
      if message != APIError.unauthorized.message {
        Button("recarregar") { Task { await reload() } }
      }
      Button("ok", role: .cancel) {}
    } message: { message in
      Text(message)
    }
  }
}

extension ToolbarItemPlacement {
  static var navigationLeading: ToolbarItemPlacement {
    #if os(iOS)
    .topBarLeading
    #else
    .navigation
    #endif
  }
}
