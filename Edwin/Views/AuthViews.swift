import SwiftUI

struct SignUpView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    @FocusState private var focused: Field?

    enum Field { case name, email, password }

    var body: some View {
        AuthFormScaffold(
            eyebrow: "CREATE ACCOUNT",
            title: "Let's get you set up.",
            subtitle: "One account, all your messaging in one place."
        ) {
            LabeledField(label: "Your name", text: $name, placeholder: "Alex")
                .textContentType(.name)
                .focused($focused, equals: .name)
                .submitLabel(.next)
                .onSubmit { focused = .email }
            LabeledField(label: "Email", text: $email, placeholder: "you@email.com")
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused, equals: .email)
                .submitLabel(.next)
                .onSubmit { focused = .password }
            LabeledField(label: "Password", text: $password, placeholder: "At least 6 characters", secure: true, error: error)
                .textContentType(.newPassword)
                .focused($focused, equals: .password)
                .submitLabel(.done)
                .onSubmit { submit() }
        } footer: {
            Button {
                submit()
            } label: {
                if busy { ProgressView().tint(.white) } else { Text("Create account") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy)
        }
    }

    private func submit() {
        error = nil
        busy = true
        Task {
            do {
                try await auth.signUp(name: name, email: email, password: password)
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}

struct SignInView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    @FocusState private var focused: Field?

    enum Field { case email, password }

    var body: some View {
        AuthFormScaffold(
            eyebrow: "WELCOME BACK",
            title: "Sign in.",
            subtitle: "Pick up right where you left off."
        ) {
            LabeledField(label: "Email", text: $email, placeholder: "you@email.com")
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused, equals: .email)
                .submitLabel(.next)
                .onSubmit { focused = .password }
            LabeledField(label: "Password", text: $password, placeholder: "Your password", secure: true, error: error)
                .textContentType(.password)
                .focused($focused, equals: .password)
                .submitLabel(.done)
                .onSubmit { submit() }
        } footer: {
            Button {
                submit()
            } label: {
                if busy { ProgressView().tint(.white) } else { Text("Sign in") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy)
        }
    }

    private func submit() {
        error = nil
        busy = true
        Task {
            do {
                try await auth.signIn(email: email, password: password)
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}

// MARK: shared form pieces

struct AuthFormScaffold<Fields: View, Footer: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    @ViewBuilder var fields: Fields
    @ViewBuilder var footer: Footer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(eyebrow)
                    .font(.system(size: 13, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textMuted)

                VStack(spacing: 16) { fields }
                    .padding(.top, 24)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            VStack { footer }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .background(Theme.bg)
        }
        .background(Theme.bg)
    }
}

struct LabeledField: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var secure = false
    var error: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(.system(size: 16))
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(error == nil ? Theme.border : Theme.danger, lineWidth: 1)
            )
            if let error {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.danger)
                    .accessibilityLabel("Error: \(error)")
            }
        }
    }
}
