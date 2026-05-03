//
//  EasyPostClient.swift
//  InZentory
//
//  Fetches shipping rates from EasyPost for a given parcel.
//  Ships from 44805 (Ashland, OH) to 97520 (Ashland, OR).
//  Supports two address modes: zip-only and full residential placeholder.
//  Excludes Media Mail and returns the cheapest rate.
//

import Foundation

actor EasyPostClient {
    static let shared = EasyPostClient()

    private let baseURL = URL(string: "https://api.easypost.com/v2")!

    struct Rate: Sendable {
        let carrier: String
        let service: String
        let rate: Double
        let deliveryDays: Int?
    }

    enum EasyPostError: LocalizedError {
        case noKeyConfigured
        case httpError(Int, String)
        case noRatesAvailable
        case parseError

        var errorDescription: String? {
            switch self {
            case .noKeyConfigured:
                return "EasyPost API key not configured — ask your admin to add it."
            case .httpError(let code, let body):
                return "EasyPost error (HTTP \(code)): \(body.prefix(200))"
            case .noRatesAvailable:
                return "No rates returned for these dimensions (excluding Media Mail)."
            case .parseError:
                return "Could not parse EasyPost response."
            }
        }
    }

    /// Returns the cheapest non-Media-Mail rate for the given parcel dimensions.
    /// Weight is in ounces; length, width, height are in inches.
    /// When `fullAddress` is true, uses generic residential street addresses on both ends
    /// so UPS/FedEx residential surcharges are included.
    func cheapestRate(
        weightOz: Double,
        lengthIn: Double,
        widthIn: Double,
        heightIn: Double,
        fullAddress: Bool = false
    ) async throws -> Rate {
        let key: String
        do {
            key = try await SharedCredentialsService.shared.getEasyPostKey()
        } catch {
            throw EasyPostError.noKeyConfigured
        }

        let fromAddress: [String: Any] = fullAddress
            ? ["street1": "530 Claremont Ave", "city": "Ashland", "state": "OH", "zip": "44805", "country": "US"]
            : ["zip": "44805", "country": "US"]

        let toAddress: [String: Any] = fullAddress
            ? ["street1": "701 Walnut St", "city": "Ashland", "state": "OR", "zip": "97520", "country": "US"]
            : ["zip": "97520", "country": "US"]

        let body: [String: Any] = [
            "shipment": [
                "from_address": fromAddress,
                "to_address":   toAddress,
                "parcel": [
                    "length": lengthIn,
                    "width": widthIn,
                    "height": heightIn,
                    "weight": weightOz
                ]
            ]
        ]

        var request = URLRequest(url: baseURL.appendingPathComponent("shipments"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let credentials = Data("\(key):".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw EasyPostError.httpError(status, body)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rates = json["rates"] as? [[String: Any]]
        else { throw EasyPostError.parseError }

        // Exclude Media Mail (USPS service name is "MediaMail")
        let filtered = rates.filter { r in
            let service = (r["service"] as? String ?? "").lowercased()
            return service != "mediamail"
        }

        guard let cheapest = filtered.min(by: { a, b in
            let ra = Double(a["rate"] as? String ?? "") ?? Double.infinity
            let rb = Double(b["rate"] as? String ?? "") ?? Double.infinity
            return ra < rb
        }) else { throw EasyPostError.noRatesAvailable }

        guard let rateStr = cheapest["rate"] as? String,
              let rateDouble = Double(rateStr),
              let carrier = cheapest["carrier"] as? String,
              let service = cheapest["service"] as? String
        else { throw EasyPostError.parseError }

        return Rate(
            carrier: carrier,
            service: service,
            rate: rateDouble,
            deliveryDays: cheapest["delivery_days"] as? Int
        )
    }
}
