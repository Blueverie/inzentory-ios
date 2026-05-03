//
//  DOSpacesClient.swift
//  InZentory
//

import Foundation
import CryptoKit

actor DOSpacesClient {
    static let shared = DOSpacesClient()

    private let bucket = "fsm"
    private let region = "nyc3"
    // Fallback credentials (same as used by the web app)
    private let fallbackAccessKey = "DO801GMF3HV9VD66EBYT"
    private let fallbackSecretKey = "CI9o3cuUrgvGbxF8MQIkV6KRSWF+Iesy5kH+YqYh+vs"

    enum DOError: LocalizedError {
        case uploadFailed(Int)
        case noData
        var errorDescription: String? {
            switch self {
            case .uploadFailed(let code): return "Upload failed (HTTP \(code))"
            case .noData:                 return "No image data"
            }
        }
    }

    /// Upload image data and return the public CDN URL.
    func upload(imageData: Data, filename: String) async throws -> String {
        let spaceCreds = try? await SharedCredentialsService.shared.getSpacesCredentials()
        let accessKey = spaceCreds?.key ?? fallbackAccessKey
        let secretKey = spaceCreds?.secret ?? fallbackSecretKey

        let host = "\(bucket).\(region).digitaloceanspaces.com"
        let uploadURL = URL(string: "https://\(host)/\(filename)")!

        // ── AWS Signature V4 ──────────────────────────────────────────────
        let now = Date()
        let amzDate   = iso8601DateTime(now)
        let dateStamp = iso8601Date(now)

        let payloadHash = sha256Hex(imageData)

        // Canonical headers (sorted alphabetically)
        let canonicalHeaders =
            "host:\(host)\n" +
            "x-amz-acl:public-read\n" +
            "x-amz-content-sha256:\(payloadHash)\n" +
            "x-amz-date:\(amzDate)\n"
        let signedHeaders = "host;x-amz-acl;x-amz-content-sha256;x-amz-date"

        let canonicalRequest = [
            "PUT",
            "/\(filename)",
            "",                   // empty query string
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")

        let credentialScope = "\(dateStamp)/\(region)/s3/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            sha256Hex(Data(canonicalRequest.utf8))
        ].joined(separator: "\n")

        let signingKey = deriveSigningKey(secretKey: secretKey, dateStamp: dateStamp)
        let signature  = hmacSHA256Hex(key: signingKey, data: stringToSign)

        let authHeader =
            "AWS4-HMAC-SHA256 " +
            "Credential=\(accessKey)/\(credentialScope)," +
            "SignedHeaders=\(signedHeaders)," +
            "Signature=\(signature)"
        // ──────────────────────────────────────────────────────────────────

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.httpBody   = imageData
        request.setValue("image/jpeg",       forHTTPHeaderField: "Content-Type")
        request.setValue(amzDate,            forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash,        forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue("public-read",      forHTTPHeaderField: "x-amz-acl")
        request.setValue(authHeader,         forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DOError.uploadFailed(http.statusCode)
        }

        return "https://\(bucket).\(region).cdn.digitaloceanspaces.com/\(filename)"
    }

    // MARK: - Sig V4 helpers

    private func deriveSigningKey(secretKey: String, dateStamp: String) -> Data {
        let kDate    = hmacSHA256(key: Data(("AWS4" + secretKey).utf8), data: dateStamp)
        let kRegion  = hmacSHA256(key: kDate,    data: region)
        let kService = hmacSHA256(key: kRegion,  data: "s3")
        return         hmacSHA256(key: kService, data: "aws4_request")
    }

    private func hmacSHA256(key: Data, data: String) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(data.utf8), using: SymmetricKey(data: key))
        return Data(mac)
    }

    private func hmacSHA256Hex(key: Data, data: String) -> String {
        hmacSHA256(key: key, data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func iso8601DateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale   = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")!
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: date)
    }

    private func iso8601Date(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale   = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")!
        f.dateFormat = "yyyyMMdd"
        return f.string(from: date)
    }
}
