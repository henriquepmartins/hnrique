import HenriqueCore
import SwiftUI

struct WeekScreen: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.dynamicTypeSize) private var textSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var editor: PlanEditorDestination?
  @State private var deletions = 0
  var onStart: (Int) -> Void = { _ in }
  var onTrainToday: () -> Void = {}

  var body: some View {
    ScrollView {
      if store.dashboard != nil {
        VStack(alignment: .leading, spacing: Space.xxl) {
          PlanCalendarCard(
            attendance: store.attendance,
            weekPlan: store.weekPlan,
            swaps: store.dashboard?.daySwaps ?? [],
            week: store.trainingWeek(),
            swapWindow: swapWindow,
            load: { from, to in await store.loadAttendance(from: from, to: to) },
            onSwap: { date, workoutId in await store.swapDay(on: date, workoutTemplateId: workoutId) })
          Button("novo treino", systemImage: "plus") { editor = .new }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .subtleEntrance()
          LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.m),
                                   count: textSize.isAccessibilitySize ? 1 : 2), spacing: 6) {
            ForEach(store.weekPlan.inTrainingWeekOrder()) { item in
              WorkoutTile(
                item: item,
                showsWave: store.dashboard?.highlightedWorkoutIDs.contains(item.id) == true,
                onEdit: { step in editor = .existing(item, at: step) },
                onDelete: {
                  withAnimation(Motion.resolve(Motion.confirm, reduceMotion)) {
                    store.deleteWorkout(workoutTemplateId: item.id)
                  }
                  deletions += 1
                },
                onStart: { if let day = item.nextWeekday(from: store.selectedDate.weekday()) { onStart(day) } },
                onTrainToday: canTrainToday(item) ? { Task { await trainToday(item) } } : nil)
                .subtleEntrance()
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
            }
          }
        }
        .padding(Space.l)
        .padding(.bottom, Space.page)
      }
    }
    .background(Color.canvas)
    .refreshable { await store.load() }
    .sensoryFeedback(.impact(weight: .medium), trigger: deletions)
    .overlay {
      TodayPlaceholder(phase: store.phase, isEmpty: store.dashboard == nil) { WeekSkeleton() }
    }
    .sheet(item: $editor) { destination in
      WorkoutEditor(
        item: destination.item, weekdays: destination.weekdays,
        tone: destination.item?.tone ?? .unused(among: store.weekPlan.map(\.tone.hex)),
        catalog: store.dashboard?.exerciseCatalog ?? [],
        startingAt: destination.step)
    }
  }

  /// As datas cujas trocas o painel aberto traz: de hoje até seis dias depois
  /// do dia aberto. Fora dela uma troca salvaria sem aparecer no calendário.
  /// Nula no servidor que ainda não troca dia. Hoje com série marcada fica de
  /// fora, como no menu de troca da home.
  private var swapWindow: ClosedRange<CalendarDate>? {
    guard let dashboard = store.dashboard, dashboard.daySwaps != nil else { return nil }
    let today = CalendarDate.today
    let start = store.todayHasMarkedSets ? today.adding(days: 1) : today
    let end = dashboard.date.adding(days: 6)
    return start <= end ? start...end : nil
  }

  /// Some quando o treino já é o de hoje ou quando hoje já tem série marcada,
  /// com qualquer dia aberto, que a troca não pode levar para outro treino.
  private func canTrainToday(_ item: WeekPlanItem) -> Bool {
    guard let dashboard = store.dashboard, dashboard.daySwaps != nil else { return false }
    if store.todayHasMarkedSets { return false }
    return dashboard.schedule.workout(on: .today)?.id != item.id
  }

  /// Abre hoje, troca o treino do dia por este e abre a sessão. A troca
  /// recusada deixa o aviso no banner do store.
  private func trainToday(_ item: WeekPlanItem) async {
    let today = CalendarDate.today
    await store.select(date: today)
    if store.dashboard?.schedule.workout(on: today)?.id != item.id {
      guard await store.swapDay(workoutTemplateId: item.id) else { return }
    }
    onTrainToday()
  }
}

/// A forma do plano sem dados: o calendário, o botão de novo treino e as
/// pastas, com a aba e o corpo de cada uma.
private struct WeekSkeleton: View {
  var body: some View {
    VStack(alignment: .leading, spacing: Space.xxl) {
      RoundedRectangle(cornerRadius: Radius.card).frame(height: 340)
      Capsule().frame(width: 160, height: 50)
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.m), count: 2), spacing: 6) {
        ForEach(0..<4, id: \.self) { _ in FolderSilhouette() }
      }
    }
    .foregroundStyle(Color.surfaceMuted)
    .modifier(SkeletonPulse())
    .padding(Space.l)
    .frame(maxHeight: .infinity, alignment: .top)
    .accessibilityHidden(true)
  }
}

/// A silhueta da `WorkoutFolderCard`, nas mesmas proporções do desenho de 508.
private struct FolderSilhouette: View {
  var body: some View {
    GeometryReader { geometry in
      let scale = geometry.size.width / 508
      ZStack(alignment: .topLeading) {
        RoundedRectangle(cornerRadius: 40 * scale).frame(width: 225 * scale, height: 180 * scale)
        RoundedRectangle(cornerRadius: 52 * scale).padding(.top, 32 * scale)
      }
    }
    .aspectRatio(508 / 455, contentMode: .fit)
  }
}

/// O passo de abertura viaja com o destino. Num `@State` à parte, a folha lia
/// o valor do desenho anterior e abria sempre no nome.
private struct PlanEditorDestination: Identifiable {
  let item: WeekPlanItem?
  let step: EditorStep
  var id: String { item?.id ?? "new" }
  var weekdays: Set<Int> { Set(item?.weekdays ?? []) }

  static let new = PlanEditorDestination(item: nil, step: .identidade)

  static func existing(_ item: WeekPlanItem, at step: EditorStep) -> PlanEditorDestination {
    PlanEditorDestination(item: item, step: step)
  }
}

let planWeekdays = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"]
let planWeekdaysShort = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"]

/// "segunda e quinta". O locale fica preso no português porque o resto da tela
/// também é, e senão um aparelho em inglês lia "segunda and quinta".
func spokenWeekdays(_ weekdays: [Int]) -> String {
  weekdays.map { planWeekdays[$0] }.formatted(.list(type: .and).locale(StudyFormat.locale))
}

extension [WeekPlanItem] {
  /// A grade segue a semana de treino pelo primeiro dia de cada treino, e os
  /// sem dia vão para o fim. O servidor não guarda posição, e na ordem em que
  /// ele manda a pasta de segunda podia cair depois da de sexta.
  func inTrainingWeekOrder(firstWeekday: Int = Calendar.trainingWeek.firstWeekday) -> [WeekPlanItem] {
    let start = firstWeekday - 1
    func rank(_ item: WeekPlanItem) -> Int {
      item.weekdays.map { ($0 - start + 7) % 7 }.min() ?? 7
    }
    return enumerated()
      .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
      .map(\.element)
  }
}

extension WeekPlanItem {
  /// Sem cor salva, a cor sai do id. Pela posição, apagar um card repintava os
  /// seguintes; pelo dia, dar o dia a outro treino repintava a pasta e todos os
  /// dias feitos dela no calendário. O id nunca muda, e o próximo salvar grava
  /// essa cor no servidor.
  var tone: WorkoutTone {
    color.flatMap(WorkoutTone.from(hex:)) ?? .at(Int(Self.stableHash(id) % UInt64(WorkoutTone.all.count)))
  }

  /// FNV-1a sobre os bytes. `hashValue` muda a cada execução do app.
  static func stableHash(_ text: String) -> UInt64 {
    text.utf8.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
  }
}

private struct WorkoutTile: View {
  let item: WeekPlanItem
  let showsWave: Bool
  let onEdit: (EditorStep) -> Void
  let onDelete: () -> Void
  let onStart: () -> Void
  let onTrainToday: (() -> Void)?
  @State private var confirmDelete = false

  var body: some View {
    // Sem dia, o que falta é o dia, então a pasta abre direto nesse passo.
    Button(action: item.weekdays.isEmpty ? { onEdit(.dias) } : onStart) {
      WorkoutFolderCard(
        name: item.name.lowercased(), tone: item.tone, weekdays: item.weekdays,
        exerciseCount: item.exerciseCount, showsWave: showsWave)
    }
    .buttonStyle(StudyPressStyle())
    .accessibilityLabel(item.weekdays.isEmpty ? "editar \(item.name), sem dia" : "\(item.name), \(spokenWeekdays(item.weekdays))")
    .accessibilityHint(item.weekdays.isEmpty ? "" : "abre o próximo dia deste treino")
    .accessibilityIdentifier("plano.pasta")
    .contextMenu { menuItems }
    // Menu dentro do label de um Button nunca chega a receber o dedo. Por isso
    // ele vem numa camada por cima, com área de toque só no disco dos três pontos.
    .overlay {
      GeometryReader { geometry in
        menuLayer
          .position(x: geometry.size.width * 0.854, y: geometry.size.width * 0.394)
      }
    }
  }

  @ViewBuilder private var menuItems: some View {
    if let onTrainToday {
      Button("treinar hoje", systemImage: "play.fill", action: onTrainToday)
      Divider()
    }
    Button("editar", systemImage: "pencil") { onEdit(.identidade) }
    Button("cor", systemImage: "paintpalette") { onEdit(.cor) }
    Button("dias", systemImage: "calendar") { onEdit(.dias) }
    Button("exercícios", systemImage: "dumbbell") { onEdit(.exercicios) }
    Button("apagar", systemImage: "trash", role: .destructive) { confirmDelete = true }
  }

  private var menuLayer: some View {
    Menu {
      menuItems
    } label: {
      Color.clear
        .frame(width: 44, height: 44)
        .contentShape(.rect)
    }
    .accessibilityLabel("editar \(item.name)")
    // Preso nos três pontos, o diálogo aponta para o card que vai sumir. Preso
    // na tela, ele abria no topo, longe do toque.
    .deleteWorkoutConfirmation(isPresented: $confirmDelete, name: item.name, onDelete: onDelete)
  }
}

struct WorkoutFolderCard: View {
  @Environment(\.dynamicTypeSize) private var textSize
  @ScaledMetric(relativeTo: .headline) private var titleSize = 44.0
  @ScaledMetric(relativeTo: .subheadline) private var footerSize = 35.0
  let name: String
  let tone: WorkoutTone
  let weekdays: [Int]
  var exerciseCount: Int?
  var showsWave = false

  private var hasDays: Bool { !weekdays.isEmpty }

  /// "seg · qui", na ordem da semana de treino.
  private var shortDays: String {
    let start = Calendar.trainingWeek.firstWeekday - 1
    return weekdays.sorted { ($0 - start + 7) % 7 < ($1 - start + 7) % 7 }
      .map { planWeekdaysShort[$0] }
      .joined(separator: " · ")
  }

  private var extraTitleHeight: CGFloat { textSize.isAccessibilitySize ? 0 : max(0, titleSize - 44) * 2.4 }
  private var extraFooterHeight: CGFloat { textSize.isAccessibilitySize ? 60 : max(0, footerSize - 35) * 2.6 }

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      let scale = width / 508
      ZStack(alignment: .topLeading) {
        RoundedRectangle(cornerRadius: 40 * scale)
          .fill(Color(hex: 0xdedfe2))
          .frame(width: 225 * scale, height: 180 * scale)
        RoundedRectangle(cornerRadius: 52 * scale)
          .fill(Color(hex: 0xf0f1f3))
          .overlay {
            RoundedRectangle(cornerRadius: 52 * scale)
              .strokeBorder(Color.ink.opacity(0.07), lineWidth: scale)
          }
          .padding(.top, 32 * scale)
        RoundedRectangle(cornerRadius: 25 * scale)
          .fill(tone.top.mix(with: .ink, by: 0.38))
          .frame(width: 466 * scale, height: 210 * scale)
          .rotationEffect(.degrees(-1.5))
          .offset(x: 24 * scale, y: 37 * scale)
        RoundedRectangle(cornerRadius: 27 * scale)
          .fill(tone.top)
          .frame(width: 475 * scale, height: 220 * scale)
          .rotationEffect(.degrees(1))
          .offset(x: 20 * scale, y: 52 * scale)
        RoundedRectangle(cornerRadius: 27 * scale)
          .fill(tone.top.mix(with: Color(hex: 0xf3f5f7), by: 0.30))
          .frame(width: 486 * scale, height: 250 * scale)
          .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 10 * scale) {
              Capsule().frame(width: 252 * scale, height: 6 * scale)
              Capsule().frame(width: 136 * scale, height: 5 * scale)
            }
            .foregroundStyle(tone.ink.opacity(0.22))
            .padding(.leading, 35 * scale)
            .padding(.top, 18 * scale)
          }
          .offset(x: 11 * scale, y: 67 * scale)
        front(scale: scale)
          .frame(width: width, height: (328 + extraTitleHeight + extraFooterHeight) * scale)
          .offset(y: 127 * scale)
      }
      .compositingGroup()
      .shadow(color: Color.ink.opacity(0.12), radius: 26 * scale, y: 20 * scale)
    }
    .aspectRatio(508 / (455 + extraTitleHeight + extraFooterHeight), contentMode: .fit)
  }

  private func front(scale: CGFloat) -> some View {
    let shape = RoundedRectangle(cornerRadius: 57 * scale)
    let textScale = textSize.isAccessibilitySize ? min(scale, 180.0 / 508) : scale
    return ZStack(alignment: .topLeading) {
      shape.fill(.ultraThinMaterial)
      shape.fill(
        LinearGradient(stops: [
          .init(color: tone.bottom.opacity(0.78), location: 0),
          .init(color: tone.bottom.opacity(0.78), location: 0.48),
          .init(color: Color(hex: 0xf2f3f6).opacity(0.95), location: 0.76),
          .init(color: Color(hex: 0xf2f3f6), location: 1),
        ], startPoint: .top, endPoint: .bottom))
      if showsWave {
        WorkoutWave(closed: true)
          .fill(LinearGradient(stops: [
            .init(color: tone.top.opacity(0.12), location: 0),
            .init(color: tone.top.opacity(0.12), location: 0.52),
            .init(color: tone.top.opacity(0), location: 1),
          ], startPoint: .top, endPoint: .bottom))
          .overlay { WorkoutWave().stroke(tone.top.opacity(0.3), lineWidth: 1) }
          .frame(height: 180 * scale)
          .offset(y: 40 * scale)
      }
      Text(name)
        .font(.system(size: titleSize * textScale, weight: .bold))
        .tracking(-1 * scale)
        .foregroundStyle(Color.ink)
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 43 * scale)
        .padding(.trailing, 130 * scale)
        .padding(.top, 46 * scale)
      Circle()
        .fill(tone.ink.opacity(0.10))
        .overlay { Circle().strokeBorder(tone.ink.opacity(0.13), lineWidth: scale) }
        .overlay {
          VStack(spacing: 8 * scale) {
            ForEach(0..<3) { _ in Circle().frame(width: 8 * scale, height: 8 * scale) }
          }
          .foregroundStyle(Color.ink)
        }
        .frame(width: 87 * scale, height: 87 * scale)
        .offset(x: 389 * scale, y: 29 * scale)
        .accessibilityHidden(true)
      VStack(spacing: 0) {
        if hasDays {
          // Com dias e exercícios na mesma linha quando cabem; senão só os
          // dias, encolhendo até caber.
          ViewThatFits(in: .horizontal) {
            HStack(spacing: 14 * scale) {
              Text(shortDays)
              if let exerciseCount, exerciseCount > 0 {
                HStack(spacing: 5 * scale) {
                  Image(systemName: "dumbbell.fill").imageScale(.small)
                  Text("\(exerciseCount)").monospacedDigit()
                }
                .foregroundStyle(tone.ink.opacity(0.6))
              }
            }
            .fixedSize()
            Text(shortDays).minimumScaleFactor(0.5)
          }
          .font(.system(size: footerSize * textScale, weight: .semibold))
          .lineLimit(1)
          .foregroundStyle(tone.ink)
          .padding(.horizontal, 24 * scale)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .accessibilityHidden(true)
        } else {
          Text("sem dia")
            .font(.system(size: footerSize * textScale, weight: .semibold))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 24 * scale)
            .foregroundStyle(Color.mutedInk)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .frame(height: (97 + extraFooterHeight) * scale)
      .frame(maxHeight: .infinity, alignment: .bottom)
    }
    .clipShape(shape)
    .overlay {
      shape.strokeBorder(
        LinearGradient(colors: [Color(hex: 0xf7fbff).opacity(0.65), Color.ink.opacity(0.06)],
          startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2 * scale)
    }
  }
}

private struct WorkoutWave: Shape {
  /// Fechada vira a faixa clara da metade de baixo, aberta vira só o traço.
  var closed = false

  func path(in rect: CGRect) -> Path {
    let base = rect.minY + rect.height * 0.52
    let amp = rect.height * 0.085
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: base))
    path.addQuadCurve(to: CGPoint(x: rect.midX, y: base),
                      control: CGPoint(x: rect.minX + rect.width * 0.25, y: base - amp))
    path.addQuadCurve(to: CGPoint(x: rect.maxX, y: base),
                      control: CGPoint(x: rect.midX + rect.width * 0.25, y: base + amp))
    if closed {
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
      path.closeSubpath()
    }
    return path
  }
}

/// Um exercício do plano. Fechado é uma linha só, "2 + 2 × 6–10 · 1:30"; o
/// toque abre os controles. Sem `onToggle` fica sempre aberto.
struct PlanExerciseRow: View {
  @Environment(\.accent) private var accent
  @Environment(\.dynamicTypeSize) private var textSize
  @Binding var exercise: PlanExercise
  let name: String
  let subtitle: String?
  let imageUrl: String?
  let isOrganizing: Bool
  let isExpanded: Bool
  let onToggle: (() -> Void)?
  let onRemove: (() -> Void)?
  /// Um campo de carga ganhou o foco. Quem mostra a linha rola para ela ficar
  /// acima do teclado.
  let onFieldFocus: () -> Void
  @State private var history: ExerciseHistoryTarget?

  init(
    exercise: Binding<PlanExercise>, name: String, subtitle: String? = nil,
    imageUrl: String? = nil, isOrganizing: Bool = false, isExpanded: Bool = true,
    onToggle: (() -> Void)? = nil, onRemove: (() -> Void)? = nil,
    onFieldFocus: @escaping () -> Void = {}
  ) {
    _exercise = exercise
    self.name = name
    self.subtitle = subtitle
    self.imageUrl = imageUrl
    self.isOrganizing = isOrganizing
    self.isExpanded = isExpanded
    self.onToggle = onToggle
    self.onRemove = onRemove
    self.onFieldFocus = onFieldFocus
  }

  private var showsControls: Bool { !isOrganizing && (isExpanded || onToggle == nil) }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: Space.m) {
        if let onToggle, !isOrganizing {
          Button(action: onToggle) { header.contentShape(.rect) }
            .buttonStyle(StudyPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name.lowercased())
            .accessibilityValue(spokenSummary)
            .accessibilityHint(isExpanded ? "fechar ajustes" : "abrir ajustes")
            .accessibilityAction(named: "remover do treino") { onRemove?() }
        } else if isOrganizing {
          header
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name.lowercased())
            .accessibilityValue(spokenSummary)
        } else {
          header
        }
        // Com o cabeçalho abrindo e fechando, o canto direito é o chevron. Um
        // lixo ali apagava o exercício de quem tocava para fechar; na lista o
        // remover é o deslize.
        if showsControls, onToggle == nil, let onRemove {
          IconButton(title: "Remover \(name) do treino", systemImage: "trash", size: 17, action: onRemove)
            .tint(.red)
        }
      }
      .padding(.top, showsControls ? 6 : 0)
      if showsControls {
        Divider()
        ExerciseStepperRow(label: "aquecimento", value: $exercise.prepSets, range: Limits.prepSets)
        Divider()
        ExerciseStepperRow(label: "valendo", value: $exercise.workSets, range: Limits.workSets)
        Divider()
        ExerciseStepperRow(label: "reps mín.", value: $exercise.repsMin, range: Limits.planReps)
        Divider()
        ExerciseStepperRow(label: "reps máx.", value: $exercise.repsMax, range: Limits.planReps)
        Divider()
        WeightStepper(weightKg: $exercise.startingWeightKg, onFocus: onFieldFocus)
        Divider()
        PrepWeightRow(weightKg: $exercise.prepWeightKg, onFocus: onFieldFocus)
        Divider()
        RestStepperRow(seconds: $exercise.restSeconds)
        Divider()
        Toggle("até a falha", isOn: $exercise.workToFailure)
          .font(.body)
          .frame(minHeight: 48)
        Divider()
        Button {
          history = ExerciseHistoryTarget(id: exercise.exerciseId, name: name)
        } label: {
          HStack {
            Label("histórico", systemImage: "chart.line.uptrend.xyaxis")
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.mutedInk)
          }
          .font(.body).foregroundStyle(Color.ink)
          .frame(minHeight: 48).contentShape(.rect)
        }
        .buttonStyle(StudyPressStyle())
      }
    }
    .padding(.vertical, showsControls ? 10 : 4)
    // Um stepper empurra o outro, e a faixa nunca fica invertida.
    .onChange(of: exercise.repsMin) { _, new in
      if new > exercise.repsMax { exercise.repsMax = new }
    }
    .onChange(of: exercise.repsMax) { _, new in
      if new < exercise.repsMin { exercise.repsMin = new }
    }
    .exerciseHistorySheet(item: $history)
  }

  /// Nos tamanhos de acessibilidade a foto sobe para cima do nome, e o nome e
  /// o resumo ficam com a largura toda em vez de quebrar sílaba ao lado dela.
  @ViewBuilder private var header: some View {
    if textSize.isAccessibilitySize, !isOrganizing {
      VStack(alignment: .leading, spacing: Space.s) {
        HStack {
          ExerciseThumb(imageUrl: imageUrl, size: 48)
          Spacer(minLength: 0)
          chevron
        }
        titles
      }
    } else {
      HStack(spacing: Space.m) {
        // Organizando, a linha encolhe para caberem muitas na tela: foto menor,
        // nome numa linha e sem o resumo.
        ExerciseThumb(imageUrl: imageUrl, size: isOrganizing ? 36 : 48)
        titles
        Spacer(minLength: 0)
        chevron
      }
    }
  }

  private var titles: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(name.lowercased()).font(.headline.weight(.semibold)).foregroundStyle(Color.ink)
        .lineLimit(isOrganizing ? 1 : nil)
      if onToggle != nil, !isOrganizing {
        summaryText.font(.caption).foregroundStyle(Color.mutedInk)
      } else if !isOrganizing, let subtitle {
        Text(subtitle).font(.caption).foregroundStyle(Color.mutedInk)
      }
    }
  }

  @ViewBuilder private var chevron: some View {
    if onToggle != nil, !isOrganizing {
      Image(systemName: "chevron.down")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Color.mutedInk)
        .rotationEffect(.degrees(isExpanded ? 180 : 0))
        .frame(width: 44, height: 44)
    }
  }

  /// O raio vem logo depois das repetições, no mesmo lugar do resumo da
  /// sessão: "2 + 2 × 6–8 ⚡ · 1:30 · 37,5 kg". Um `Text` só, para quebrar
  /// entre palavras quando o texto cresce.
  private var summaryText: Text {
    let parts = exercise.summaryParts
    let bolt = exercise.workToFailure
      ? Text(" \(Image(systemName: "bolt.fill"))").font(.caption2).foregroundStyle(accent.base) : Text("")
    let tail = parts.tail.map { " · \($0)" }.joined()
    return Text("\(parts.setsAndReps)\(bolt)\(tail)").monospacedDigit()
  }

  private var spokenSummary: String {
    var parts: [String] = []
    if exercise.prepSets > 0 { parts.append("\(exercise.prepSets) de aquecimento") }
    let reps = exercise.repsMin == exercise.repsMax
      ? "\(exercise.repsMin) repetições" : "de \(exercise.repsMin) a \(exercise.repsMax) repetições"
    parts.append("\(exercise.workSets) valendo, \(reps)")
    parts.append("descanso \(restClock(TimeInterval(exercise.restSeconds ?? defaultRestSeconds)))")
    if exercise.startingWeightKg > 0 { parts.append("carga \(formatPrepWeight(exercise.startingWeightKg)) quilos") }
    if exercise.workToFailure { parts.append("até a falha") }
    return parts.joined(separator: ", ")
  }
}

extension PlanExercise {
  /// "2 + 2 × 6–10 · 1:30 · 40 kg": aquecimento + valendo, a faixa de
  /// repetições, o descanso e a carga inicial quando tem. Sem aquecimento,
  /// "2 × 6–10 · 1:30".
  var summary: String {
    let parts = summaryParts
    return ([parts.setsAndReps] + parts.tail).joined(separator: " · ")
  }

  /// As séries e a faixa, e depois o descanso e a carga quando tem.
  var summaryParts: (setsAndReps: String, tail: [String]) {
    let sets = prepSets > 0 ? "\(prepSets) + \(workSets)" : "\(workSets)"
    let reps = repsMin == repsMax ? "\(repsMin)" : "\(repsMin)–\(repsMax)"
    var tail = [restClock(TimeInterval(restSeconds ?? defaultRestSeconds))]
    if startingWeightKg > 0 { tail.append("\(formatPrepWeight(startingWeightKg)) kg") }
    return ("\(sets) × \(reps)", tail)
  }
}

/// A carga do aquecimento. Vazio deixa o servidor calcular a partir do último
/// aquecimento, que é o normal; o campo existe para quem quer fixar.
///
/// O campo edita texto e grava o número a cada tecla. Com `value:format:` o
/// número só chegava ao rascunho quando o campo perdia o foco, e tocar em
/// "concluir" com o teclado aberto salvava sem ele.
private struct PrepWeightRow: View {
  @Binding var weightKg: Double?
  var onFocus: () -> Void = {}
  @State private var text = ""
  @FocusState private var focused: Bool

  var body: some View {
    AdjustRow(label: "carga do aquecimento") {
      TextField("auto", text: $text)
        .focused($focused)
        .submitLabel(.done)
        .decimalInput()
        .multilineTextAlignment(.trailing)
        .font(.body.weight(.semibold)).monospacedDigit()
        .frame(width: 72)
        .accessibilityLabel("Carga do aquecimento em kg, vazio calcula sozinho")
        .accessibilityIdentifier("plano.carga-aquecimento")
      Text("kg").font(.callout).foregroundStyle(Color.mutedInk)
    }
    .onChange(of: weightKg, initial: true) { _, new in
      if !focused { text = new.map(formatPrepWeight) ?? "" }
    }
    .onChange(of: text) { _, new in weightKg = parsePrepWeight(new) }
    .onChange(of: focused) { _, isFocused in
      if isFocused { onFocus() } else { text = weightKg.map(formatPrepWeight) ?? "" }
    }
  }
}

/// Etiqueta de um lado e controle do outro, em 48 pt de altura. Nos tamanhos
/// de acessibilidade a etiqueta vai para cima e o controle para baixo, para
/// nenhuma palavra quebrar no meio.
struct AdjustRow<Control: View>: View {
  @Environment(\.dynamicTypeSize) private var textSize
  let label: String
  @ViewBuilder let control: Control

  var body: some View {
    if textSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: Space.xs) {
        Text(label).font(.body)
        HStack(spacing: Space.s) {
          Spacer(minLength: 0)
          control
        }
      }
      .padding(.vertical, Space.xs)
    } else {
      HStack(spacing: Space.s) {
        Text(label).font(.body).lineLimit(1)
        Spacer(minLength: 8)
        control
      }
      .frame(minHeight: 48)
    }
  }
}

func formatPrepWeight(_ value: Double) -> String {
  value.formatted(
    .number.precision(.fractionLength(0...2)).grouping(.never).locale(Locale(identifier: "pt_BR")))
}

/// Vírgula ou ponto, porque o teclado decimal em português dá vírgula. Vazio
/// ou ilegível é "calcular sozinho".
func parsePrepWeight(_ text: String) -> Double? {
  parseDecimal(text)?.clamped(to: Limits.startingWeightKg)
}

/// O descanso entre séries desse exercício, de 15 em 15 segundos.
private struct RestStepperRow: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Binding var seconds: Int?

  var body: some View {
    let value = seconds ?? defaultRestSeconds
    AdjustRow(label: "descanso") {
      Text(restClock(TimeInterval(value))).font(.body.weight(.semibold)).monospacedDigit()
        .contentTransition(.numericText(value: Double(value)))
        .animation(Motion.resolve(Motion.tap, reduceMotion), value: value)
        .frame(minWidth: 44, alignment: .trailing)
      Stepper(
        "", value: Binding(get: { value }, set: { seconds = $0 }), in: Limits.restSeconds, step: 15
      )
      .labelsHidden()
      .accessibilityLabel("descanso")
      .accessibilityValue(restClock(TimeInterval(value)))
    }
    .sensoryFeedback(.selection, trigger: value)
  }
}

/// Um controle por linha, etiqueta de um lado e stepper do outro. Cada linha
/// tem 48 de altura para o dedo acertar sem mirar, e o número em tabular não
/// empurra o stepper quando vai de 9 para 10.
struct ExerciseStepperRow: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let label: String
  @Binding var value: Int
  let range: ClosedRange<Int>

  var body: some View {
    AdjustRow(label: label) {
      Text("\(value)").font(.body.weight(.semibold)).monospacedDigit()
        .contentTransition(.numericText(value: Double(value)))
        .animation(Motion.resolve(Motion.tap, reduceMotion), value: value)
        .frame(minWidth: 32, alignment: .trailing)
        .accessibilityHidden(true)
      Stepper("", value: $value, in: range)
        .labelsHidden()
        .accessibilityLabel(label)
        .accessibilityValue("\(value)")
    }
    .sensoryFeedback(.selection, trigger: value)
  }
}

/// A miniatura do exercício. Foto quando tem, halter quando não tem. O contorno
/// fino separa a foto do fundo sem virar borda dura.
struct ExerciseThumb: View {
  let imageUrl: String?
  let size: CGFloat
  private var radius: CGFloat { size * 0.32 }

  var body: some View {
    Group {
      if let imageUrl, let url = URL(string: imageUrl) {
        AsyncImage(url: url) { phase in
          switch phase {
          case .success(let image):
            image.resizable().scaledToFill()
              .transition(.opacity)
          default:
            RoundedRectangle(cornerRadius: radius).fill(Color.surfaceMuted)
              .overlay { Image(systemName: "dumbbell").foregroundStyle(Color.mutedInk.opacity(0.5)) }
          }
        }
      } else {
        RoundedRectangle(cornerRadius: radius).fill(Color.surfaceMuted)
          .overlay { Image(systemName: "dumbbell").foregroundStyle(Color.mutedInk.opacity(0.6)) }
      }
    }
    .frame(width: size, height: size)
    .clipShape(.rect(cornerRadius: radius))
    .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color.black.opacity(0.1)))
    .accessibilityHidden(true)
  }
}

struct ExercisePicker: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @FocusState private var searchFocused: Bool
  @State private var search = ""
  @State private var muscle: String?
  @State private var remote: [ExerciseCatalogItem] = []
  @State private var remotePhase: RemotePhase = .idle
  @State private var lookup: Task<Void, Never>?
  @State private var pickedHere = 0
  /// Os escolhidos nesta abertura. Só eles saem com um toque; os que já
  /// estavam no treino ficam travados para não apagar ajuste sem querer.
  @State private var pickedIds: Set<String> = []
  @State private var refusals = 0
  /// Liga na primeira tecla. Daí em diante as linhas que voltam à lista
  /// aparecem sem a cascata, que a cada letra fazia a lista piscar.
  @State private var settled = false

  let catalog: [ExerciseCatalogItem]
  let chosen: Set<String>
  let onPick: (ExerciseCatalogItem) -> Void
  var onUnpick: ((String) -> Void)?
  private let wger = WgerClient.shared

  private var isFull: Bool { chosen.count >= Limits.exerciseCount.upperBound }

  private enum RemotePhase: Equatable {
    case idle, loading, done, failed
  }

  private var library: [ExerciseCatalogItem] {
    ExerciseLibrary.merged(with: catalog)
  }

  private var local: [ExerciseCatalogItem] {
    ExerciseLibrary.search(search, muscle: muscle, in: library)
  }

  private var exactMatch: Bool {
    let folded = ExerciseLibrary.fold(search.trimmingCharacters(in: .whitespaces))
    guard !folded.isEmpty else { return false }
    return library.contains { ExerciseLibrary.fold($0.name) == folded }
  }

  private var canCreate: Bool {
    Limits.exerciseNameLength.contains(search.trimmingCharacters(in: .whitespaces).count) && !exactMatch
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
          Section {
            if local.isEmpty, remote.isEmpty, remotePhase == .idle || remotePhase == .done, !search.isEmpty {
              // Sem resultado, a ação que resolve vem primeiro, acima do
              // teclado.
              if canCreate { createRow }
              ContentUnavailableView(
                "sem \"\(search.trimmingCharacters(in: .whitespaces))\" no catálogo",
                systemImage: "magnifyingglass")
            } else {
              ForEach(Array(local.enumerated()), id: \.element.id) { index, item in
                row(item)
                  .firstEntrance(index: index, settled: settled)
                Divider().padding(.leading, 76).opacity(0.6)
              }
              if !remote.isEmpty {
                HStack {
                  Text("wger").font(.caption).foregroundStyle(Color.mutedInk)
                  Spacer()
                  Text("em inglês").font(.caption2).foregroundStyle(Color.mutedInk.opacity(0.7))
                }
                .padding(.horizontal, Space.l).padding(.top, 18).padding(.bottom, Space.xs)
                ForEach(Array(remote.enumerated()), id: \.element.id) { index, item in
                  row(item)
                    .staggeredEntrance(index: index, isReady: remotePhase == .done)
                  Divider().padding(.leading, 76).opacity(0.6)
                }
                Text("fotos wger.de, CC-BY-SA")
                  .font(.caption2).foregroundStyle(Color.mutedInk.opacity(0.7))
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(.horizontal, Space.l).padding(.vertical, 10)
              } else if remotePhase == .loading {
                HStack(spacing: Space.s) {
                  ProgressView().controlSize(.small)
                  Text("buscando na wger").font(.caption).foregroundStyle(Color.mutedInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(Space.l)
              } else if remotePhase == .failed {
                HStack(spacing: Space.s) {
                  Image(systemName: "wifi.exclamationmark")
                    .accessibilityLabel("a wger não respondeu")
                  Spacer(minLength: 8)
                  Button("tentar de novo", systemImage: "arrow.clockwise") { scheduleRemote() }
                    .frame(minHeight: 44)
                }
                .font(.subheadline).foregroundStyle(Color.mutedInk)
                .padding(.horizontal, Space.l).padding(.vertical, Space.xs)
              }
              // Fora do vazio também, porque achar parecido não quer dizer
              // achar o que se procura.
              if canCreate { createRow }
            }
          } header: {
            VStack(spacing: 10) {
              HStack(spacing: Space.s) {
                Image(systemName: "magnifyingglass")
                  .foregroundStyle(Color.mutedInk)
                  .padding(.leading, 2)
                TextField("buscar", text: $search)
                  .submitLabel(.done)
                  .focused($searchFocused)
                  #if os(iOS)
                  .textInputAutocapitalization(.never)
                  #endif
                  .autocorrectionDisabled()
                  .accessibilityLabel("Buscar exercício")
                if !search.isEmpty {
                  IconButton(title: "Limpar busca", systemImage: "xmark.circle.fill", size: 17) { search = "" }
                    .tint(Color.mutedInk)
                    // Sem isso o botão de 44pt estica o campo de 32 para 56.
                    .padding(.vertical, -12).padding(.trailing, -10)
                }
              }
              .padding(.horizontal, Space.m).padding(.vertical, 6)
              .fieldSurface()
              .padding(.horizontal, Space.l)
              ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                  MuscleChip(title: "todos", selected: muscle == nil) { muscle = nil }
                  ForEach(ExerciseLibrary.muscleGroups, id: \.self) { group in
                    MuscleChip(title: group.lowercased(), selected: muscle == group) {
                      muscle = muscle == group ? nil : group
                    }
                  }
                }.padding(.horizontal, Space.l).padding(.vertical, 2)
              }
              if isFull {
                Label("limite de \(Limits.exerciseCount.upperBound) exercícios", systemImage: "exclamationmark.circle")
                  .font(.footnote).foregroundStyle(Color.mutedInk)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(.horizontal, Space.l)
                  .transition(.opacity)
              }
            }
            .padding(.top, Space.s).padding(.bottom, 6)
            .background(Color.canvas)
          }
        }
      }
      .background(Color.canvas)
      .animation(Motion.resolve(Motion.subtleEntrance, reduceMotion), value: isFull)
      .navigationTitle(isFull ? "\(chosen.count) de \(Limits.exerciseCount.upperBound)" : "exercícios")
      .toolbarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Group {
            if pickedHere > 0 {
              Button(role: .confirm) { dismiss() }
            } else {
              Button("fechar", systemImage: "xmark", role: .close) { dismiss() }
            }
          }
          .accessibilityIdentifier("seletor.fechar")
        }
      }
      .keyboardDone()
      .onAppear { searchFocused = true }
      .task { await wger.prefetch() }
      .sensoryFeedback(.success, trigger: pickedHere)
      .sensoryFeedback(.warning, trigger: refusals)
      .onChange(of: search) {
        settled = true
        scheduleRemote()
      }
      .onChange(of: muscle) {
        settled = true
        scheduleRemote()
      }
    }
  }

  private var createRow: some View {
    Button { createCustom() } label: {
      HStack(spacing: Space.m) {
        RoundedRectangle(cornerRadius: 56 * 0.32).fill(Color.surfaceMuted).frame(width: 56, height: 56)
          .overlay { Image(systemName: "plus").foregroundStyle(Color.mutedInk) }
        VStack(alignment: .leading, spacing: 2) {
          Text("criar \"\(search.trimmingCharacters(in: .whitespaces))\"")
            .font(.body.weight(.medium)).foregroundStyle(Color.ink)
          Text(muscle?.lowercased() ?? "geral")
            .font(.caption).foregroundStyle(Color.mutedInk)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, Space.l).padding(.vertical, Space.s)
      .contentShape(.rect)
      .opacity(isFull ? 0.55 : 1)
    }.buttonStyle(StudyPressStyle())
  }

  private func row(_ item: ExerciseCatalogItem) -> ExercisePickerRow {
    let picked = chosen.contains(item.id)
    let canUnpick = picked && onUnpick != nil && pickedIds.contains(item.id)
    return ExercisePickerRow(
      item: item, picked: picked, isFull: isFull,
      action: { pick(item) },
      onUnpick: canUnpick ? { unpick(item.id) } : nil)
  }

  /// A folha fica aberta para montar o treino de uma vez. A linha passa a "no
  /// treino" porque `chosen` chega de novo de quem abriu. Cheio, o toque não
  /// entra e avisa na hora, em vez de deixar o editor reclamar no "concluir".
  private func pick(_ item: ExerciseCatalogItem) {
    guard !chosen.contains(item.id) else { return }
    guard !isFull else { return refuse() }
    onPick(item)
    pickedIds.insert(item.id)
    pickedHere += 1
    if chosen.count + 1 >= Limits.exerciseCount.upperBound { announceLimit() }
  }

  private func unpick(_ id: String) {
    onUnpick?(id)
    pickedIds.remove(id)
    pickedHere -= 1
  }

  private func refuse() {
    refusals += 1
    announceLimit()
  }

  private func announceLimit() {
    AccessibilityNotification.Announcement("limite de \(Limits.exerciseCount.upperBound) exercícios").post()
  }

  private func createCustom() {
    let name = search.trimmingCharacters(in: .whitespaces)
    guard Limits.exerciseNameLength.contains(name.count) else { return }
    let item = ExerciseCatalogItem(
      id: ExerciseLibrary.slug(name), name: name,
      muscleGroup: muscle ?? "Geral", equipment: "Livre", imageUrl: nil)
    guard !chosen.contains(item.id) else { return }
    guard !isFull else { return refuse() }
    onPick(item)
    pickedIds.insert(item.id)
    pickedHere += 1
    search = ""
  }

  private func scheduleRemote() {
    lookup?.cancel()
    remote = []
    remotePhase = .idle
    let term = search.trimmingCharacters(in: .whitespaces)
    let scope = library
    let group = muscle
    let client = wger
    let animated = !reduceMotion
    guard term.count >= 3, local.count < 8 else { return }
    remotePhase = .loading
    lookup = Task {
      try? await Task.sleep(for: .milliseconds(500))
      guard !Task.isCancelled else { return }
      do {
        let found = try await client.search(term, muscle: group, excluding: scope)
        guard !Task.isCancelled else { return }
        withAnimation(animated ? Motion.subtleEntrance : nil) {
          remote = found
          remotePhase = .done
        }
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled else { return }
        remotePhase = .failed
      }
    }
  }
}

private struct MuscleChip: View {
  let title: String
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.subheadline.weight(selected ? .semibold : .regular))
        .foregroundStyle(selected ? .white : Color.ink)
        .padding(.horizontal, Space.l).frame(minHeight: 44)
        .modifier(StudyChipSurface(isActive: selected))
        .contentShape(.capsule)
    }
    .buttonStyle(StudyPressStyle())
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

struct ExercisePickerRow: View {
  @Environment(\.accent) private var accent
  let item: ExerciseCatalogItem
  let picked: Bool
  /// O treino chegou ao limite: o "+" apaga, mas o toque continua chegando
  /// para o seletor avisar.
  var isFull = false
  let action: () -> Void
  /// Presente só nos escolhidos nesta abertura do seletor: tocar de novo tira.
  var onUnpick: (() -> Void)?

  var body: some View {
    Button(action: onUnpick ?? action) {
      HStack(spacing: Space.m) {
        ExerciseThumb(imageUrl: item.imageUrl, size: 56)
        VStack(alignment: .leading, spacing: 3) {
          Text(item.name.lowercased())
            .font(.body.weight(.medium)).foregroundStyle(Color.ink)
            .lineLimit(2)
          Text("\(item.muscleGroup.lowercased()) · \(item.equipment.lowercased())")
            .font(.caption).foregroundStyle(Color.mutedInk)
            .lineLimit(1)
        }
        Spacer(minLength: 8)
        if picked {
          HStack(spacing: 4) {
            if onUnpick != nil {
              Image(systemName: "checkmark.circle.fill").foregroundStyle(accent.base)
            }
            Text("no treino")
          }
          .font(.caption2.weight(.medium))
          .foregroundStyle(Color.mutedInk)
          .padding(.horizontal, 10).padding(.vertical, 6)
          .background(Color.surfaceMuted, in: .capsule)
        } else {
          Image(systemName: "plus.circle.fill")
            .font(.title2).foregroundStyle(Color.ink.opacity(isFull ? 0.25 : 0.75))
            .frame(width: 44, height: 44)
            .contentShape(.rect)
        }
      }
      .padding(.horizontal, Space.l).padding(.vertical, Space.s)
      .contentShape(.rect)
      .opacity(picked && onUnpick == nil ? 0.55 : 1)
    }
    .buttonStyle(StudyPressStyle())
    .disabled(picked && onUnpick == nil)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
  }

  private var accessibilityLabel: String {
    if picked {
      return onUnpick == nil ? "\(item.name) já está no treino" : "Tirar \(item.name) do treino"
    }
    return "Adicionar \(item.name)"
  }
}

#if DEBUG
  #Preview("Seletor de exercícios") {
    ExercisePicker(
      catalog: [
        ExerciseCatalogItem(
          id: "supino-reto-barra", name: "Supino reto com barra", muscleGroup: "Peito",
          equipment: "Barra",
          imageUrl:
            "https://wger.de/media/exercise-images/192/Bench-press-1.png.400x400_q85.png"),
        ExerciseCatalogItem(
          id: "puxada-fechada", name: "Puxada alta pegada fechada", muscleGroup: "Costas",
          equipment: "Cabo",
          imageUrl:
            "https://wger.de/media/exercise-images/158/0d51a0f2-622f-434b-beb8-1a003c54712a.png.400x400_q85.jpg"
        ),
        ExerciseCatalogItem(
          id: "panturrilha-em-pe", name: "Panturrilha em pé", muscleGroup: "Panturrilha",
          equipment: "Peso corporal",
          imageUrl:
            "https://wger.de/media/exercise-images/622/9a429bd0-afd3-4ad0-8043-e9beec901c81.jpeg.400x400_q85.jpg"
        ),
      ],
      chosen: ["supino-reto-barra"]
    ) { _ in }
  }

  #Preview("Linha do exercício") {
    PlanExercisePreview()
  }

  private struct PlanExercisePreview: View {
    @State private var exercise = PlanExercise(
      exerciseId: "panturrilha-em-pe", prepSets: 2, workSets: 2, repsMin: 8, repsMax: 12,
      workToFailure: true, startingWeightKg: 0)

    var body: some View {
      Form {
        PlanExerciseRow(
          exercise: $exercise, name: "Panturrilha em pé",
          subtitle: "panturrilha · peso corporal",
          imageUrl:
            "https://wger.de/media/exercise-images/622/9a429bd0-afd3-4ad0-8043-e9beec901c81.jpeg.400x400_q85.jpg"
        )
      }
    }
  }
#endif
