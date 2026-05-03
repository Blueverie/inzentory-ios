//
//  LoginView.swift
//  InZentory
//

import SwiftUI

struct LoginView: View {
    @Environment(AuthService.self) private var auth

    enum Mode { case signIn, register }

    @State private var mode: Mode = .signIn
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focus: Field?

    enum Field { case username, password }

    private var hasStoredToken: Bool {
        Keychain.load(forKey: AuthService.tokenKeychainKey) != nil
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("InZentory")
                .font(.largeTitle.bold())

            Picker("Mode", selection: $mode) {
                Text("Sign In").tag(Mode.signIn)
                Text("Register").tag(Mode.register)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            VStack(spacing: 12) {
                HStack {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.asciiCapable)
                        #endif
                        .submitLabel(.next)
                        .focused($focus, equals: .username)
                        .onSubmit { focus = .password }
                }
                .padding()
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))

                HStack {
                    SecureField("Password", text: $password)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                        .submitLabel(.done)
                        .focused($focus, equals: .password)
                        .onSubmit { Task { await submit() } }
                        .colorScheme(.light)
                }
                .padding()
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal)

            Group {
                if let error = auth.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: auth.errorMessage)

            Button {
                Task { await submit() }
            } label: {
                ZStack {
                    if auth.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(mode == .signIn ? "Sign In" : "Register")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(auth.isLoading || username.isEmpty || password.isEmpty)
            .padding(.horizontal)

            if mode == .signIn && auth.biometricsAvailable && hasStoredToken {
                Button {
                    Task { await auth.authenticateWithBiometrics() }
                } label: {
                    Label(
                        "Use Biometrics",
                        systemImage: {
                            #if os(iOS)
                            "faceid"
                            #else
                            "touchid"
                            #endif
                        }()
                    )
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        #if os(iOS)
        .keyboardDoneButton()
        #endif
    }

    private func submit() async {
        focus = nil
        if mode == .signIn {
            await auth.login(username: username, password: password)
        } else {
            await auth.register(username: username, password: password)
        }
    }
}

#Preview {
    LoginView()
        .environment(AuthService())
}
