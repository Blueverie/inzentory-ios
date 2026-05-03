//
//  AuthService.swift
//  InZentory
//

import Foundation
import LocalAuthentication

@Observable final class AuthService {
    static let tokenKeychainKey    = "auth.bearer_token"
    static let usernameKeychainKey = "auth.username"
    static let lastAuthKey         = "auth.lastAuthenticatedAt"
    /// Re-auth is skipped if the user authenticated within this window.
    static let gracePeriod: TimeInterval = 15 * 60   // 15 minutes

    private(set) var isAuthenticated = false
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var username: String?

    var biometricsAvailable: Bool {
        let ctx = LAContext()
        var error: NSError?
        return ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// True when the user authenticated recently enough to skip the biometric prompt.
    private var isWithinGracePeriod: Bool {
        guard let last = UserDefaults.standard.object(forKey: Self.lastAuthKey) as? Date else {
            return false
        }
        return Date().timeIntervalSince(last) < Self.gracePeriod
    }

    func bootstrap() async {
        guard let token = Keychain.load(forKey: Self.tokenKeychainKey) else {
            isAuthenticated = false
            return
        }
        username = Keychain.load(forKey: Self.usernameKeychainKey)
        await APIClient.shared.setToken(token)
        // If username is missing (session predates username-save), require fresh login
        guard username != nil else {
            isAuthenticated = false
            return
        }
        await SharedCredentialsService.shared.configure(token: token)
        if biometricsAvailable && !isWithinGracePeriod {
            await authenticateWithBiometrics()
        } else {
            recordAuthTime()
            isAuthenticated = true
        }
    }

    func login(username: String, password: String) async {
        await perform {
            let response = try await APIClient.shared.login(username: username, password: password)
            Keychain.save(response.accessToken, forKey: Self.tokenKeychainKey)
            Keychain.save(username, forKey: Self.usernameKeychainKey)
            await APIClient.shared.setToken(response.accessToken)
            await SharedCredentialsService.shared.configure(token: response.accessToken)
            self.username = username
            self.recordAuthTime()
            self.isAuthenticated = true
        }
    }

    func register(username: String, password: String) async {
        await perform {
            let response = try await APIClient.shared.register(username: username, password: password)
            Keychain.save(response.accessToken, forKey: Self.tokenKeychainKey)
            Keychain.save(username, forKey: Self.usernameKeychainKey)
            await APIClient.shared.setToken(response.accessToken)
            await SharedCredentialsService.shared.configure(token: response.accessToken)
            self.username = username
            self.recordAuthTime()
            self.isAuthenticated = true
        }
    }

    func logout() {
        Keychain.delete(forKey: Self.tokenKeychainKey)
        UserDefaults.standard.removeObject(forKey: Self.lastAuthKey)
        Task {
            await APIClient.shared.setToken(nil)
            await SharedCredentialsService.shared.clear()
        }
        isAuthenticated = false
        errorMessage = nil
    }

    func handleUnauthorized() {
        logout()
    }

    func authenticateWithBiometrics() async {
        let ctx = LAContext()
        do {
            let success = try await ctx.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Authenticate to access InZentory"
            )
            if success {
                recordAuthTime()
                isAuthenticated = true
            }
        } catch {
            // Biometric failed or cancelled — token still present, user can retry via button
        }
    }

    private func recordAuthTime() {
        UserDefaults.standard.set(Date(), forKey: Self.lastAuthKey)
    }

    private func perform(_ work: () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        do {
            try await work()
        } catch let err as APIError {
            errorMessage = err.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
