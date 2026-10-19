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
/// registro e redesenhar a cada segundo não mudaria nada. `since` é um instante
/// em que o relógio da corrida virou segundo cheio: ancorado nele, o tick cai
/// quando o dígito troca, e não até um segundo depois. A leitura vem 10 ms
/// depois do tick para o arredondamento para baixo não cair em cima do segundo
/// exato e pular um dígito.
struct FocoTicker<Content: View>: View {
  let since: Date?
  var every: TimeInterval = 1
  @ViewBuilder let content: (Date) -> Content

  var body: some View {
    if let since {
      TimelineView(.periodic(from: since, by: every)) { context in
        content(context.date.addingTimeInterval(0.01))
      }
    } else {
      content(.now)
    }
  }
}

extension FocoLedger {
  /// Onde se ancora o tick de um relógio que mostra `shown`, nulo pausado. A
  /// corrida, o total do dia e o total da matéria somam trechos fechados com
  /// pedaços de segundo diferentes, então cada relógio vira quando o pedaço do
  /// que ele mesmo mostra completa.
  func tickAnchor(now: Date = .now, showing shown: (Date) -> TimeInterval) -> Date? {
    guard running?.runningSince != nil else { return nil }
    return now - shown(now).truncatingRemainder(dividingBy: 1)
  }
}

// MARK: - Tela

public struct FocoScreen: View {
  @Environment(FocoStore.self) private var foco
  @Environment(EstudosStore.self) private var estudos
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .largeTitle) private var clockSize = 64.0
  @State private var selectedDay: CalendarDate?

  private let leading: FocoTrack.Source

  public init(leading: FocoTrack.Source) {
    self.leading = leading
  }

  private var calendar: Calendar { StudyFormat.calendar }

  private var todayAnchor: Date? {
    let ledger = foco.ledger
    return ledger.tickAnchor { ledger.seconds(on: CalendarDate($0, in: calendar), now: $0, calendar: calendar) }
  }

  /// A linha da matéria que corre é a única que muda a cada segundo.
  private var trackAnchor: Date? {
    let ledger = foco.ledger
    guard let id = ledger.running?.track.id else { return nil }
    return ledger.tickAnchor {
      ledger.seconds(on: CalendarDate($0, in: calendar), track: id, now: $0, calendar: calendar)
    }
  }

  public var body: some View {
    ScrollView {
      // Cada tick redesenha só o que mostra segundos. A grade muda no máximo a
      // cada minuto, e o título e a lista de hoje só quando o registro muda.
      VStack(alignment: .leading, spacing: Space.xl) {
        StudyHeading(title: "foco")
          .staggeredEntrance(index: 0, isReady: true)
        FocoTicker(since: todayAnchor) { now in
          clockCard(ledger: foco.ledger, today: CalendarDate(now, in: calendar), now: now)
        }
        .staggeredEntrance(index: 1, isReady: true)
        FocoTicker(since: todayAnchor) { now in
          let ledger = foco.ledger
          streakRow(
            ledger.streak(now: now, calendar: calendar), ledger: ledger,
            today: CalendarDate(now, in: calendar), now: now)
        }
        .staggeredEntrance(index: 2, isReady: true)
        FocoTicker(since: trackAnchor) { now in
          tracksSection(ledger: foco.ledger, today: CalendarDate(now, in: calendar), now: now)
        }
        .staggeredEntrance(index: 3, isReady: true)
        FocoTicker(since: todayAnchor, every: 60) { now in
          let today = CalendarDate(now, in: calendar)
          FocoGrid(
            weeks: foco.ledger.weeks(endingOn: today, count: 12, now: now, calendar: calendar),
            today: today, selected: $selectedDay)
        }
        .staggeredEntrance(index: 4, isReady: true)
        daySection(selectedDay ?? CalendarDate(.now, in: calendar))
          .staggeredEntrance(index: 5, isReady: true)
      }
      .padding(.horizontal, Space.l)
      .padding(.bottom, Space.page)
    }
    .refreshable { await foco.sync() }
    .studyPage()
    .overlay(alignment: .bottom) {
      if let entry = foco.undoable {
        FocoUndoToast(entry: entry) { foco.undoRemove() }
          .padding(.horizontal, Space.l)
          .padding(.bottom, Space.m)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(reduceMotion ? nil : Motion.crossfade, value: foco.undoable)
    .sensoryFeedback(.start, trigger: foco.ledger.running?.startedAt) { _, new in new != nil }
    .sensoryFeedback(.impact(weight: .medium), trigger: foco.undoable?.id) { _, new in new != nil }
    .onChange(of: foco.undoable?.id) { _, id in
      guard id != nil, let entry = foco.undoable else { return }
      AccessibilityNotification.Announcement("sessão de \(entry.track.name) apagada, desfazer disponível")
        .post()
    }
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
      VStack(alignment: .leading, spacing: Space.m) {
        Text.clock(FocoFormat.clock(seconds))
          .font(.system(size: clockSize, weight: .semibold).leading(.tight))
          .tracking(-clockSize * 0.03)
          .contentTransition(.numericText())
          .animation(reduceMotion ? nil : Motion.roll, value: Int(seconds))
          .lineLimit(1)
          .minimumScaleFactor(0.5)
          .offset(x: -2)
          .accessibilityIdentifier("foco.relogio")
          .accessibilityLabel("\(FocoFormat.spoken(seconds)) hoje")
        FocoGoalBar(fraction: fraction, color: .studyBlue)
        Menu {
          Picker(
            "meta do dia",
            selection: Binding(
              get: { ledger.dailyGoalMinutes / 60 }, set: { foco.setGoal(minutes: $0 * 60) })
          ) {
            ForEach(1...8, id: \.self) { hours in Text("\(hours) h").tag(hours) }
          }
        } label: {
          HStack(spacing: Space.xs) {
            Text("\(percent)% de \(FocoFormat.short(minutes: ledger.dailyGoalMinutes))")
              .monospacedDigit()
              .contentTransition(.numericText())
              .animation(reduceMotion ? nil : Motion.roll, value: percent)
            Image(systemName: "chevron.up.chevron.down").imageScale(.small)
          }
          // Menu não aceita ButtonStyle, então o alvo de 44 cresce no rótulo.
          .padding(.vertical, 14).contentShape(.rect).padding(.vertical, -14)
        }
        .font(.caption)
        .foregroundStyle(Color.studyInk60)
        .accessibilityHint("troca a meta do dia")
        .sensoryFeedback(.selection, trigger: ledger.dailyGoalMinutes)
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
    // No texto de acessibilidade o recorde desce para baixo do resto, senão
    // rouba a largura e a linha de baixo quebra em três.
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.s))
      : AnyLayout(HStackLayout(alignment: .center, spacing: Space.m))
    return StudyCard {
      layout {
        HStack(alignment: .center, spacing: Space.m) {
          Image(systemName: "flame.fill")
            .font(.system(size: 26))
            .foregroundStyle(done ? Color.studyCoral : Color.studyInk20)
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
              .foregroundStyle(Color.studyInk60)
              .monospacedDigit()
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
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
          .transition(.opacity)
        }
        switch estudos.subjects {
        case .idle, .loading:
          ForEach(0..<2, id: \.self) { _ in
            FocoTrackRow(track: .alemao, isRunning: false, seconds: 0) {}
              .redacted(reason: .placeholder)
              .disabled(true)
              .accessibilityHidden(true)
          }
        case .failed(let message):
          StudyFailedState(message: message) { Task { await estudos.loadSubjects(force: true) } }
            .padding(.vertical, Space.s)
        case .ready:
          EmptyView()
        }
      }
      .animation(Motion.resolve(Motion.entrance, reduceMotion), value: tracks.map(\.id))
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

  // MARK: Dia escolhido

  private func daySection(_ day: CalendarDate) -> some View {
    let entries = foco.ledger.entries(on: day, calendar: calendar)
    return VStack(alignment: .leading, spacing: 0) {
      StudySectionHeading(title: dayTitle(day))
      if entries.isEmpty {
        StudyEmptyState(icon: "timer", title: "nenhuma sessão")
      } else {
        StudyDbList {
          ForEach(entries) { entry in
            StudyDbRow(
              dot: entry.track.color, title: entry.track.name,
              detail: "\(StudyFormat.hour(entry.startedAt)) a \(StudyFormat.hour(entry.endedAt))",
              end: { Text(entryDuration(entry)).monospacedDigit() }
            )
            .accessibilityElement(children: .combine)
            .contextMenu {
              Button("apagar", systemImage: "trash", role: .destructive) {
                foco.remove(entry, holdFor: .seconds(voiceOver ? 10 : 4))
              }
            }
          }
        }
      }
    }
    .animation(reduceMotion ? nil : Motion.crossfade, value: day)
  }

  private func dayTitle(_ day: CalendarDate) -> String {
    let today = CalendarDate(.now, in: calendar)
    if day == today { return "hoje" }
    if day == today.adding(days: -1, in: calendar) { return "ontem" }
    return StudyFormat.shortDay(day.date(in: calendar))
  }

  private func entryDuration(_ entry: FocoEntry) -> String {
    entry.seconds < 60
      ? "\(Int(entry.seconds)) s" : FocoFormat.short(minutes: Int(entry.seconds / 60))
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
    VStack(alignment: .leading, spacing: Space.s) {
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
      StudyWrap(spacing: Space.m, lineSpacing: Space.xs) {
        ForEach(shares.indices, id: \.self) { index in
          HStack(spacing: Space.xs) {
            StudyDot(color: shares[index].color)
            Text("\(shares[index].name) \(Int((shares[index].fraction * 100).rounded()))%")
              .monospacedDigit()
          }
        }
      }
      .font(.caption)
      .foregroundStyle(Color.studyInk60)
    }
    .padding(.top, Space.xs)
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
      HStack(spacing: Space.m) {
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
          .animation(reduceMotion ? nil : Motion.roll, value: Int(seconds))
          .foregroundStyle(isRunning ? Color.studyInk : Color.studyInk60)
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

/// O anel em volta do botão que roda. Cresce de 40 a 56 pontos e some em
/// ciclo. É escala e opacidade num quadro fixo, então o tick de cada segundo
/// redesenha a linha sem reiniciar o ciclo nem medir o anel de novo.
struct FocoPulseRing: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var expanded = false
  let color: Color

  var body: some View {
    Circle()
      .strokeBorder(color, lineWidth: 2)
      .frame(width: 56, height: 56)
      .scaleEffect(expanded ? 1 : 40.0 / 56)
      .opacity(expanded ? 0 : 0.6)
      .animation(expanded ? Motion.pulse : nil, value: expanded)
      .onAppear { expanded = !reduceMotion }
  }
}

/// Grade de 7 linhas por 12 colunas terminando na semana de hoje. Cada coluna
/// é uma semana do calendário e a cascata entra por coluna. Tocar num dia
/// mostra as sessões dele embaixo; tocar de novo volta para hoje.
struct FocoGrid: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let weeks: [[FocoDay?]]
  let today: CalendarDate
  @Binding var selected: CalendarDate?
  @State private var shown = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      StudySectionHeading(title: "últimas 12 semanas")
      StudyCard {
        HStack(spacing: Space.xs) {
          ForEach(weeks.indices, id: \.self) { column in
            VStack(spacing: Space.xs) {
              ForEach(0..<7, id: \.self) { row in
                if let day = weeks[column][row] {
                  cell(day)
                } else {
                  Color.clear.aspectRatio(1, contentMode: .fit)
                }
              }
            }
            .opacity(shown || reduceMotion ? 1 : 0)
            .animation(
              reduceMotion
                ? nil : Motion.entrance.delay(0.2 * Double(column) / Double(max(weeks.count - 1, 1))),
              value: shown)
          }
        }
        .frame(maxWidth: .infinity)
      }
    }
    .onAppear { shown = true }
    .sensoryFeedback(.selection, trigger: selected)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(
      "\(FocoFormat.count(weeks.joined().count { ($0?.seconds ?? 0) > 0 }, "dia", "dias")) com foco nas últimas 12 semanas")
  }

  private func cell(_ day: FocoDay) -> some View {
    let isSelected = day.date == (selected ?? today)
    return Button {
      selected = day.date == today || day.date == selected ? nil : day.date
    } label: {
      RoundedRectangle(cornerRadius: 3)
        .fill(day.level == 0 ? Color.studyLine : Color.studyBlue.opacity(opacity(day.level)))
        .aspectRatio(1, contentMode: .fit)
        .overlay {
          if isSelected {
            RoundedRectangle(cornerRadius: 3).strokeBorder(Color.studyInk, lineWidth: 1.5)
          }
        }
        .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(StudyFormat.weekdayLong(day.date.date(in: StudyFormat.calendar)))
    .accessibilityValue(FocoFormat.spoken(day.seconds))
    .accessibilityAddTraits(isSelected ? .isSelected : [])
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

  private var todayAnchor: Date? {
    let ledger = foco.ledger
    return ledger.tickAnchor { ledger.seconds(on: CalendarDate($0, in: calendar), now: $0, calendar: calendar) }
  }

  var body: some View {
    StudyCard {
      VStack(alignment: .leading, spacing: Space.m) {
        FocoTicker(since: todayAnchor) { now in
          let ledger = foco.ledger
          let seconds = ledger.seconds(on: CalendarDate(now, in: calendar), now: now, calendar: calendar)
          let streak = ledger.streak(now: now, calendar: calendar)
          VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
              Text.clock(FocoFormat.clock(seconds))
                .font(.system(size: clockSize, weight: .semibold).leading(.tight))
                .tracking(-clockSize * 0.03)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : Motion.roll, value: Int(seconds))
                .accessibilityLabel("\(FocoFormat.spoken(seconds)) hoje")
              Spacer(minLength: 0)
              HStack(spacing: Space.xs) {
                Image(systemName: "flame.fill")
                  .foregroundStyle(streak.isTodayDone ? Color.studyCoral : Color.studyInk20)
                  .animation(reduceMotion ? nil : Motion.crossfade, value: streak.isTodayDone)
                Text("\(streak.current)")
                  .monospacedDigit()
                  .contentTransition(.numericText())
                  .animation(reduceMotion ? nil : Motion.grow, value: streak.current)
              }
              .font(.headline)
              .accessibilityElement(children: .combine)
              .accessibilityLabel("\(FocoFormat.count(streak.current, "dia seguido", "dias seguidos"))")
            }
            FocoGoalBar(fraction: min(1, seconds / (Double(ledger.dailyGoalMinutes) * 60)), color: .studyBlue)
          }
        }
        NavigationLink {
          FocoScreen(leading: .estudos)
        } label: {
          Label(foco.isRunning ? "voltar ao foco" : "focar", systemImage: "timer")
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .tint(.studyBlue)
        .padding(.top, Space.xs)
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
    HStack(spacing: Space.m) {
      Label("sessão de \(entry.track.name) apagada", systemImage: "trash")
        .font(.subheadline)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
      Button("desfazer", systemImage: "arrow.uturn.backward", action: undo)
        .font(.subheadline.weight(.semibold))
        .accessibilityIdentifier("foco.desfazer")
    }
    .padding(.leading, Space.l)
    .padding(.trailing, Space.s)
    .padding(.vertical, 6)
    .frame(minHeight: 48)
    .glassEffect(in: .rect(cornerRadius: 24))
  }
}
