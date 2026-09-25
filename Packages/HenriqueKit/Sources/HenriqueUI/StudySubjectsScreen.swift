import HenriqueCore
import SwiftUI

public struct StudySubjectRoute: Hashable, Sendable {
  public let id: String
  public init(id: String) { self.id = id }
}

public struct StudySubjectsScreen: View {
  @Environment(EstudosStore.self) private var store
  @Namespace private var cardSource

  public init() {}

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        switch store.subjects {
        case .idle, .loading:
          StudyLoadingState().transition(.blurReplace)
        case .failed(let message):
          StudyFailedState(message: message) { Task { await store.loadSubjects(force: true) } }
            .transition(.blurReplace)
        case .ready(let subjects):
          content(subjects).transition(.blurReplace)
        }
      }
      .animation(Motion.crossfade, value: store.subjects.phase)
      .padding(.horizontal, 16)
      .padding(.bottom, 32)
    }
    .studyPage()
    .task { await store.loadSubjects() }
    .refreshable { await store.loadSubjects(force: true) }
    // O cartão da grade cresce e vira a tela em vez de empurrar de lado. Quem
    // toca sabe de onde a tela veio, e voltar devolve a peça ao mesmo lugar.
    .navigationDestination(for: StudySubjectRoute.self) { route in
      StudySubjectScreen(id: route.id)
        .navigationTransition(.zoom(sourceID: route.id, in: cardSource))
    }
    .navigationDestination(for: NotebookPageRoute.self) { NotebookPageScreen(id: $0.id) }
  }

  @ViewBuilder
  private func content(_ subjects: [StudySubject]) -> some View {
    StudyHeading(eyebrow: semestreLabel(subjects), title: "matérias")

    if subjects.isEmpty {
      StudyEmptyState(icon: "book", title: "sem matérias")
    } else {
      LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
        ForEach(Array(subjects.enumerated()), id: \.element.id) { index, subject in
          NavigationLink(value: StudySubjectRoute(id: subject.id)) {
            StudySubjectCard(subject: subject)
          }
          .buttonStyle(StudyPressStyle())
          .matchedTransitionSource(id: subject.id, in: cardSource)
          .staggeredEntrance(index: index, columns: 2, isReady: true)
        }
      }
    }
  }
}

/// O semestre do cabeçalho é o que aparece em mais matérias. Uma optativa de
/// outro período não muda o rótulo da página inteira. O empate fica com quem
/// apareceu antes na lista, e não com a ordem do dicionário, que muda a cada
/// execução e faria o rótulo trocar sozinho entre duas aberturas do app.
private func semestreLabel(_ subjects: [StudySubject]) -> String? {
  var order: [Int] = []
  var tally: [Int: Int] = [:]
  for semester in subjects.compactMap(\.semester) {
    if tally[semester] == nil { order.append(semester) }
    tally[semester, default: 0] += 1
  }
  var winner: Int?
  var most = 0
  for semester in order where tally[semester, default: 0] > most {
    winner = semester
    most = tally[semester, default: 0]
  }
  return winner.map { "\($0)º semestre" }
}

struct StudySubjectCard: View {
  let subject: StudySubject

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        Image(systemName: "book").font(.system(size: 20)).offset(x: -1.5)
        Spacer(minLength: 8)
        if let code = subject.code {
          Text(code)
            .font(.system(size: 11, weight: .medium))
            .opacity(0.75)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 0)
      VStack(alignment: .leading, spacing: 3) {
        Text(subject.name)
          .font(.system(size: 16, weight: .semibold))
          .tracking(-0.18)
          .lineLimit(3)
        if let semester = subject.semester {
          Text("\(semester)º semestre").font(.caption).opacity(0.8)
        }
      }
    }
    .frame(maxWidth: .infinity, minHeight: 148, alignment: .leading)
    .padding(14)
    .foregroundStyle(Color.subjectInk(for: subject.color))
    .background(Color(hexString: subject.color), in: .rect(cornerRadius: StudyRadius.card))
  }
}

// MARK: - Detalhe

public struct StudySubjectScreen: View {
  @Environment(EstudosStore.self) private var store
  @State private var state: DetailState = .loading
  @State private var tab: SubjectTab = .slides
  @State private var switched = false
  let id: String

  public init(id: String) { self.id = id }

  private enum DetailState {
    case loading
    case ready(SubjectDetail)
    case failed(String)

    /// Em que pé está, sem o detalhe, para animar a troca de tela.
    var isReady: Bool {
      if case .ready = self { return true }
      return false
    }
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        switch state {
        case .loading:
          StudyLoadingState().transition(.blurReplace)
        case .failed(let message):
          StudyFailedState(message: message) { Task { await load(force: true) } }
            .transition(.blurReplace)
        case .ready(let detail):
          content(detail).transition(.blurReplace)
        }
      }
      .animation(Motion.crossfade, value: state.isReady)
      .padding(.horizontal, 16)
      .padding(.bottom, 32)
    }
    .studyPage()
    .navigationTitle("")
    .toolbarTitleDisplayMode(.inline)
    .task { await load(force: false) }
    .refreshable { await load(force: true) }
  }

  @ViewBuilder
  private func content(_ detail: SubjectDetail) -> some View {
    let now = Date()

    VStack(alignment: .leading, spacing: 12) {
      Image(systemName: "book")
        .font(.system(size: 24))
        .foregroundStyle(Color.subjectInk(for: detail.subject.color))
        .frame(width: 44, height: 44)
        .background(Color(hexString: detail.subject.color), in: .rect(cornerRadius: 10))
      StudyHeading(title: detail.subject.name)
      VStack(alignment: .leading, spacing: 2) {
        ForEach(properties(of: detail, now: now), id: \.icon) { property in
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(spacing: 6) {
              Image(systemName: property.icon)
              if property.showsName { Text(property.name) }
            }
              .font(.footnote)
              .foregroundStyle(Color.studyInk40)
              .frame(width: 104, alignment: .leading)
              .accessibilityLabel(property.name)
            Text(property.value)
              .font(.footnote)
              .foregroundStyle(Color.black.opacity(0.95))
              .fixedSize(horizontal: false, vertical: true)
          }
          .frame(minHeight: 30, alignment: .center)
        }
      }
    }

    Picker("seção da matéria", selection: Binding(get: { tab }, set: select)) {
      ForEach(SubjectTab.allCases) { entry in Text(entry.label).tag(entry) }
    }
    .pickerStyle(.segmented)

    VStack(alignment: .leading, spacing: 20) {
      switch tab {
      case .slides: slides(detail.materials)
      case .caderno: SubjectNotebookSection(subjectId: detail.subject.id)
      case .notas: notes(detail.notes)
      case .entregas: assignments(detail.assignments, now: now)
      case .cartoes:
        StudyEmptyState(icon: "rectangle.on.rectangle", title: "na aba revisar")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .id(tab)
    .transition(.opacity)
    .animation(Motion.swap, value: tab)
  }

  @ViewBuilder
  private func slides(_ materials: [StudyMaterial]) -> some View {
    if materials.isEmpty {
      StudyEmptyState(icon: "doc.richtext", title: "sem slides")
    } else {
      ForEach(Array(lessonGroups(materials).enumerated()), id: \.element.key) { index, group in
        VStack(alignment: .leading, spacing: 0) {
          StudyGroupLabel(left: group.key)
          StudyDbList {
            ForEach(group.items) { material in
              StudyDbRow(
                icon: material.kind == .link ? "link" : "doc.richtext", title: material.title,
                detail: materialDetail(material), end: { EmptyView() })
            }
          }
        }
        .firstEntrance(index: index, settled: switched)
      }
    }
  }

  @ViewBuilder
  private func notes(_ notes: [NoteSummary]) -> some View {
    if notes.isEmpty {
      StudyEmptyState(icon: "doc.text", title: "sem notas")
    } else {
      StudyDbList {
        ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
          StudyDbRow(
            icon: "doc.text", title: note.title,
            detail: StudyFormat.relative(note.updatedAt, now: Date()),
            end: { EmptyView() }
          )
          .firstEntrance(index: index, settled: switched)
        }
      }
    }
  }

  @ViewBuilder
  private func assignments(_ assignments: [StudyAssignment], now: Date) -> some View {
    if assignments.isEmpty {
      StudyEmptyState(
        icon: "checkmark.circle", title: "sem entregas",
        detail: "as do moodle entram sozinhas na próxima sincronização.")
    } else {
      StudyDbList {
        ForEach(Array(assignments.enumerated()), id: \.element.id) { index, assignment in
          StudyDbRow(
            icon: "checkmark.circle", title: assignment.title,
            detail: "\(assignment.source) · \(StudyFormat.due(assignment.dueAt, now: now))",
            end: { StudyPill(tone: assignment.status.pillTone, text: assignment.status.label) }
          )
          .firstEntrance(index: index, settled: switched)
        }
      }
    }
  }

  /// A trava da cascata vira no mesmo passo que a aba, senão a lista nova
  /// começa a entrar em cascata e é derrubada no passo seguinte.
  private func select(_ next: SubjectTab) {
    switched = true
    tab = next
  }

  private func load(force: Bool) async {
    if case .ready = state, !force { return }
    if let detail = await store.subjectDetail(id: id, force: force) {
      state = .ready(detail)
    } else if case .ready = state {
      return
    } else {
      state = .failed("não abriu")
    }
  }
}

enum SubjectTab: String, Hashable, CaseIterable, Identifiable {
  case slides, caderno, notas, entregas, cartoes

  var id: String { rawValue }

  var label: String {
    switch self {
    case .slides: "slides"
    case .caderno: "caderno"
    case .notas: "notas"
    case .entregas: "entregas"
    case .cartoes: "cartões"
    }
  }
}

private struct LessonGroup {
  let key: String
  let lesson: Int?
  var items: [StudyMaterial]
}

/// Aula mais nova em cima, e o que veio sem número de aula por último.
private func lessonGroups(_ materials: [StudyMaterial]) -> [LessonGroup] {
  var order: [String] = []
  var buckets: [String: LessonGroup] = [:]
  for material in materials {
    let key =
      material.lessonNumber.map { "aula \(String(format: "%02d", $0))" } ?? "outros"
    if buckets[key] == nil {
      order.append(key)
      buckets[key] = LessonGroup(key: key, lesson: material.lessonNumber, items: [])
    }
    buckets[key]?.items.append(material)
  }
  return order.compactMap { buckets[$0] }.sorted {
    guard let left = $0.lesson else { return false }
    guard let right = $1.lesson else { return true }
    return left > right
  }
}

private func materialDetail(_ material: StudyMaterial) -> String {
  material.page > 0
    ? "\(material.kind.rawValue) · p. \(material.page)"
    : "\(material.kind.rawValue) · \(material.source)"
}

private struct SubjectProperty {
  let icon: String
  let name: String
  let value: String
  var showsName = true
}

private func properties(of detail: SubjectDetail, now: Date) -> [SubjectProperty] {
  let next = detail.assignments.filter { $0.status != .done }.min { $0.dueAt < $1.dueAt }
  return [
    detail.subject.code.map {
      SubjectProperty(icon: "tag", name: "código", value: $0, showsName: false)
    },
    detail.subject.semester.map {
      SubjectProperty(icon: "calendar", name: "semestre", value: "\($0)º semestre", showsName: false)
    },
    next.map {
      SubjectProperty(
        icon: "clock", name: "próxima",
        value: "\($0.title) · \(StudyFormat.due($0.dueAt, now: now))")
    },
  ].compactMap { $0 }
}
