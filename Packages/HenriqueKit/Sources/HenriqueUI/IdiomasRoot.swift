import SwiftUI

public enum IdiomasTab: String, Hashable, Sendable, CaseIterable {
  case rotina, foco, revisar, progresso, apps

  public init?(named name: String) {
    self.init(rawValue: name)
  }
}

struct IdiomasTabs: View {
  @Environment(IdiomasStore.self) private var store
  @Environment(AcademiaStore.self) private var academia
  @Binding var tab: IdiomasTab
  @Binding var showingApps: Bool
  @State private var speech = IdiomasSpeech()

  var body: some View {
    TabView(selection: appSwitcherSelection($tab, isPresented: $showingApps, bubble: .apps)) {
      Tab("rotina", systemImage: "bubble.left.and.text.bubble.right", value: IdiomasTab.rotina) {
        shell { IdiomasRotinaScreen() }
      }
      Tab("foco", systemImage: "timer", value: IdiomasTab.foco) {
        shell { FocoScreen(leading: .idiomas) }
      }
      Tab("revisar", systemImage: "rectangle.on.rectangle", value: IdiomasTab.revisar) {
        shell { IdiomasRevisarScreen() }
      }
      Tab("progresso", systemImage: "chart.xyaxis.line", value: IdiomasTab.progresso) {
        shell { IdiomasProgressoScreen() }
      }
      Tab(
        "apps", systemImage: showingApps ? "xmark" : "square.grid.2x2",
        value: IdiomasTab.apps, role: appHubTabRole
      ) {
        Color.clear
      }
    }
    .focoAccessory()
    .onAppear { if tab == .apps { tab = .rotina; showingApps = true } }
    .tint(.idiomasTeal)
    .environment(speech)
    .task {
      speech.checkVoiceAvailability()
      await store.prefetchAll()
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
