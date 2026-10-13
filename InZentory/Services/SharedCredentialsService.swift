//
//  SharedCredentialsService.swift
//  InZentory
//
//  Fetches all service credentials from the shared backend after login,
//  caches them in memory for the session. Clients read from here instead
//  of local Keychain.
//

import Foundation

actor SharedCredentialsService {
    static let shared = SharedCredentialsService()

    private let baseURL = URL(string: "https://blueverie-share-backend-3p62q.ondigitalocean.app")!

    // MARK: - Credential types

    struct AoBCredentials: Sendable {
        let username: String
        let password: String
    }

    struct SpacesCredentials: Sendable {
        let key: String
        let secret: String
    }

    // MARK: - Cache

    private var aob: AoBCredentials?
    private var spaces: SpacesCredentials?
    private var printNodeKey: String?
    private var easyPostKey: String?
    private(set) var lastError: String?

    // MARK: - Errors

    enum CredError: LocalizedError {
        case notLoaded
        case httpError(Int, String)
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .notLoaded:              return "Service credentials not loaded. Try signing out and back in."
            case .httpError(let c, let b): return "Credential fetch failed (HTTP \(c)): \(b)"
            case .parseError(let s):      return "Credential response could not be parsed: \(s)"
            }
        }
    }

    // MARK: - Lifecycle

    /// Call after a successful login or bootstrap. Fetches all credentials in parallel.
    /// Returns false when the backend rejected the bearer token (HTTP 401) — e.g. it
    /// expired or the server's SECRET_KEY changed — so the caller can force a fresh login.
    @discardableResult
    func configure(token: String) async -> Bool {
        lastError = nil
        var tokenRejected = false
        async let aobTask      = fetch("aob",       token: token)
        async let spacesTask   = fetch("do_spaces", token: token)
        async let printTask    = fetch("printnode", token: token)
        async let easyPostTask = fetch("easypost",  token: token)

        do {
            let d = try await aobTask
            if let u = d["username"], let p = d["password"] {
                aob = AoBCredentials(username: u, password: p)
            } else {
                lastError = "aob: missing username or password fields"
            }
        } catch {
            if Self.isUnauthorized(error) { tokenRejected = true }
            lastError = "aob: \(error.localizedDescription)"
        }

        do {
            let d = try await spacesTask
            if let k = d["key"], let s = d["secret"] {
                spaces = SpacesCredentials(key: k, secret: s)
            }
        } catch {
            if Self.isUnauthorized(error) { tokenRejected = true }
            // Spaces failure is non-fatal (hardcoded fallback exists)
        }

        do {
            let d = try await printTask
            if let k = d["key"] { printNodeKey = k }
        } catch {
            if Self.isUnauthorized(error) { tokenRejected = true }
            // PrintNode failure is non-fatal (user can still list without printing)
        }

        do {
            let d = try await easyPostTask
            if let k = d["key"] { easyPostKey = k }
        } catch {
            if Self.isUnauthorized(error) { tokenRejected = true }
            // EasyPost failure is non-fatal
        }

        return !tokenRejected
    }

    private static func isUnauthorized(_ error: Error) -> Bool {
        if case CredError.httpError(401, _) = error { return true }
        return false
    }

    func clear() {
        aob          = nil
        spaces       = nil
        printNodeKey = nil
        easyPostKey  = nil
        lastError    = nil
    }

    // MARK: - Load status (non-throwing, for UI)

    func loadStatus() -> (aob: Bool, spaces: Bool, printNode: Bool, easyPost: Bool) {
        (aob != nil, spaces != nil, printNodeKey != nil, easyPostKey != nil)
    }

    // MARK: - Accessors

    func getAoBCredentials() throws -> AoBCredentials {
        guard let c = aob else { throw CredError.notLoaded }
        return c
    }

    func getSpacesCredentials() throws -> SpacesCredentials {
        guard let c = spaces else { throw CredError.notLoaded }
        return c
    }

    func getPrintNodeKey() throws -> String {
        guard let k = printNodeKey else { throw CredError.notLoaded }
        return k
    }

    func getEasyPostKey() throws -> String {
        guard let k = easyPostKey else { throw CredError.notLoaded }
        return k
    }

    // MARK: - Private

    private func fetch(_ service: String, token: String) async throws -> [String: String] {
        var request = URLRequest(url: baseURL.appendingPathComponent("inzentory/credentials/\(service)"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CredError.httpError(status, body)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let creds = json["credentials"] as? [String: String]
        else {
            throw CredError.parseError(String(data: data, encoding: .utf8)?.prefix(200).description ?? "")
        }

        return creds
    }
}
