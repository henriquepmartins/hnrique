import HenriqueCore
import SwiftUI

struct WeekScreen: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.dynamicTypeSize) private var textSize
  @State private var editor: PlanEditorDestination?
  @State private var editorStep: EditorStep = .identidade
  var onStart: (Int) -> Void = { _ in }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        PlanCalendarCard(
          attendance: store.attendance,
          weekPlan: store.weekPlan,
          swaps: store.dashboard?.daySwaps ?? [],
          load: { from, to in await store.loadAttendance(from: from, to: to) })
        Button("novo treino", systemImage: "plus") {
          editorStep = .identidade
          editor = .new(weekdays: [])
        }
          .buttonStyle(.glassProminent)
          .controlSize(.large)
          .subtleEntrance()
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                 count: textSize.isAccessibilitySize ? 1 : 2), spacing: 6) {
          ForEach(store.weekPlan) { item in
            WorkoutTile(
              item: item,
              showsWave: store.dashboard?.highlightedWorkoutIDs.contains(item.id) == true,
              onEdit: { step in
                editorStep = step
                editor = .existing(item)
              },
              onDelete: { store.deleteWorkout(workoutTemplateId: item.id) },
              onStart: { if let day = item.nextWeekday(from: store.selectedDate.weekday()) { onStart(day) } })
              .subtleEntrance()
          }
        }
      }
      .padding(16)
      .padding(.bottom, 32)
    }
    .background(Color.canvas)
    .refreshable { await store.load() }
    .sheet(item: $editor) { destination in
      WorkoutEditor(
        item: destination.item, weekdays: destination.weekdays,
        tone: destination.item?.tone ?? .unused(among: store.weekPlan.map(\.tone.hex)),
        catalog: store.dashboard?.exerciseCatalog ?? [],
        startingAt: editorStep)
    }
  }


}

private enum PlanEditorDestination: Identifiable {
  case new(weekdays: Set<Int>)
  case existing(WeekPlanItem)
  var id: String { item?.id ?? "new" }
  var item: WeekPlanItem? {
    if case .existing(let item) = self { return item }
    return nil
  }
  var weekdays: Set<Int> {
    switch self {
    case .new(let weekdays): weekdays
    case .existing(let item): Set(item.weekdays)
    }
  }
}

let planWeekdays = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"]
let planWeekdaysShort = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"]

/// "segunda e quinta". O locale fica preso no português porque o resto da tela
/// também é, e senão um aparelho em inglês lia "segunda and quinta".
func spokenWeekdays(_ weekdays: [Int]) -> String {
  weekdays.map { planWeekdays[$0] }.formatted(.list(type: .and).locale(StudyFormat.locale))
}

extension WeekPlanItem {
  /// Sem cor escolhida, a cor vem do dia e não da posição na grade. Pela
  /// posição, apagar um card repintava todos os que vinham depois.
  var tone: WorkoutTone {
    color.flatMap(WorkoutTone.from(hex:)) ?? .at(weekdays.first ?? 0)
  }
}

private struct WorkoutTile: View {
  let item: WeekPlanItem
  let showsWave: Bool
  let onEdit: (EditorStep) -> Void
  let onDelete: () -> Void
  let onStart: () -> Void
  @State private var confirmDelete = false

  var body: some View {
    Button(action: item.weekdays.isEmpty ? { onEdit(.identidade) } : onStart) {
      WorkoutFolderCard(name: item.name, tone: item.tone, hasDays: !item.weekdays.isEmpty, showsWave: showsWave)
    }
    .buttonStyle(StudyPressStyle())
    .accessibilityLabel(item.weekdays.isEmpty ? "editar \(item.name), sem dia" : "iniciar \(item.name), \(spokenWeekdays(item.weekdays))")
    // Menu dentro do label de um Button nunca chega a receber o dedo. Por isso
    // ele vem numa camada por cima, com área de toque só no disco dos três pontos.
    .overlay {
      GeometryReader { geometry in
        menuLayer
          .position(x: geometry.size.width * 0.854, y: geometry.size.width * 0.394)
      }
    }
  }

  private var menuLayer: some View {
    Menu {
      Button("editar", systemImage: "pencil") { onEdit(.identidade) }
      Button("cor", systemImage: "paintpalette") { onEdit(.cor) }
      Button("apagar", systemImage: "trash", role: .destructive) { confirmDelete = true }
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
  let hasDays: Bool
  var showsWave = false

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
        Text(hasDays ? "começar treino" : "sem dia")
          .font(.system(size: footerSize * textScale, weight: .semibold))
          .multilineTextAlignment(.center)
          .lineLimit(2)
          .padding(.horizontal, 24 * scale)
          .foregroundStyle(Color.mutedInk)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
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

struct PlanExerciseRow: View {
  @Binding var exercise: PlanExercise
  let name: String
  let subtitle: String?
  let imageUrl: String?
  let isOrganizing: Bool
  let onRemove: (() -> Void)?

  init(
    exercise: Binding<PlanExercise>, name: String, subtitle: String? = nil,
    imageUrl: String? = nil, isOrganizing: Bool = false, onRemove: (() -> Void)? = nil
  ) {
    _exercise = exercise
    self.name = name
    self.subtitle = subtitle
    self.imageUrl = imageUrl
    self.isOrganizing = isOrganizing
    self.onRemove = onRemove
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 12) {
        ExerciseThumb(imageUrl: imageUrl, size: 48)
        VStack(alignment: .leading, spacing: 3) {
          Text(name.lowercased()).font(.headline.weight(.semibold))
          if isOrganizing {
            Text("\(exercise.workSets) × \(exercise.repsMin)-\(exercise.repsMax)")
              .font(.caption).foregroundStyle(Color.mutedInk).monospacedDigit()
          } else if let subtitle {
            Text(subtitle).font(.caption).foregroundStyle(Color.mutedInk)
          }
        }
        Spacer(minLength: 0)
        if !isOrganizing, let onRemove {
          IconButton(title: "Remover \(name) do treino", systemImage: "trash", size: 17, action: onRemove)
            .tint(.red)
        }
      }
      .padding(.top, isOrganizing ? 0 : 6)
      if !isOrganizing {
        Divider()
        ExerciseStepperRow(label: "aquecimento", value: $exercise.prepSets, range: Limits.prepSets)
        Divider()
        ExerciseStepperRow(label: "valendo", value: $exercise.workSets, range: Limits.workSets)
        Divider()
        ExerciseStepperRow(label: "reps mín.", value: $exercise.repsMin, range: Limits.planReps)
        Divider()
        ExerciseStepperRow(label: "reps máx.", value: $exercise.repsMax, range: Limits.planReps)
        Divider()
        WeightStepper(weightKg: $exercise.startingWeightKg)
        Divider()
        PrepWeightRow(weightKg: $exercise.prepWeightKg)
        Divider()
        RestStepperRow(seconds: $exercise.restSeconds)
        Divider()
        Toggle("até a falha", isOn: $exercise.workToFailure)
          .font(.body)
          .frame(minHeight: 48)
      }
    }
    .padding(.vertical, 10)
  }
}

/// A carga do aquecimento. Vazio deixa o servidor calcular a partir do último
/// aquecimento, que é o normal; o campo existe para quem quer fixar.
private struct PrepWeightRow: View {
  @Binding var weightKg: Double?

  var body: some View {
    HStack(spacing: 8) {
      Text("carga do aquecimento").font(.body)
      Spacer(minLength: 8)
      TextField("auto", value: $weightKg, format: .number.precision(.fractionLength(0...2)))
        .submitLabel(.done)
        .decimalInput()
        .multilineTextAlignment(.trailing)
        .font(.body.weight(.semibold)).monospacedDigit()
        .frame(minWidth: 64)
        .accessibilityLabel("Carga do aquecimento em kg, vazio calcula sozinho")
      Text("kg").font(.callout).foregroundStyle(Color.mutedInk)
    }
    .frame(minHeight: 48)
    .onChange(of: weightKg) { _, new in
      guard let new else { return }
      let clamped = new.isFinite ? new.clamped(to: Limits.startingWeightKg) : nil
      if clamped != new { weightKg = clamped }
    }
  }
}

/// O descanso entre séries desse exercício, de 15 em 15 segundos.
private struct RestStepperRow: View {
  @Binding var seconds: Int?

  var body: some View {
    let value = seconds ?? defaultRestSeconds
    HStack(spacing: 12) {
      Text("descanso").font(.body)
      Spacer(minLength: 8)
      Text(restClock(TimeInterval(value))).font(.body.weight(.semibold)).monospacedDigit()
        .frame(minWidth: 44, alignment: .trailing)
      Stepper(
        "", value: Binding(get: { value }, set: { seconds = $0 }), in: Limits.restSeconds, step: 15
      )
      .labelsHidden()
      .accessibilityLabel("descanso")
      .accessibilityValue(restClock(TimeInterval(value)))
    }
    .frame(minHeight: 48)
  }
}

/// Um controle por linha, etiqueta de um lado e stepper do outro. Cada linha
/// tem 48 de altura para o dedo acertar sem mirar, e o número em tabular não
/// empurra o stepper quando vai de 9 para 10.
struct ExerciseStepperRow: View {
  let label: String
  @Binding var value: Int
  let range: ClosedRange<Int>

  var body: some View {
    HStack(spacing: 12) {
      Text(label).font(.body)
      Spacer(minLength: 8)
      Text("\(value)").font(.body.weight(.semibold)).monospacedDigit()
        .frame(minWidth: 32, alignment: .trailing)
      Stepper("", value: $value, in: range)
        .labelsHidden()
        .accessibilityLabel(label)
    }
    .frame(minHeight: 48)
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

  let catalog: [ExerciseCatalogItem]
  let chosen: Set<String>
  let onPick: (ExerciseCatalogItem) -> Void
  @State private var wger = WgerClient()

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

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
          Section {
            if local.isEmpty, remote.isEmpty, remotePhase != .loading, !search.isEmpty {
              ContentUnavailableView.search(text: search)
            } else {
              ForEach(Array(local.enumerated()), id: \.element.id) { index, item in
                ExercisePickerRow(
                  item: item, picked: chosen.contains(item.id),
                  action: { pick(item) }
                )
                .staggeredEntrance(index: index, isReady: true)
                Divider().padding(.leading, 76).opacity(0.6)
              }
              if !remote.isEmpty {
                HStack {
                  Text("wger").font(.caption).foregroundStyle(Color.mutedInk)
                  Spacer()
                  Text("em inglês").font(.caption2).foregroundStyle(Color.mutedInk.opacity(0.7))
                }
                .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 4)
                ForEach(Array(remote.enumerated()), id: \.element.id) { index, item in
                  ExercisePickerRow(
                    item: item, picked: chosen.contains(item.id),
                    action: { pick(item) }
                  )
                  .staggeredEntrance(index: index, isReady: remotePhase == .done)
                  Divider().padding(.leading, 76).opacity(0.6)
                }
                Text("fotos wger.de, CC-BY-SA")
                  .font(.caption2).foregroundStyle(Color.mutedInk.opacity(0.7))
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(.horizontal, 16).padding(.vertical, 10)
              } else if remotePhase == .loading {
                ProgressView().controlSize(.small)
                  .frame(maxWidth: .infinity, alignment: .leading).padding(16)
              }
              if !search.trimmingCharacters(in: .whitespaces).isEmpty, !exactMatch {
                Button { createCustom() } label: {
                  HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 56 * 0.32).fill(Color.surfaceMuted).frame(width: 56, height: 56)
                      .overlay { Image(systemName: "plus").foregroundStyle(Color.mutedInk) }
                    VStack(alignment: .leading, spacing: 2) {
                      Text("criar \"\(search.trimmingCharacters(in: .whitespaces))\"")
                        .font(.body.weight(.medium)).foregroundStyle(Color.ink)
                      Text(muscle ?? "geral")
                        .font(.caption).foregroundStyle(Color.mutedInk)
                    }
                    Spacer(minLength: 0)
                  }
                  .padding(.horizontal, 16).padding(.vertical, 8)
                  .contentShape(.rect)
                }.buttonStyle(StudyPressStyle())
              }
            }
          } header: {
            VStack(spacing: 10) {
              HStack(spacing: 8) {
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
              .padding(.horizontal, 12).padding(.vertical, 6)
              .background(.white, in: .rect(cornerRadius: 18))
              .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.ink.opacity(0.08)))
              ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                  MuscleChip(title: "todos", selected: muscle == nil) { muscle = nil }
                  ForEach(ExerciseLibrary.muscleGroups, id: \.self) { group in
                    MuscleChip(title: group.lowercased(), selected: muscle == group) {
                      muscle = muscle == group ? nil : group
                    }
                  }
                }.padding(.horizontal, 16).padding(.vertical, 2)
              }
            }
            .padding(.top, 8).padding(.bottom, 6)
            .background(Color.canvas)
          }
        }
      }
      .background(Color.canvas)
      .navigationTitle("exercícios")
      .toolbarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("fechar") { dismiss() }
        }
      }
      .keyboardDone()
      .onAppear { searchFocused = true }
      .onChange(of: search) { scheduleRemote() }
      .onChange(of: muscle) { scheduleRemote() }
    }
  }

  private func pick(_ item: ExerciseCatalogItem) {
    guard !chosen.contains(item.id) else { return }
    onPick(item)
    dismiss()
  }

  private func createCustom() {
    let name = search.trimmingCharacters(in: .whitespaces)
    guard name.count >= 2 else { return }
    let item = ExerciseCatalogItem(
      id: ExerciseLibrary.slug(name), name: name,
      muscleGroup: muscle ?? "Geral", equipment: "Livre", imageUrl: nil)
    guard !chosen.contains(item.id) else { return }
    onPick(item)
    dismiss()
  }

  private func scheduleRemote() {
    lookup?.cancel()
    remote = []
    remotePhase = .idle
    let term = search.trimmingCharacters(in: .whitespaces)
    let scope = library
    let client = wger
    let animated = !reduceMotion
    guard term.count >= 3, local.count < 8 else { return }
    remotePhase = .loading
    lookup = Task {
      try? await Task.sleep(for: .milliseconds(500))
      guard !Task.isCancelled else { return }
      do {
        let found = try await client.search(term, excluding: scope)
        guard !Task.isCancelled else { return }
        withAnimation(animated ? .easeOut(duration: 0.2) : nil) {
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
  let item: ExerciseCatalogItem
  let picked: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
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
          Text("no treino").font(.caption2.weight(.medium))
            .foregroundStyle(Color.mutedInk)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.surfaceMuted, in: .capsule)
            .accessibilityLabel("\(item.name) já está no treino")
        } else {
          Image(systemName: "plus.circle.fill")
            .font(.title2).foregroundStyle(Color.ink.opacity(0.75))
            .frame(width: 44, height: 44)
            .contentShape(.rect)
            .accessibilityLabel("Adicionar \(item.name)")
        }
      }
      .padding(.horizontal, 16).padding(.vertical, 8)
      .contentShape(.rect)
      .opacity(picked ? 0.55 : 1)
    }
    .buttonStyle(StudyPressStyle())
    .disabled(picked)
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
