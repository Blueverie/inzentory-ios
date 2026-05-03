//
//  CropFeedbackStore.swift
//  InZentory
//
//  Records whether auto-crops were accepted, rejected, or replaced by manual crops.
//  Uses the history to tune MediaCropService's Vision parameters so repeated mistakes
//  become less likely over time.
//

import Foundation

final class CropFeedbackStore {

    static let shared = CropFeedbackStore()

    enum Event: Codable {
        case accepted   // user kept the auto-crop
        case rejected   // user chose the original (auto-crop was wrong)
        case manual     // user drew a manual crop (auto-crop was wrong)
    }

    private let key = "com.inzentory.cropFeedback.v1"
    private var events: [Event] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Event].self, from: data) {
            events = decoded
        }
    }

    func record(_ event: Event) {
        events.append(event)
        if events.count > 60 { events.removeFirst(events.count - 60) }
        persist()
    }

    // MARK: - Tuned parameters

    /// Minimum confidence passed to VNDetectRectanglesRequest.
    /// Rises when crops are frequently wrong so Vision becomes more selective.
    var minimumConfidence: Float {
        guard events.count >= 5 else { return 0.65 }
        let badCount = events.filter { if case .accepted = $0 { return false }; return true }.count
        let rejectionRate = Float(badCount) / Float(events.count)
        // Higher rejection → raise threshold so Vision only fires on clear subjects.
        return clamp(0.65 + rejectionRate * 0.20, lo: 0.50, hi: 0.85)
    }

    /// Minimum relative size passed to VNDetectRectanglesRequest.
    var minimumSize: Float {
        guard events.count >= 5 else { return 0.15 }
        let acceptedCount = events.filter { if case .accepted = $0 { return true }; return false }.count
        let acceptRate = Float(acceptedCount) / Float(events.count)
        // Slightly raise when acceptance is high (subjects fill more of the frame on average).
        return clamp(0.15 + (acceptRate - 0.5) * 0.06, lo: 0.10, hi: 0.25)
    }

    // MARK: - Private

    private func persist() {
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func clamp<T: Comparable>(_ value: T, lo: T, hi: T) -> T {
        min(max(value, lo), hi)
    }
}
