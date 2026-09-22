import HenriqueCore
import SwiftUI

/// O seletor de exercício só para hoje. Fica restrito ao catálogo do painel,
/// diferente do seletor do plano: a rota de sessão só aceita id que o servidor já
/// conhece, então biblioteca embutida e wger não entram aqui.
struct SessionExercisePicker: View {
  @Environment(\.dismiss) private var dismiss
  @FocusState private var searchFocused: Bool
  @State private var search = ""

  let catalog: [ExerciseCatalogItem]
  let chosen: Set<String>
  let onPick: (ExerciseCatalogItem) -> Void

  private var results: [ExerciseCatalogItem] {
    ExerciseLibrary.search(search, muscle: nil, in: catalog)
      .sorted { ExerciseLibrary.fold($0.name) < ExerciseLibrary.fold($1.name) }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
          Section {
            if results.isEmpty {
              ContentUnavailableView.search(text: search)
            } else {
              ForEach(results) { item in
                ExercisePickerRow(item: item, picked: chosen.contains(item.id)) {
                  onPick(item)
                  dismiss()
                }
                Divider().padding(.leading, 76).opacity(0.6)
              }
            }
          } header: {
            HStack(spacing: 8) {
              Image(systemName: "magnifyingglass").foregroundStyle(Color.mutedInk).padding(.leading, 2)
              TextField("buscar", text: $search)
                .submitLabel(.done)
                .focused($searchFocused)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .accessibilityLabel("Buscar exercício")
                .accessibilityIdentifier("sessao.buscar-exercicio")
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
            .padding(.horizontal, Space.l).padding(.top, Space.s).padding(.bottom, Space.s)
            .background(Color.canvas)
          }
        }
      }
      .background(Color.canvas)
      .navigationTitle("só hoje")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("fechar") { dismiss() }.accessibilityIdentifier("sessao.fechar-catalogo")
        }
      }
      .onAppear { searchFocused = true }
    }
  }
}
