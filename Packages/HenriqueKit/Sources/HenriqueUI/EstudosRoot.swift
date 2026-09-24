import SwiftUI

public enum EstudosTab: String, Hashable, Sendable, CaseIterable {
  case hoje, materias, entregas, revisar, apps

  /// "cadernos" deixou de ser aba e virou uma seção da matéria. O nome antigo
  /// continua valendo na linha de comando para as capturas antigas abrirem.
  public init?(named name: String) {
    if name == "cadernos" {
      self = .materias
    } else {
      self.init(rawValue: name)
    }
  }
}

struct EstudosTabs: View {
  @Environment(EstudosStore.self) private var store
  @Environment(AcademiaStore.self) private var academia
  @Binding var tab: EstudosTab
  @Binding var accent: Accent
  @State private var showingSession: Bool
  @State private var showingWrite: Bool
  @Binding var showingApps: Bool

  init(
    tab: Binding<EstudosTab>, accent: Binding<Accent>, showingApps: Binding<Bool>,
    openSession: Bool = false, openWrite: Bool = false
  ) {
    _tab = tab
    _accent = accent
    _showingApps = showingApps
    showingSession = openSession || FocusSessionScreen.hasActiveBlock
    showingWrite = openWrite
  }

  var body: some View {
    TabView(selection: appSwitcherSelection($tab, isPresented: $showingApps, bubble: .apps)) {
      Tab("hoje", systemImage: "house", value: EstudosTab.hoje) {
        shell {
          StudyTodayScreen(
            onSession: { showingSession = true },
            onAssignments: { tab = .entregas },
            onReview: { tab = .revisar })
        }
      }
      Tab("matérias", systemImage: "book", value: EstudosTab.materias) {
        shell { StudySubjectsScreen() }
      }
      Tab("entregas", systemImage: "calendar", value: EstudosTab.entregas) {
        shell { StudyAssignmentsScreen() }
      }
      Tab("revisar", systemImage: "rectangle.on.rectangle", value: EstudosTab.revisar) {
        shell { StudyReviewScreen(onWrite: { showingWrite = true }) }
      }
      // A bolha é o botão do painel, então ela mostra o x enquanto o painel
      // está aberto.
      Tab(
        "apps", systemImage: showingApps ? "xmark" : "square.grid.2x2",
        value: EstudosTab.apps, role: appHubTabRole
      ) {
        Color.clear
      }
    }
    .focoAccessory()
    .onAppear { if tab == .apps { tab = .hoje; showingApps = true } }
    #if os(iOS)
      .fullScreenCover(isPresented: $showingSession) {
        FocusSessionScreen(onReview: { tab = .revisar })
      }
    #endif
    .sheet(isPresented: $showingWrite) { WriteScreen() }
    // A folha e o cover leem o tint de fora dos próprios modificadores, então o
    // azul precisa envolvê-los para não sair verde da academia lá dentro.
    .tint(.studyBlue)
    .task { await store.prefetchAll() }
  }

  private func shell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    NavigationStack {
      content()
        .offlineInset()
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(Color.studyPaper.ignoresSafeArea())
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .primaryAction) {
            Menu {
              Button("escrever", systemImage: "square.and.pencil") { showingWrite = true }
              Picker("cor", selection: $accent) {
                ForEach(Accent.allCases) { color in Text(color.label).tag(color) }
              }
              Button("sessão", systemImage: "play.fill") { showingSession = true }
            } label: { Label("configurar", systemImage: "gearshape") }
          }
          ToolbarItem(placement: .primaryAction) {
            Menu {
              Button("sair", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive)
              {
                Task { await academia.signOut() }
              }
            } label: { Image(systemName: "person.crop.circle") }
            .accessibilityLabel("sua conta")
          }
        }
        .keyboardDone()
    }
  }
}
