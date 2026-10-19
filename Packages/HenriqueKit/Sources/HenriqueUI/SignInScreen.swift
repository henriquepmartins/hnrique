import HenriqueCore
import SwiftUI

struct SignInScreen: View {
  @Environment(AcademiaStore.self) private var store
  @Environment(\.accent) private var accent
  @State private var username = ""
  @State private var password = ""
  @FocusState private var focus: Field?

  let phase: AcademiaStore.Phase

  private enum Field: Hashable { case username, password }

  private var canSubmit: Bool {
    !username.isEmpty && !password.isEmpty && phase != .loading
  }

  var body: some View {
    ZStack {
      Color.canvas.ignoresSafeArea()

      VStack(spacing: Space.xxl) {
        Text("\(Text("h&").foregroundStyle(Color.ink))\(Text(".").foregroundStyle(accent.base))")
          .font(.system(size: 64, weight: .medium)).tracking(-4)
          .accessibilityLabel("henrique")
          .accessibilityAddTraits(.isHeader)

        VStack(spacing: Space.m) {
          LoginField(placeholder: "usuário") {
            TextField("usuário", text: $username)
              .textContentType(.username)
              #if os(iOS)
                .textInputAutocapitalization(.never)
              #endif
              .autocorrectionDisabled()
              .focused($focus, equals: .username)
              .submitLabel(.next)
              .onSubmit { focus = .password }
          }
          LoginField(placeholder: "senha") {
            SecureField("senha", text: $password)
              .textContentType(.password)
              .focused($focus, equals: .password)
              .submitLabel(.go)
              .onSubmit(submit)
          }
        }

        if case .failed(let message) = phase {
          Text(message)
            .font(.footnote)
            .foregroundStyle(Color.danger)
            .multilineTextAlignment(.center)
            .transition(.opacity)
        }

        Button(action: submit) {
          HStack(spacing: Space.s) {
            if phase == .loading {
              ProgressView().tint(.white)
              Text("entrando")
            } else {
              Text("entrar")
            }
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, Space.xs)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(!canSubmit)
      }
      .padding(.horizontal, Space.page)
      .frame(maxWidth: 420)
    }
    .sensoryFeedback(.error, trigger: phase) { _, new in
      if case .failed = new { true } else { false }
    }
    .onAppear { focus = .username }
  }

  private func submit() {
    guard canSubmit else { return }
    focus = nil
    Task { await store.signIn(username: username, password: password) }
  }
}

private struct LoginField<Content: View>: View {
  let placeholder: String
  @ViewBuilder let content: Content

  var body: some View {
    content
      .textFieldStyle(.plain)
      .padding(.horizontal, Space.l)
      .padding(.vertical, 14)
      .fieldSurface()
      .accessibilityLabel(placeholder)
  }
}
