import HenriqueCore
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
  @Environment(FocoStore.self) private var foco
  @Binding var tab: EstudosTab
  @State private var showingSession: Bool
  @State private var showingWrite: Bool
  @Binding var showingApps: Bool

  init(
    tab: Binding<EstudosTab>, showingApps: Binding<Bool>,
    openSession: Bool = false, openWrite: Bool = false
  ) {
    _tab = tab
    _showingApps = showingApps
    showingSession = openSession
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
      .badge(overdueCount)
      Tab("revisar", systemImage: "rectangle.on.rectangle", value: EstudosTab.revisar) {
        shell { StudyReviewScreen(onWrite: { showingWrite = true }) }
      }
      .badge(store.overview.value?.reviewCount ?? 0)
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
    .onAppear {
      if tab == .apps { tab = .hoje; showingApps = true }
      if foco.takeBlockResume() { showingSession = true }
    }
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

  private var overdueCount: Int {
    let now = Date()
    return (store.assignments.value ?? []).reduce(0) { total, group in
      total + group.items.count { $0.isOverdue(at: now) }
    }
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
            Button("escrever", systemImage: "square.and.pencil") { showingWrite = true }
          }
          ToolbarItem(placement: .primaryAction) {
            Button("sessão", systemImage: "timer") { showingSession = true }
          }
          ToolbarItem(placement: .primaryAction) { AccountMenu() }
        }
        .keyboardDone()
    }
  }
}
