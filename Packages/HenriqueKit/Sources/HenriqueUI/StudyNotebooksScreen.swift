import HenriqueCore
import SwiftUI

public struct NotebookPageRoute: Hashable, Sendable {
  public let id: String
  public init(id: String) { self.id = id }
}

private func pageCountLabel(_ total: Int) -> String? {
  switch total {
  case 0: nil
  case 1: "1 página"
  default: "\(total) páginas"
  }
}

/// O caderno de uma matéria. Era o miolo da tela de cadernos, que listava um
/// bloco destes por matéria; agora mora dentro do detalhe da matéria.
public struct SubjectNotebookSection: View {
  @Environment(EstudosStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var creating = false
  @State private var failed = false
  @State private var created: NotebookPageRoute?
  @State private var doomed: NotebookPageSummary?
  let subjectId: String

  public init(subjectId: String) { self.subjectId = subjectId }

  public var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      switch store.notebooks {
      case .idle, .loading:
        StudyLoadingState().transition(.opacity)
      case .failed(let message):
        StudyFailedState(message: message) { Task { await store.loadNotebooks(force: true) } }
          .transition(.opacity)
      case .ready(let notebooks):
        pages(notebooks.first { $0.subject.id == subjectId }?.pages ?? []).transition(.opacity)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .animation(Motion.resolve(Motion.crossfade, reduceMotion), value: store.notebooks.phase)
    .task { await store.loadNotebooks() }
    .navigationDestination(item: $created) { NotebookPageScreen(id: $0.id) }
    .confirmationDialog(
      "apagar página?", isPresented: Binding(get: { doomed != nil }, set: { if !$0 { doomed = nil } }),
      titleVisibility: .visible, presenting: doomed
    ) { page in
      Button("apagar", role: .destructive) { Task { _ = await store.removeNotebookPage(id: page.id) } }
      Button("cancelar", role: .cancel) {}
    }
  }

  @ViewBuilder
  private func pages(_ pages: [NotebookPageSummary]) -> some View {
    HStack(spacing: 12) {
      if let count = pageCountLabel(pages.count) {
        Text(count)
          .font(.footnote)
          .monospacedDigit()
          .foregroundStyle(Color.studyInk40)
      }
      Spacer(minLength: 0)
      Button(newPageLabel, systemImage: "plus") { Task { await create() } }
        .buttonStyle(.glass)
        .controlSize(.large)
        .disabled(creating)
    }

    if pages.isEmpty {
      StudyEmptyState(icon: "doc.text", title: "sem páginas")
    } else {
      StudyDbList {
        ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
          NavigationLink(value: NotebookPageRoute(id: page.id)) {
            StudyDbRow(icon: "doc.text", title: page.displayTitle) {
              Text(StudyFormat.relative(page.updatedAt, now: Date())).monospacedDigit()
            }
          }
          .buttonStyle(StudyPressStyle())
          .contextMenu {
            Button("apagar", systemImage: "trash", role: .destructive) { doomed = page }
          }
          .staggeredEntrance(index: index, isReady: true)
        }
      }
    }
  }

  private var newPageLabel: String {
    failed ? "tentar de novo" : "nova"
  }

  private func create() async {
    guard !creating else { return }
    creating = true
    failed = false
    if let page = await store.createNotebookPage(subjectId: subjectId) {
      created = NotebookPageRoute(id: page.id)
    } else {
      failed = true
    }
    creating = false
  }
}

// MARK: - Página

public struct NotebookPageScreen: View {
  @Environment(EstudosStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @ScaledMetric(relativeTo: .title) private var titleSize = 30.0
  @State private var page: NotebookPage?
  /// Os blocos saem do JSON uma vez por carga. Ler `page.blocks` no corpo
  /// reconstruiria a árvore inteira a cada tecla digitada no título.
  @State private var blocks: [NotebookBlock] = []
  @State private var failed: String?
  @State private var title = ""
  @State private var save: SaveState = .pending
  @State private var version = 0
  @State private var sent = 0
  @State private var inFlight = false
  @State private var debounce: Task<Void, Never>?
  @State private var confirmingDelete = false
  @FocusState private var editingTitle: Bool
  let id: String

  public init(id: String) { self.id = id }

  /// O rótulo do salvamento. Estado próprio porque a tela precisa distinguir
  /// "ainda não mandei" de "mandei e não voltou".
  enum SaveState: Equatable {
    case clean
    case pending
    case saving
    case failed

    var label: String {
      switch self {
      case .clean: "salvo"
      case .pending: "alterado"
      case .saving: "salvando…"
      case .failed: "não salvou, tentar de novo"
      }
    }

    var icon: String {
      switch self {
      case .clean: "checkmark.icloud"
      case .pending, .saving: "icloud"
      case .failed: "exclamationmark.icloud"
      }
    }

    var color: Color {
      switch self {
      case .failed: StudyPillTone.coral.foreground
      case .saving: .studyInk60
      default: .studyInk40
      }
    }
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        if page != nil {
          TextField("título", text: Binding(get: { title }, set: { touch($0) }), axis: .vertical)
            .lineLimit(1...4)
            .focused($editingTitle)
            .submitLabel(.done)
            .font(.system(size: titleSize, weight: .bold))
            .tracking(-titleSize * 0.035)
            .textFieldStyle(.plain)
            .padding(.vertical, 4)
            .accessibilityLabel("título da página")
          if blocks.isEmpty {
            StudyEmptyState(icon: "lock", title: "corpo só no web")
              .padding(.top, 8)
          } else {
            NotebookBody(blocks: blocks)
              .padding(.top, 8)
            Label("só leitura", systemImage: "lock")
              .font(.footnote)
              .foregroundStyle(Color.studyInk40)
              .padding(.top, 24)
          }
        } else if let failed {
          StudyFailedState(message: failed) { Task { await load(force: true) } }
        } else {
          StudyLoadingState(shape: .page)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.bottom, 40)
    }
    .studyPage()
    .navigationTitle("")
    .toolbarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .principal) {
        StudyPill(color: subject?.color, text: subject?.name ?? "caderno")
      }
      ToolbarItem(placement: .primaryAction) {
        if page != nil {
          Button { flush(report: true) } label: {
            Image(systemName: save.icon)
              .foregroundStyle(save.color)
              .symbolEffect(.pulse, isActive: save == .saving)
              .contentTransition(.symbolEffect(.replace))
          }
          .disabled(save != .failed)
          .accessibilityLabel("salvamento")
          .accessibilityValue(save.label)
        }
      }
      ToolbarItem(placement: .primaryAction) {
        Button("apagar página", systemImage: "trash") { confirmingDelete = true }
          .labelStyle(.iconOnly)
          .disabled(page == nil)
      }
    }
    .keyboardDone()
    .confirmationDialog(
      "apagar página?", isPresented: $confirmingDelete, titleVisibility: .visible
    ) {
      Button("apagar", role: .destructive) { Task { await remove() } }
      Button("cancelar", role: .cancel) {}
    }
    .task {
      await store.loadNotebooks()
      await load(force: false)
    }
    .refreshable { await load(force: true) }
    .onDisappear { flush(report: false) }
  }

  private var subject: StudySubject? {
    guard let page else { return nil }
    return store.notebooks.value?.first { $0.subject.id == page.subjectId }?.subject
  }

  private func load(force: Bool) async {
    if page != nil, !force { return }
    guard let loaded = await store.notebookPage(id: id, force: force) else {
      if page == nil { failed = "não abriu" }
      return
    }
    page = loaded
    blocks = loaded.blocks
    failed = nil
    // Um refresh no meio de uma edição não pode jogar fora o que ainda não
    // subiu, então o campo só recebe o título do servidor quando está limpo.
    if version == sent {
      title = loaded.title
      save = .clean
    }
  }

  /// Com eixo vertical o Return viraria quebra de linha. Aqui ele encerra.
  private func touch(_ typed: String) {
    let text = typed.replacingOccurrences(of: "\n", with: "")
    if text != typed { editingTitle = false }
    guard text != title else { return }
    title = text
    guard page != nil else { return }
    version += 1
    if save != .pending { save = .pending }
    debounce?.cancel()
    debounce = Task {
      try? await Task.sleep(for: .milliseconds(800))
      guard !Task.isCancelled else { return }
      flush(report: true)
    }
  }

  /// Um envio por vez. Quem digitou enquanto a rede respondia ganha um envio
  /// novo logo depois, com a versão mais recente, e assim dois saves nunca se
  /// cruzam com o antigo por cima.
  private func flush(report: Bool) {
    debounce?.cancel()
    debounce = nil
    guard let page, !inFlight, sent != version else { return }
    let attempt = version
    let draft = title
    inFlight = true
    if report { save = .saving }
    Task {
      do {
        _ = try await store.saveNotebookPage(
          SaveNotebookPageInput(
            id: page.id, subjectId: page.subjectId, title: draft, content: page.content))
        sent = attempt
        if report, version == attempt { save = .clean }
      } catch {
        if report, version == attempt { save = .failed }
      }
      inFlight = false
      if version != attempt { flush(report: report) }
    }
  }

  private func remove() async {
    debounce?.cancel()
    debounce = nil
    // A página vai sumir, então o rascunho pendente não deve virar um save
    // depois do apagar.
    version = sent
    if await store.removeNotebookPage(id: id) {
      dismiss()
    } else {
      save = .failed
    }
  }
}

// MARK: - Corpo em blocos

struct NotebookBody: View {
  let blocks: [NotebookBlock]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(numbered(blocks)) { row in
        NotebookBlockView(block: row.block, number: row.number)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct NotebookBlockView: View {
  let block: NotebookBlock
  let number: Int?
  @ScaledMetric(relativeTo: .body) private var textSize = 16.0
  @ScaledMetric(relativeTo: .callout) private var codeSize = 14.0
  @ScaledMetric(relativeTo: .title) private var heading1 = 26.0
  @ScaledMetric(relativeTo: .title2) private var heading2 = 21.0
  @ScaledMetric(relativeTo: .headline) private var heading3 = 17.0

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      leaf
      if !block.children.isEmpty {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(numbered(block.children)) { row in
            NotebookBlockView(block: row.block, number: row.number)
          }
        }
        .padding(.leading, 16)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private var leaf: some View {
    switch block.type {
    case .heading:
      Text(block.text)
        .font(.system(size: headingSize, weight: .semibold))
        .tracking(-headingSize * 0.02)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
    case .bulletListItem:
      marker(Text("•"))
    case .numberedListItem:
      marker(Text("\(number ?? 1).").monospacedDigit())
    case .checkListItem:
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Image(systemName: block.checked == true ? "checkmark.square" : "square")
          .font(.system(size: textSize))
          .foregroundStyle(block.checked == true ? Color.studyBlue : Color.studyInk40)
          .frame(width: 24, alignment: .trailing)
        paragraph(block.text)
          .strikethrough(block.checked == true)
          .foregroundStyle(block.checked == true ? Color.studyInk40 : Color.studyInk)
      }
    case .codeBlock:
      Text(block.text)
        .font(.system(size: codeSize, design: .monospaced))
        .foregroundStyle(Color.studyInk)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.black.opacity(0.04), in: .rect(cornerRadius: StudyRadius.inner))
    case .quote:
      HStack(alignment: .top, spacing: 12) {
        Rectangle().fill(Color.studyInk20).frame(width: 2)
        paragraph(block.text).foregroundStyle(Color.studyGraphite)
      }
      .fixedSize(horizontal: false, vertical: true)
    case .paragraph, .other:
      paragraph(block.text)
    }
  }

  private func marker(_ symbol: Text) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      symbol
        .font(.system(size: textSize))
        .foregroundStyle(Color.studyInk40)
        .frame(width: 24, alignment: .trailing)
      paragraph(block.text)
    }
  }

  private func paragraph(_ text: String) -> some View {
    Text(text)
      .font(.system(size: textSize))
      .lineSpacing(5)
      .foregroundStyle(Color.studyInk)
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var headingSize: CGFloat {
    switch block.level ?? 1 {
    case 1: heading1
    case 2: heading2
    default: heading3
    }
  }
}

private struct NumberedBlock: Identifiable {
  let block: NotebookBlock
  let number: Int?
  var id: String { block.id }
}

/// A numeração é por corrida de irmãos. Um parágrafo no meio começa a contagem
/// de novo, como o BlockNote faz no web.
private func numbered(_ blocks: [NotebookBlock]) -> [NumberedBlock] {
  var counter = 0
  return blocks.map { block in
    guard block.type == .numberedListItem else {
      counter = 0
      return NumberedBlock(block: block, number: nil)
    }
    counter += 1
    return NumberedBlock(block: block, number: counter)
  }
}
