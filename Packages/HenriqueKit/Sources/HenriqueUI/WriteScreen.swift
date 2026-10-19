import HenriqueCore
import SwiftUI

// MARK: - Rascunho

struct WriteDraft: Equatable, Sendable {
  var title = ""
  var subjectId: String?
  var tags: [String] = []
  var body = ""

  var trimmedTitle: String {
    title.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

// MARK: - Inserções

enum WriteInsert: Equatable, Sendable {
  case line(String)
  case wrap(before: String, after: String)
}

struct WriteAction: Identifiable, Sendable {
  let label: String
  let icon: String
  let insert: WriteInsert

  var id: String { label }

  static let all: [WriteAction] = [
    WriteAction(label: "negrito", icon: "bold", insert: .wrap(before: "**", after: "**")),
    WriteAction(label: "título", icon: "textformat.size", insert: .line("## ")),
    WriteAction(label: "lista", icon: "list.bullet", insert: .line("- ")),
    WriteAction(label: "ligar nota", icon: "link.badge.plus", insert: .wrap(before: "[[", after: "]]")),
    WriteAction(label: "link", icon: "link", insert: .wrap(before: "[", after: "](https://)")),
  ]
}

/// O texto novo e a posição do cursor nele, contada em caracteres a partir do
/// começo, porque o índice antigo não vale mais na string depois da edição.
func writeApplyInsert(_ value: String, range: Range<String.Index>, insert: WriteInsert)
  -> (text: String, caret: Int)
{
  let start = value.distance(from: value.startIndex, to: range.lowerBound)
  switch insert {
  case .line(let prefix):
    let lineStart =
      value[..<range.lowerBound].lastIndex(of: "\n").map { value.index(after: $0) }
      ?? value.startIndex
    var text = value
    text.insert(contentsOf: prefix, at: lineStart)
    return (text, start + prefix.count)
  case .wrap(let before, let after):
    let selected = String(value[range])
    var text = value
    text.replaceSubrange(range, with: before + selected + after)
    return (text, start + before.count + selected.count)
  }
}

func writeSlugify(_ title: String) -> String {
  let plain = title.folding(options: .diacriticInsensitive, locale: nil).lowercased()
  var slug = ""
  var gap = false
  for character in plain {
    guard character.isASCII, character.isLetter || character.isNumber else {
      gap = true
      continue
    }
    if gap, !slug.isEmpty { slug.append("-") }
    gap = false
    slug.append(character)
  }
  return slug.isEmpty ? "sem-titulo" : slug
}

/// O caminho nasce do título uma vez e depois congela. Se ele seguisse o título
/// enquanto o dono digita, cada tecla criaria um arquivo novo no vault.
func writeFreshPath(title: String, taken: Set<String>) -> String {
  let slug = writeSlugify(title)
  var candidate = "notas/\(slug).md"
  var counter = 2
  while taken.contains(candidate) {
    candidate = "notas/\(slug)-\(counter).md"
    counter += 1
  }
  return candidate
}

// MARK: - Tela

public struct WriteScreen: View {
  @Environment(EstudosStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 30.0
  @ScaledMetric(relativeTo: .body) private var bodySize = 16.0

  @State private var draft = WriteDraft()
  @State private var saved = WriteDraft()
  @State private var path: String?
  @State private var savedAt: Date?
  @State private var saving = false
  @State private var failed = false
  @State private var pending: Task<Bool, Never>?
  @State private var selection: TextSelection?
  @State private var askLeave = false
  @State private var materialId: String?
  @State private var opening: Opening
  @FocusState private var focus: Field?

  private enum Field { case title, body }

  /// Uma nota que já existe passa pela rede antes de virar rascunho.
  private enum Opening: Equatable {
    case ready
    case loading(String)
    case failed(String)
  }

  public init(path: String? = nil) {
    _opening = State(initialValue: path.map(Opening.loading) ?? .ready)
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          switch opening {
          case .ready:
            page
            recent
          case .loading:
            StudyLoadingState(shape: .page)
          case .failed(let path):
            StudyFailedState(message: "a nota não abriu") { Task { await open(path) } }
          }
        }
        .padding(.horizontal, 16)
      }
      .scrollDismissesKeyboard(.interactively)
      .studyPage()
      .navigationTitle("")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("fechar", systemImage: "xmark", role: .close) { Task { await close() } }
        }
      }
      .modifier(WriteKeybar(insert: insert))
      // Arrastar a folha não passa pela pergunta do "fechar". Com algo por
      // salvar, só o botão fecha.
      .interactiveDismissDisabled(dirty)
      .confirmationDialog(
        "descartar nota?", isPresented: $askLeave, titleVisibility: .visible
      ) {
        Button("descartar", role: .destructive) { dismiss() }
        Button("continuar", role: .cancel) {}
      }
      .task {
        if case .loading(let path) = opening { await open(path) }
        await store.loadNotes()
        await store.loadSubjects()
      }
      .task(id: draft) { await autosave() }
    }
  }

  // MARK: Página

  private var page: some View {
    VStack(alignment: .leading, spacing: 12) {
      RoundedRectangle(cornerRadius: 10)
        .fill(Color(hexString: subject?.color))
        .frame(width: 44, height: 44)
        .overlay(
          Image(systemName: "doc.text")
            .font(.system(size: 20))
            .foregroundStyle(Color.subjectInk(for: subject?.color)))

      // Com eixo vertical o Return viraria quebra de linha no título. Aqui ele
      // leva ao corpo.
      TextField("título", text: titleBinding, axis: .vertical)
        .font(.system(size: titleSize, weight: .semibold).leading(.tight))
        .tracking(-titleSize * 0.03)
        .lineLimit(1...4)
        .textFieldStyle(.plain)
        .focused($focus, equals: .title)
        .submitLabel(.next)

      props

      if failed {
        VStack(alignment: .leading, spacing: 8) {
          StudyCallout(
            icon: "arrow.triangle.2.circlepath", tone: .yellow,
            title: "nota não salva")
          Button("tentar de novo", systemImage: "arrow.clockwise") { Task { _ = await savePending() } }
            .buttonStyle(.glass)
            .controlSize(.large)
            .tint(Color.studyInk)
            .disabled(saving)
        }
      }

      if dirty, draft.trimmedTitle.isEmpty {
        Text("falta título")
          .font(.footnote)
          .foregroundStyle(Color.studyGraphite)
      }

      editor
    }
  }

  private var props: some View {
    VStack(alignment: .leading, spacing: 2) {
      WritePropRow(icon: "book", label: "matéria", lineHeight: 44) {
        ForEach(subjects) { item in
          StudyChip(label: item.name, count: nil, isActive: item.id == draft.subjectId) {
            draft.subjectId = draft.subjectId == item.id ? nil : item.id
          }
        }
      }
      if !draft.tags.isEmpty {
        WritePropRow(icon: "tag", label: "tags") {
          ForEach(draft.tags, id: \.self) { tag in
            StudyPill(text: tag)
          }
        }
      }
      WritePropRow(icon: "clock", label: "salvamento", showsLabel: false) {
        TimelineView(.periodic(from: .now, by: 30)) { context in
          Text(savedLabel(now: context.date))
            .font(.footnote)
            .monospacedDigit()
        }
      }
    }
  }

  /// Campo que cresce dentro da rolagem da página, e não um editor com
  /// rolagem própria: assim o sistema rola a página até o cursor e as últimas
  /// linhas não ficam atrás do teclado.
  private var editor: some View {
    TextField("escreva", text: $draft.body, selection: $selection, axis: .vertical)
      .font(.system(size: bodySize))
      .foregroundStyle(Color.black.opacity(0.95))
      .lineLimit(12...)
      .textFieldStyle(.plain)
      .focused($focus, equals: .body)
  }

  private var titleBinding: Binding<String> {
    Binding(
      get: { draft.title },
      set: { text in
        guard text.contains("\n") else {
          draft.title = text
          return
        }
        draft.title = text.replacingOccurrences(of: "\n", with: "")
        focus = .body
      })
  }

  @ViewBuilder private var recent: some View {
    if !notes.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
        StudySectionHeading(title: "recentes", systemImage: "clock.arrow.circlepath")
        StudyDbList {
          ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
            StudyDbRow(
              icon: "doc.text", title: note.title,
              detail: note.tags.isEmpty ? nil : note.tags.joined(separator: ", "),
              end: {
                HStack(spacing: 8) {
                  Text(StudyFormat.relative(note.updatedAt, now: .now)).monospacedDigit()
                  StudyRowChevron()
                }
              },
              action: { Task { await switchTo(note.path) } }
            )
            .staggeredEntrance(index: index, isReady: store.notes.value != nil)
          }
        }
      }
    }
  }

  // MARK: Estado derivado

  private var subjects: [StudySubject] { store.subjects.value ?? [] }
  /// A nota aberta não aparece entre as recentes.
  private var notes: [NoteSummary] { (store.notes.value ?? []).filter { $0.path != path } }
  private var subject: StudySubject? { subjects.first { $0.id == draft.subjectId } }
  private var dirty: Bool { draft != saved }

  private func savedLabel(now: Date) -> String {
    if saving { return "salvando…" }
    guard let savedAt else { return "rascunho" }
    return dirty ? "alterado" : StudyFormat.relative(savedAt, now: now)
  }

  // MARK: Salvar

  private func autosave() async {
    guard dirty, !draft.trimmedTitle.isEmpty else { return }
    try? await Task.sleep(for: .milliseconds(800))
    guard !Task.isCancelled else { return }
    _ = await savePending()
  }

  /// Um pedido de cada vez. Quem chega no meio de um envio espera o mesmo
  /// resultado em vez de abrir uma segunda gravação do mesmo arquivo.
  private func savePending() async -> Bool {
    if let pending { return await pending.value }
    let task = Task { await runSave() }
    pending = task
    let result = await task.value
    pending = nil
    return result
  }

  private func runSave() async -> Bool {
    saving = true
    failed = false
    defer { saving = false }
    while draft != saved {
      let value = draft
      let title = value.trimmedTitle
      if title.isEmpty { return false }
      let target = path ?? writeFreshPath(title: value.title, taken: Set(notes.map(\.path)))
      path = target
      do {
        let note = try await store.saveNote(
          SaveNoteInput(
            path: target, title: title, subjectId: value.subjectId, materialId: materialId,
            tags: value.tags, body: value.body))
        saved = value
        savedAt = note.updatedAt
      } catch {
        failed = true
        return false
      }
    }
    return true
  }

  private func open(_ notePath: String) async {
    opening = .loading(notePath)
    guard let note = await store.note(path: notePath) else {
      opening = .failed(notePath)
      return
    }
    let loaded = WriteDraft(
      title: note.title, subjectId: note.subjectId, tags: note.tags, body: note.body)
    saved = loaded
    draft = loaded
    path = note.path
    materialId = note.materialId
    savedAt = note.updatedAt
    failed = false
    opening = .ready
  }

  /// Abrir uma recente troca a nota na mesma folha. O que estava na tela salva
  /// antes; sem título ainda, fica onde está e o aviso de falta de título diz
  /// por quê.
  private func switchTo(_ notePath: String) async {
    guard await savePending() else { return }
    await open(notePath)
  }

  private func close() async {
    if await savePending() {
      dismiss()
    } else {
      askLeave = true
    }
  }

  // MARK: Teclado

  private func insert(_ action: WriteInsert) {
    let text = draft.body
    let next = writeApplyInsert(text, range: writeRange(in: text), insert: action)
    draft.body = next.text
    selection = TextSelection(
      insertionPoint: next.text.index(next.text.startIndex, offsetBy: next.caret))
  }

  private func writeRange(in text: String) -> Range<String.Index> {
    let end = text.endIndex..<text.endIndex
    guard let selection else { return end }
    let candidate: Range<String.Index>?
    switch selection.indices {
    case .selection(let range):
      candidate = range
    case .multiSelection(let set):
      candidate = set.ranges.first.map { first in
        first.lowerBound..<(set.ranges.last?.upperBound ?? first.upperBound)
      }
    @unknown default:
      candidate = nil
    }
    guard let candidate, candidate.lowerBound >= text.startIndex, candidate.upperBound <= text.endIndex
    else { return end }
    return candidate
  }
}

// MARK: - Peças da tela

/// A linha de propriedade do web é uma grade de 104pt mais o resto, e o valor
/// quebra linha quando as matérias não cabem.
private struct WritePropRow<Content: View>: View {
  let icon: String
  let label: String
  var showsLabel = true
  var lineHeight: CGFloat = 30
  @ViewBuilder let content: Content
  @ScaledMetric(relativeTo: .footnote) private var labelWidth = 104.0

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: icon).imageScale(.small)
        if showsLabel { Text(label) }
      }
      .font(.footnote)
      .foregroundStyle(Color.studyInk40)
      .frame(width: showsLabel ? labelWidth : 20, height: lineHeight, alignment: .leading)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(label)
      StudyWrap(spacing: 4, lineSpacing: 4) { content }
        .frame(maxWidth: .infinity, minHeight: lineHeight, alignment: .leading)
    }
  }
}

private struct WriteKeybar: ViewModifier {
  let insert: (WriteInsert) -> Void

  func body(content: Content) -> some View {
    #if os(iOS)
      content.toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          ForEach(WriteAction.all) { action in
            IconButton(title: action.label, systemImage: action.icon, size: 20) { insert(action.insert) }
          }
          Spacer()
          KeyboardDoneButton()
        }
      }
    #else
      content
    #endif
  }
}
