import HenriqueCore
import SwiftUI

// MARK: - Foco visível de qualquer app

extension View {
  /// A faixa acima das abas enquanto o foco roda. Mora na casca para aparecer
  /// também na academia, sem as telas de treino saberem do foco.
  func focoAccessory() -> some View {
    modifier(FocoAccessory())
  }

  /// "você ainda está aí?" depois de 4 h. A pergunta aparece onde a pessoa
  /// estiver: na casca ou dentro da tela escura, que cobre a casca.
  func focoPresenceCheck(inCover: Bool) -> some View {
    modifier(FocoPresenceCheck(inCover: inCover))
  }
}

private struct FocoAccessory: ViewModifier {
  @Environment(FocoStore.self) private var foco

  func body(content: Content) -> some View {
    #if os(iOS)
      if #available(iOS 26.1, *) {
        content.tabViewBottomAccessory(isEnabled: foco.isRunning) { FocoAccessoryLabel() }
      } else {
        content
      }
    #else
      content
    #endif
  }
}

private struct FocoAccessoryLabel: View {
  @Environment(FocoStore.self) private var foco

  var body: some View {
    if let run = foco.ledger.running {
      // O botão inteiro mora dentro do tick: o rótulo falado lia o tempo do
      // último desenho completo e ficava minutos atrás do relógio.
      FocoTicker(running: !run.isPaused) { now in
        Button {
          foco.isShowingRun = true
        } label: {
          HStack(spacing: 10) {
            Circle().fill(Color(hexString: run.track.color)).frame(width: 10, height: 10)
            Text(run.track.name).lineLimit(1)
            Spacer(minLength: 0)
            Text(run.isPaused ? "pausado" : FocoFormat.clock(run.seconds(at: now)))
              .monospacedDigit()
              .contentTransition(.numericText())
          }
          .font(.subheadline.weight(.medium))
          .padding(.horizontal, 16)
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("foco em \(run.track.name)")
        .accessibilityValue(run.isPaused ? "pausado" : FocoFormat.spoken(run.seconds(at: now)))
        .accessibilityHint("abre o cronômetro")
        .accessibilityIdentifier("foco.faixa")
      }
    }
  }
}

private struct FocoPresenceCheck: ViewModifier {
  @Environment(FocoStore.self) private var foco
  let inCover: Bool

  func body(content: Content) -> some View {
    let cut = foco.presenceCut
    content.alert(
      "você ainda está aí?",
      isPresented: .init(
        get: { cut != nil && foco.isShowingRun == inCover }, set: { _ in })
    ) {
      Button("sim, continuar") { foco.confirmPresence() }
      if let cut {
        Button("parar às \(StudyFormat.hour(cut))") { foco.stopAtLastPresence() }
      }
    } message: {
      Text("o foco está rodando há mais de 4 h. dá para cortar na última vez que o app esteve aberto.")
    }
  }
}

// MARK: - Sem conexão

extension View {
  /// A faixa de sem conexão dentro da pilha de navegação, entre a barra e o
  /// conteúdo. Como inset ela empurra o título para baixo; sobreposta ao app
  /// inteiro, tampava os botões da barra ou o título grande.
  func offlineInset() -> some View {
    modifier(OfflineInset())
  }
}

private struct OfflineInset: ViewModifier {
  @Environment(AcademiaStore.self) private var store
  @Environment(EstudosStore.self) private var estudos
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var isOffline: Bool {
    store.isSignedIn && estudos.client.connectivity.isOffline
  }

  func body(content: Content) -> some View {
    content
      .safeAreaInset(edge: .top, spacing: 0) {
        if isOffline {
          OfflineBanner()
            .padding(.vertical, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
      }
      .animation(reduceMotion ? nil : Motion.crossfade, value: isOffline)
  }
}

/// Uma faixa discreta no topo, no lugar do alerta que travava a tela a cada
/// abertura sem rede. Some sozinha quando um pedido chega ao servidor.
struct OfflineBanner: View {
  var body: some View {
    Label("sem conexão · tentando de novo", systemImage: "wifi.slash")
      .font(.footnote.weight(.medium))
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .glassEffect(in: .capsule)
      .accessibilityIdentifier("sem-conexao")
  }
}
