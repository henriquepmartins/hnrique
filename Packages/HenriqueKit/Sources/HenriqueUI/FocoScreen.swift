import HenriqueCore
import SwiftUI

// MARK: - Formatação

enum FocoFormat {
  static func clock(_ seconds: TimeInterval) -> String {
    let safe = max(0, Int(seconds.rounded(.down)))
    return String(format: "%d:%02d:%02d", safe / 3600, (safe % 3600) / 60, safe % 60)
  }

  static func short(minutes total: Int) -> String {
    if total < 60 { return "\(total) min" }
    let hours = total / 60
    let rest = total % 60
    return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
  }

  static func spoken(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let minutes = total / 60
    let hours = minutes / 60
    let rest = minutes % 60
    if minutes == 0 { return count(total, "segundo", "segundos") }
    if hours == 0 { return count(rest, "minuto", "minutos") }
    if rest == 0 { return count(hours, "hora", "horas") }
    return "\(count(hours, "hora", "horas")) e \(count(rest, "minuto", "minutos"))"
  }

  /// "1 dia", "3 dias". Contagem falada ou escrita com número na frente.
  static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
    "\(value) \(value == 1 ? singular : plural)"
  }
}

/// O tick só existe enquanto uma corrida roda. Parado, o total já está no
/// registro e redesenhar a cada segundo não mudaria nada.
struct FocoTicker<Content: View>: View {
  let running: Bool
  @ViewBuilder let content: (Date) -> Content

  var body: some View {
    if running {
      TimelineView(.periodic(from: .now, by: 1)) { context in
        content(context.date)
      }
    } else {
      content(.now)
    }
  }
}

// MARK: - Tela

public struct FocoScreen: View {
  @Environment(FocoStore.self) private var foco
  @Environment(EstudosStore.self) private var estudos
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @ScaledMetric(relativeTo: .largeTitle) private var clockSize = 64.0

  private let leading: FocoTrack.Source

  public init(leading: FocoTrack.Source) {
    self.leading = leading
  }

  private var calendar: Calendar { StudyFormat.calendar }

  public var body: some View {
    ScrollView {
      FocoTicker(running: foco.isRunning) { now in
        let today = CalendarDate(now, in: calendar)
        let ledger = foco.ledger
        VStack(alignment: .leading, spacing: 20) {
          StudyHeading(title: "foco")
            .staggeredEntrance(index: 0, isReady: true)
          clockCard(ledger: ledger, today: today, now: now)
            .staggeredEntrance(index: 1, isReady: true)
          streakRow(ledger.streak(now: now, calendar: calendar), ledger: ledger, today: today, now: now)
            .staggeredEntrance(index: 2, isReady: true)
          tracksSection(ledger: ledger, today: today, now: now)
            .staggeredEntrance(index: 3, isReady: true)
          FocoGrid(days: ledger.days(endingOn: today, count: 84, now: now, calendar: calendar), today: today)
            .staggeredEntrance(index: 4, isReady: true)
          todaySection(ledger.entries(on: today, calendar: calendar))
            .staggeredEntrance(index: 5, isReady: true)
        }
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 32)
    }
    .studyPage()
    .overlay(alignment: .bottom) {
      if let entry = foco.undoable {
        FocoUndoToast(entry: entry) { foco.undoRemove() }
          .padding(.horizontal, 16)
          .padding(.bottom, 12)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(reduceMotion ? nil : Motion.crossfade, value: foco.undoable)
    .task {
      await estudos.loadSubjects()
      if foco.takeResume() { foco.isShowingRun = true }
      await foco.syncIfStale()
    }
    .onChange(of: scenePhase) {
      if scenePhase == .active { Task { await foco.syncIfStale() } }
    }
  }

  // MARK: Relógio do dia

  private func clockCard(ledger: FocoLedger, today: CalendarDate, now: Date) -> some View {
    let seconds = ledger.seconds(on: today, now: now, calendar: calendar)
    let goal = Double(ledger.dailyGoalMinutes) * 60
    let fraction = min(1, seconds / goal)
    let percent = Int((seconds / goal * 100).rounded(.down))
    return StudyCard {
      VStack(alignment: .leading, spacing: 12) {
        Text.clock(FocoFormat.clock(seconds))
          .font(.system(size: clockSize, weight: .semibold).leading(.tight))
          .tracking(-clockSize * 0.03)
          .contentTransition(.numericText())
          .animation(reduceMotion ? nil : Motion.crossfade, value: Int(seconds))
          .lineLimit(1)
          .minimumScaleFactor(0.5)
          .offset(x: -2)
          .accessibilityIdentifier("foco.relogio")
          .accessibilityLabel("\(FocoFormat.spoken(seconds)) hoje")
        FocoGoalBar(fraction: fraction, color: .studyBlue)
        Menu {
          ForEach(1...8, id: \.self) { hours in
            Button("\(hours) h") { foco.setGoal(minutes: hours * 60) }
          }
        } label: {
          HStack(spacing: 4) {
            Text("\(percent)% de \(FocoFormat.short(minutes: ledger.dailyGoalMinutes))")
              .monospacedDigit()
              .contentTransition(.numericText())
            Image(systemName: "chevron.up.chevron.down").imageScale(.small)
          }
          // Menu não aceita ButtonStyle, então o alvo de 44 cresce no rótulo.
          .padding(.vertical, 14).contentShape(.rect).padding(.vertical, -14)
        }
        .font(.caption)
        .foregroundStyle(Color.studyInk60)
        .accessibilityHint("troca a meta do dia")
        let shares = trackShares(ledger: ledger, today: today, now: now)
        if !shares.isEmpty {
          FocoDayBand(shares: shares)
            .transition(.opacity)
        }
      }
      .animation(reduceMotion ? nil : Motion.crossfade, value: seconds > 0)
    }
  }

  /// A fatia de cada trilha no dia, na ordem da lista. É a faixa colorida do YPT.
  private func trackShares(ledger: FocoLedger, today: CalendarDate, now: Date) -> [(name: String, color: String, fraction: Double)] {
    let total = ledger.seconds(on: today, now: now, calendar: calendar)
    guard total > 0 else { return [] }
    return tracks.compactMap { track in
      let seconds = ledger.seconds(on: today, track: track.id, now: now, calendar: calendar)
      return seconds > 0 ? (track.name, track.color, seconds / total) : nil
    }
  }

  // MARK: Streak

  private func streakRow(_ streak: FocoStreak, ledger: FocoLedger, today: CalendarDate, now: Date) -> some View {
    let done = streak.isTodayDone
    let missing = FocoLedger.dayCountsMinutes
      - Int(ledger.seconds(on: today, now: now, calendar: calendar) / 60)
    return StudyCard {
      HStack(alignment: .center, spacing: 12) {
        Image(systemName: "flame.fill")
          .font(.system(size: 26))
          .foregroundStyle(done ? Color.studyCoral : Color.studyInk20)
          .symbolEffect(.bounce, value: streak.current)
          .animation(reduceMotion ? nil : Motion.crossfade, value: done)
        VStack(alignment: .leading, spacing: 2) {
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(streak.current)")
              .font(.title2.weight(.semibold))
              .monospacedDigit()
              .contentTransition(.numericText())
              .animation(reduceMotion ? nil : Motion.grow, value: streak.current)
            Text("dias seguidos").font(.subheadline).foregroundStyle(Color.studyInk60)
          }
          Text(done ? "hoje já conta" : streak.current > 0 ? "faltam \(max(missing, 1)) min para manter" : "\(FocoLedger.dayCountsMinutes) min contam o dia")
            .font(.caption)
            .foregroundStyle(Color.studyInk40)
            .monospacedDigit()
        }
        Spacer(minLength: 0)
        Text("recorde \(streak.best)")
          .font(.caption.weight(.medium))
          .monospacedDigit()
          .foregroundStyle(Color.studyInk60)
      }
      .accessibilityElement(children: .combine)
    }
  }

  // MARK: Matérias

  private var tracks: [FocoTrack] {
    let subjects = (estudos.subjects.value ?? []).map {
      FocoTrack.subject(id: $0.id, name: $0.name, color: $0.color)
    }
    return leading == .idiomas ? [.alemao] + subjects : subjects + [.alemao]
  }

  private func tracksSection(ledger: FocoLedger, today: CalendarDate, now: Date) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      StudySectionHeading(title: "matérias")
      StudyDbList {
        ForEach(tracks) { track in
          FocoTrackRow(
            track: track,
            isRunning: ledger.running?.track.id == track.id,
            seconds: ledger.seconds(on: today, track: track.id, now: now, calendar: calendar)
          ) { toggle(track) }
        }
      }
    }
  }

  private func toggle(_ track: FocoTrack) {
    if foco.ledger.running?.track.id == track.id {
      foco.stop()
    } else {
      foco.start(track)
      foco.isShowingRun = true
    }
  }

  // MARK: Hoje

  private func todaySection(_ entries: [FocoEntry]) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      StudySectionHeading(title: "hoje")
      if entries.isEmpty {
        StudyEmptyState(icon: "timer", title: "nenhuma sessão hoje")
      } else {
        StudyDbList {
          ForEach(entries) { entry in
            StudyDbRow(dot: entry.track.color, title: entryTitle(entry), end: { EmptyView() })
              .contextMenu {
                Button("apagar", systemImage: "trash", role: .destructive) { foco.remove(entry) }
              }
          }
        }
      }
    }
  }

  private func entryTitle(_ entry: FocoEntry) -> String {
    let minutes = entry.seconds < 60
      ? "\(Int(entry.seconds)) s" : FocoFormat.short(minutes: Int(entry.seconds / 60))
    return "\(StudyFormat.hour(entry.startedAt)) a \(StudyFormat.hour(entry.endedAt)) · \(entry.track.name) · \(minutes)"
  }
}

// MARK: - Peças

struct FocoGoalBar: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let fraction: Double
  let color: Color

  var body: some View {
    Capsule().fill(color.opacity(0.14))
      .frame(height: 8)
      .overlay(alignment: .leading) {
        Capsule().fill(color)
          .scaleEffect(x: min(max(fraction, 0), 1), y: 1, anchor: .leading)
      }
      .clipShape(.capsule)
      .animation(reduceMotion ? nil : Motion.grow, value: fraction)
      .accessibilityHidden(true)
  }
}

/// Uma cápsula fina dividida nas cores das trilhas do dia, proporcional ao
/// tempo de cada uma.
struct FocoDayBand: View {
  let shares: [(name: String, color: String, fraction: Double)]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      GeometryReader { proxy in
        HStack(spacing: 2) {
          ForEach(shares.indices, id: \.self) { index in
            Rectangle()
              .fill(Color(hexString: shares[index].color))
              .frame(width: max(2, proxy.size.width * shares[index].fraction - 2))
          }
        }
      }
      .frame(height: 6)
      .clipShape(.capsule)
      // Sem a legenda a faixa lia como uma segunda barra de meta, cheia.
      StudyWrap(spacing: 12, lineSpacing: 4) {
        ForEach(shares.indices, id: \.self) { index in
          HStack(spacing: 4) {
            StudyDot(color: shares[index].color)
            Text("\(shares[index].name) \(Int((shares[index].fraction * 100).rounded()))%")
              .monospacedDigit()
          }
        }
      }
      .font(.caption)
      .foregroundStyle(Color.studyInk60)
    }
    .padding(.top, 4)
    .accessibilityElement(children: .combine)
  }
}

struct FocoTrackRow: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let track: FocoTrack
  let isRunning: Bool
  let seconds: TimeInterval
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        ZStack {
          if isRunning && !reduceMotion {
            FocoPulseRing(color: Color(hexString: track.color))
          }
          Circle()
            .fill(Color(hexString: track.color))
            .frame(width: 40, height: 40)
            .overlay {
              Image(systemName: isRunning ? "stop.fill" : "play.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.subjectInk(for: track.color))
                .contentTransition(.symbolEffect(.replace))
                // O triângulo centrado pela geometria parece à esquerda.
                .offset(x: isRunning ? 0 : 1)
            }
        }
        .frame(width: 48, height: 48)
        Text(track.name)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(Color.studyInk)
          .lineLimit(1)
        Spacer(minLength: 0)
        Text(FocoFormat.clock(seconds))
          .font(.subheadline)
          .monospacedDigit()
          .contentTransition(.numericText())
          .foregroundStyle(isRunning ? Color.studyInk : Color.studyInk40)
      }
      .frame(minHeight: 52)
      .padding(.vertical, 6)
      .contentShape(.rect)
      .animation(reduceMotion ? nil : Motion.tap, value: isRunning)
    }
    .buttonStyle(StudyPressStyle())
    .accessibilityLabel(isRunning ? "parar \(track.name)" : "começar \(track.name)")
    .accessibilityValue("\(FocoFormat.spoken(seconds)) hoje")
  }
}

/// O anel em volta do botão que roda. Cresce e some em ciclo, e a fase sai do
/// relógio para o anel não reiniciar toda vez que o segundo troca.
struct FocoPulseRing: View {
  let color: Color

  var body: some View {
    TimelineView(.animation) { context in
      let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
      Circle()
        .strokeBorder(color.opacity(0.6 * (1 - phase)), lineWidth: 2)
        .frame(width: 40 + 16 * phase, height: 40 + 16 * phase)
    }
  }
}

/// Grade de 7 linhas por 12 colunas terminando hoje. Cada coluna é uma semana
/// e a cascata entra por coluna.
struct FocoGrid: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let days: [FocoDay]
  let today: CalendarDate
  @State private var shown = false

  private let columns = 12
  private let rows = 7

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      StudySectionHeading(title: "últimas 12 semanas")
      StudyCard {
        HStack(spacing: 4) {
          ForEach(0..<columns, id: \.self) { column in
            VStack(spacing: 4) {
              ForEach(0..<rows, id: \.self) { row in
                cell(days[column * rows + row])
              }
            }
            .opacity(shown || reduceMotion ? 1 : 0)
            .animation(
              reduceMotion ? nil : Motion.entrance.delay(0.04 * Double(column)), value: shown)
          }
        }
        .frame(maxWidth: .infinity)
      }
    }
    .onAppear { shown = true }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(FocoFormat.count(days.count { $0.seconds > 0 }, "dia", "dias")) com foco nas últimas 12 semanas")
  }

  private func cell(_ day: FocoDay) -> some View {
    RoundedRectangle(cornerRadius: 3)
      .fill(day.level == 0 ? Color.studyLine : Color.studyBlue.opacity(opacity(day.level)))
      .aspectRatio(1, contentMode: .fit)
      .overlay {
        if day.date == today {
          RoundedRectangle(cornerRadius: 3).strokeBorder(Color.studyInk, lineWidth: 1.5)
        }
      }
  }

  private func opacity(_ level: Int) -> Double {
    switch level {
    case 1: 0.25
    case 2: 0.45
    case 3: 0.7
    default: 1
    }
  }
}

// MARK: - Cartão da aba hoje de estudos

/// O que ficou no lugar do herói de estudos: o total de hoje, a chama e a
/// meta, com o botão que leva à tela de foco.
struct FocoTodayCard: View {
  @Environment(FocoStore.self) private var foco
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .largeTitle) private var clockSize = 44.0

  private var calendar: Calendar { StudyFormat.calendar }

  var body: some View {
    FocoTicker(running: foco.isRunning) { now in
      let ledger = foco.ledger
      let today = CalendarDate(now, in: calendar)
      let seconds = ledger.seconds(on: today, now: now, calendar: calendar)
      let streak = ledger.streak(now: now, calendar: calendar)
      StudyCard {
        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text.clock(FocoFormat.clock(seconds))
              .font(.system(size: clockSize, weight: .semibold).leading(.tight))
              .tracking(-clockSize * 0.03)
              .contentTransition(.numericText())
              .animation(reduceMotion ? nil : Motion.crossfade, value: Int(seconds))
              .accessibilityLabel("\(FocoFormat.spoken(seconds)) hoje")
            Spacer(minLength: 0)
            HStack(spacing: 4) {
              Image(systemName: "flame.fill")
                .foregroundStyle(streak.isTodayDone ? Color.studyCoral : Color.studyInk20)
                .symbolEffect(.bounce, value: streak.current)
              Text("\(streak.current)")
                .monospacedDigit()
                .contentTransition(.numericText())
            }
            .font(.headline)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(FocoFormat.count(streak.current, "dia seguido", "dias seguidos"))")
          }
          FocoGoalBar(fraction: min(1, seconds / (Double(ledger.dailyGoalMinutes) * 60)), color: .studyBlue)
          NavigationLink {
            FocoScreen(leading: .estudos)
          } label: {
            Label(foco.isRunning ? "voltar ao foco" : "focar", systemImage: "timer")
          }
          .buttonStyle(.glassProminent)
          .controlSize(.large)
          .tint(.studyBlue)
          .padding(.top, 4)
        }
      }
    }
    .task { await foco.syncIfStale() }
  }
}

/// O aviso depois de apagar uma sessão. Fica 4 s, o tempo que o store segura a
/// remoção antes de mandar ao servidor.
struct FocoUndoToast: View {
  let entry: FocoEntry
  let undo: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Text("sessão de \(entry.track.name) apagada")
        .font(.subheadline)
        .lineLimit(1)
      Spacer(minLength: 0)
      Button("desfazer", action: undo)
        .font(.subheadline.weight(.semibold))
        .accessibilityIdentifier("foco.desfazer")
    }
    .padding(.leading, 16)
    .padding(.trailing, 8)
    .frame(minHeight: 48)
    .glassEffect(in: .capsule)
  }
}
