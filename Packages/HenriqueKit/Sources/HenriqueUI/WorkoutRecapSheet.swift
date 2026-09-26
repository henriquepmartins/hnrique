import HenriqueCore
import SwiftUI

/// O que aparece ao tocar "encerrar": quanto durou, quanto saiu, os recordes do
/// dia e a melhor série de cada exercício.
struct WorkoutRecapSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accent) private var accent
  @ScaledMetric(relativeTo: .caption) private var badgeSize = 11.0
  @ScaledMetric(relativeTo: .caption) private var medalSize = 36.0
  let recap: WorkoutRecap

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: Space.l) {
          Text("treino encerrado").font(.title2.weight(.medium)).tracking(-0.8)
          HStack(alignment: .top, spacing: Space.m) {
            stat(duration, caption: "de treino")
            stat("\(Formatting.trim(recap.workVolumeKg.rounded())) kg", caption: "de volume", delta: delta)
            stat("\(recap.doneSets)/\(recap.totalSets)", caption: "séries valendo")
          }
          if !recap.records.isEmpty {
            VStack(spacing: Space.s) {
              ForEach(recap.records) { record(for: $0) }
            }
          }
          VStack(spacing: 0) {
            ForEach(recap.exercises) { line in
              exerciseLine(line)
              if line.id != recap.exercises.last?.id { Divider() }
            }
          }
        }
        .padding(.horizontal, Space.xl).padding(.top, Space.xl).padding(.bottom, Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      Button("fechar") { dismiss() }
        .buttonStyle(.glassProminent).tint(accent.deep).controlSize(.large)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("resumo.fechar")
        .padding(.horizontal, Space.xl).padding(.bottom, Space.l)
    }
    .background(Color.canvas.ignoresSafeArea())
    .presentationDetents([.medium, .large])
  }

  private var duration: String {
    guard let seconds = recap.durationSeconds else { return "0:00" }
    return Duration.seconds(seconds).formatted(
      .time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond(padMinuteToLength: 2)))
  }

  /// A diferença para a última vez, nos exercícios que têm histórico. Zero não
  /// aparece: "o mesmo volume" era uma frase inteira para dizer nada.
  private var delta: Double? {
    guard let comparison = recap.comparison else { return nil }
    let delta = (comparison.today - comparison.previous).rounded()
    return delta == 0 ? nil : delta
  }

  private func stat(_ value: String, caption: String, delta: Double? = nil) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        .lineLimit(1).minimumScaleFactor(0.7)
      Text(caption).font(.caption).foregroundStyle(Color.mutedInk)
      if let delta {
        Text("\(delta > 0 ? "+" : "−")\(Formatting.trim(abs(delta))) kg")
          .font(.caption.weight(.medium)).monospacedDigit()
          .foregroundStyle(delta > 0 ? accent.base : Color.mutedInk)
          .padding(.top, 2)
          .accessibilityLabel(
            "\(Formatting.trim(abs(delta))) quilos a \(delta > 0 ? "mais" : "menos") que da última vez")
          .accessibilityIdentifier("resumo.comparacao")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private func record(for record: PersonalRecord) -> some View {
    let badge = record.kind.badge(delta: record.delta)
    return HStack(spacing: 12) {
      Group {
        if let symbol = record.kind.badgeSymbol {
          Image(systemName: symbol).font(.system(size: badgeSize + 3, weight: .semibold))
        } else if let badge {
          Text(badge)
            .font(.system(size: badgeSize, weight: .semibold, design: .monospaced))
            .multilineTextAlignment(.center)
        }
      }
      .foregroundStyle(accent.deep)
      .frame(width: medalSize, height: medalSize)
      .background(accent.pale, in: .rect(cornerRadius: medalSize / 3))
      Text(record.exerciseName.lowercased())
        .font(.callout.weight(.medium)).lineLimit(1)
      Spacer(minLength: Space.s)
      Text("\(Formatting.trim(record.weightKg)) × \(record.reps)")
        .font(.callout).monospacedDigit().foregroundStyle(Color.mutedInk)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("recorde de \(record.kind.label), \(record.exerciseName.lowercased())")
    .accessibilityValue(
      ["\(Formatting.trim(record.weightKg)) quilos por \(record.reps)", badge?.replacingOccurrences(of: "\n", with: " ")]
        .compactMap { $0 }.joined(separator: ", "))
  }

  /// "puxada alta · 2/2 · 48 × 8", com a série valendo mais pesada feita.
  private func exerciseLine(_ line: WorkoutRecap.ExerciseLine) -> some View {
    HStack(spacing: Space.s) {
      Text(line.name.lowercased()).font(.subheadline).lineLimit(1)
      Spacer(minLength: Space.s)
      Text("\(line.doneSets)/\(line.totalSets)")
        .font(.subheadline).monospacedDigit().foregroundStyle(Color.mutedInk)
      Text(line.top.map { "\(Formatting.trim($0.weightKg)) × \($0.reps)" } ?? "–")
        .font(.subheadline.weight(.medium)).monospacedDigit()
        .frame(minWidth: 64, alignment: .trailing)
    }
    .padding(.vertical, 11)
    .accessibilityElement(children: .combine)
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
