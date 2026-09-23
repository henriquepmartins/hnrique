import HenriqueCore
import SwiftUI

/// O que aparece ao tocar "encerrar": quanto durou, quanto saiu e se foi mais
/// que da última vez.
struct WorkoutRecapSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accent) private var accent
  let recap: WorkoutRecap

  var body: some View {
    VStack(alignment: .leading, spacing: Space.l) {
      Text("treino encerrado").font(.title2.weight(.medium)).tracking(-0.8)
      HStack(alignment: .top, spacing: Space.m) {
        stat(duration, caption: "de treino")
        stat("\(Formatting.trim(recap.workVolumeKg.rounded())) kg", caption: "de volume")
        stat("\(recap.doneSets)/\(recap.totalSets)", caption: "séries valendo")
      }
      if let comparison = recap.comparison {
        Text(compare(comparison))
          .font(.subheadline).foregroundStyle(Color.mutedInk)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("resumo.comparacao")
      }
      Spacer(minLength: 0)
      Button("fechar") { dismiss() }
        .buttonStyle(.glassProminent).tint(accent.deep).controlSize(.large)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("resumo.fechar")
    }
    .padding(Space.xl)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.canvas.ignoresSafeArea())
    .presentationDetents([.medium])
  }

  private var duration: String {
    guard let seconds = recap.durationSeconds else { return "0:00" }
    return Duration.seconds(seconds).formatted(
      .time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond(padMinuteToLength: 2)))
  }

  private func stat(_ value: String, caption: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        .lineLimit(1).minimumScaleFactor(0.7)
      Text(caption).font(.caption).foregroundStyle(Color.mutedInk)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private func compare(_ comparison: WorkoutRecap.VolumeComparison) -> String {
    let delta = (comparison.today - comparison.previous).rounded()
    if delta == 0 { return "o mesmo volume da última vez nos mesmos exercícios" }
    let amount = Formatting.trim(abs(delta))
    return delta > 0
      ? "\(amount) kg a mais que da última vez nos mesmos exercícios"
      : "\(amount) kg a menos que da última vez nos mesmos exercícios"
  }
}

/// O descanso rodando com a sessão minimizada. Tocar volta para a sessão.
struct RestChip: View {
  @Environment(\.accent) private var accent
  let rest: RestState
  let onOpen: () -> Void

  var body: some View {
    Button(action: onOpen) {
      TimelineView(.periodic(from: .now, by: 1)) { context in
        let remaining = rest.remaining(at: context.date)
        HStack(spacing: 6) {
          Image(systemName: "timer")
          Text(remaining > 0 ? "descanso \(restClock(remaining))" : "descanso completo, vai")
            .monospacedDigit()
        }
        .font(.subheadline.weight(.medium)).foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(remaining > 0 ? accent.deep : accent.base, in: .capsule)
      }
    }
    .buttonStyle(PressScaleStyle())
    .accessibilityIdentifier("descanso.chip")
  }
}

/// A fila de séries em uma linha, sem alerta: quantas esperam a rede, ou a
/// série que o servidor recusou.
struct SyncStatusLine: View {
  @Environment(AcademiaStore.self) private var store

  var body: some View {
    if let notice = store.notice {
      HStack(spacing: 6) {
        Label(notice, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(Color.orange).lineLimit(2)
        Spacer(minLength: 4)
        Button("ok") { store.notice = nil }.font(.caption.weight(.semibold))
      }
      .font(.caption)
      .accessibilityIdentifier("fila.aviso")
    } else if store.waitingCount > 0 {
      Label(
        store.waitingCount == 1 ? "1 série esperando a rede" : "\(store.waitingCount) séries esperando a rede",
        systemImage: "clock"
      )
      .font(.caption).foregroundStyle(Color.mutedInk)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityIdentifier("fila.esperando")
    }
  }
}
