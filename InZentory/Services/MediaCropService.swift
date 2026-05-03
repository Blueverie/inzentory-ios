//
//  MediaCropService.swift
//  InZentory
//
//  Detects the dominant rectangular subject in a photo (book cover, DVD/VHS case,
//  LP sleeve, etc.) using Vision, then deskews and crops to it via CoreImage.
//  Vision parameters are tuned over time by CropFeedbackStore.
//

#if os(iOS)
import UIKit
import Vision
import CoreImage

// MARK: - Result type

struct CropResult {
    /// Perspective-corrected crop of the detected subject.
    let cropped: UIImage
    /// Bounding rect of the detected subject in normalized image coords (0-1, top-left origin).
    /// Used to seed the manual crop editor with a sensible initial selection.
    let normalizedRect: CGRect
}

// MARK: - Service

enum MediaCropService {

    /// Detects and crops the dominant rectangular subject.
    /// Returns nil if no confident rectangle is found (caller should use the original).
    static func cropToSubject(_ image: UIImage) -> CropResult? {
        let normalized = image.orientationNormalized()
        guard let cgImage = normalized.cgImage else { return nil }

        let store = CropFeedbackStore.shared
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio    = 0.25   // allows wide DVD/VHS or tall books
        request.maximumAspectRatio    = 1.0
        request.minimumSize           = store.minimumSize
        request.maximumObservations   = 1
        request.minimumConfidence     = store.minimumConfidence

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        guard let observation = request.results?.first else { return nil }
        guard let cropped = perspectiveCrop(normalized, observation: observation) else { return nil }

        return CropResult(cropped: cropped, normalizedRect: boundingRect(for: observation))
    }

    // MARK: - Private

    private static func perspectiveCrop(
        _ image: UIImage,
        observation: VNRectangleObservation
    ) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)

        // Vision uses normalized coords, bottom-left origin — same as CoreImage pixels
        func pt(_ p: CGPoint) -> CIVector {
            CIVector(x: p.x * w, y: p.y * h)
        }

        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(ciImage,                        forKey: kCIInputImageKey)
        filter.setValue(pt(observation.topLeft),        forKey: "inputTopLeft")
        filter.setValue(pt(observation.topRight),       forKey: "inputTopRight")
        filter.setValue(pt(observation.bottomLeft),     forKey: "inputBottomLeft")
        filter.setValue(pt(observation.bottomRight),    forKey: "inputBottomRight")

        guard let output = filter.outputImage else { return nil }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let result = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: result)
    }

    /// Converts a VNRectangleObservation's four corners to a bounding CGRect in
    /// normalized UIKit coordinates (0-1, top-left origin).
    private static func boundingRect(for obs: VNRectangleObservation) -> CGRect {
        // Vision uses bottom-left origin; UIKit uses top-left origin.
        let minX = min(obs.topLeft.x,  obs.bottomLeft.x)
        let maxX = max(obs.topRight.x, obs.bottomRight.x)
        let minVisionY = min(obs.bottomLeft.y, obs.bottomRight.y)   // Vision bottom
        let maxVisionY = max(obs.topLeft.y,    obs.topRight.y)      // Vision top
        // Flip Y: UIKit minY = 1 - Vision maxY
        return CGRect(
            x:      minX,
            y:      1 - maxVisionY,
            width:  maxX - minX,
            height: maxVisionY - minVisionY
        )
    }
}

private extension UIImage {
    /// Returns a copy with EXIF orientation baked in (.up) so Vision sees correct geometry.
    func orientationNormalized() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}
#endif
