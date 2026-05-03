//
//  ManualCropView.swift
//  InZentory
//
//  Interactive crop editor: four draggable corner handles let the user trim a
//  rectangle from the original photo.  Presented as a full-screen cover from
//  CropPreviewSheet when the user taps "Crop Manually".
//

import SwiftUI

// MARK: - Main view

#if os(iOS)
import UIKit
struct ManualCropView: View {

    let image: UIImage
    /// Initial crop rect in normalized image coordinates (0-1, top-left origin).
    let initialRect: CGRect
    let onCrop: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var cropRect: CGRect
    /// Tracks the last-seen translation per handle to derive incremental deltas.
    @State private var prevTranslation: [Handle: CGSize] = [:]

    init(
        image: UIImage,
        initialRect: CGRect = CGRect(x: 0.08, y: 0.08, width: 0.84, height: 0.84),
        onCrop: @escaping (UIImage) -> Void
    ) {
        self.image = image
        self.initialRect = initialRect
        self.onCrop = onCrop
        _cropRect = State(initialValue: initialRect)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let frame = imageFrame(for: image.size, in: geo.size)
                ZStack {
                    Color.black.ignoresSafeArea()

                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    CropDimmingOverlay(cropRect: cropRect, imageFrame: frame)

                    cropBorder(imageFrame: frame)

                    ForEach(Handle.allCases, id: \.self) { handle in
                        handleView(handle, imageFrame: frame)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Manual Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        if let result = applyCrop() { onCrop(result) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Reset") { withAnimation(.easeInOut(duration: 0.2)) { cropRect = initialRect } }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { prevTranslation = [:] }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func cropBorder(imageFrame frame: CGRect) -> some View {
        let vr = toViewRect(cropRect, frame: frame)
        ZStack {
            // Border
            Rectangle()
                .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                .frame(width: vr.width, height: vr.height)
                .position(x: vr.midX, y: vr.midY)
            // Rule-of-thirds grid
            Path { path in
                for t in [1.0/3, 2.0/3] as [CGFloat] {
                    path.move(to: CGPoint(x: vr.minX + vr.width * t, y: vr.minY))
                    path.addLine(to: CGPoint(x: vr.minX + vr.width * t, y: vr.maxY))
                    path.move(to: CGPoint(x: vr.minX, y: vr.minY + vr.height * t))
                    path.addLine(to: CGPoint(x: vr.maxX, y: vr.minY + vr.height * t))
                }
            }
            .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private func handleView(_ handle: Handle, imageFrame frame: CGRect) -> some View {
        let pos = handleViewPosition(handle, frame: frame)
        Circle()
            .fill(Color.white)
            .frame(width: 26, height: 26)
            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
            .position(pos)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .local)
                    .onChanged { value in
                        let prev = prevTranslation[handle] ?? .zero
                        let dx = (value.translation.width  - prev.width)  / frame.width
                        let dy = (value.translation.height - prev.height) / frame.height
                        prevTranslation[handle] = value.translation
                        cropRect = applying(handle: handle, dx: dx, dy: dy, to: cropRect)
                    }
                    .onEnded { _ in prevTranslation[handle] = nil }
            )
    }

    // MARK: - Geometry helpers

    private func imageFrame(for imageSize: CGSize, in container: CGSize) -> CGRect {
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width  * scale
        let h = imageSize.height * scale
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }

    private func toViewRect(_ norm: CGRect, frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX + norm.minX * frame.width,
            y: frame.minY + norm.minY * frame.height,
            width: norm.width  * frame.width,
            height: norm.height * frame.height
        )
    }

    private func handleViewPosition(_ handle: Handle, frame: CGRect) -> CGPoint {
        let nx: CGFloat
        let ny: CGFloat
        switch handle {
        case .topLeft:     nx = cropRect.minX; ny = cropRect.minY
        case .topRight:    nx = cropRect.maxX; ny = cropRect.minY
        case .bottomLeft:  nx = cropRect.minX; ny = cropRect.maxY
        case .bottomRight: nx = cropRect.maxX; ny = cropRect.maxY
        }
        return CGPoint(x: frame.minX + nx * frame.width, y: frame.minY + ny * frame.height)
    }

    // MARK: - Crop rect update

    private let minSize: CGFloat = 0.05

    private func applying(handle: Handle, dx: CGFloat, dy: CGFloat, to r: CGRect) -> CGRect {
        var r = r
        switch handle {
        case .topLeft:
            let newX = clamp(r.minX + dx, lo: 0, hi: r.maxX - minSize)
            let newY = clamp(r.minY + dy, lo: 0, hi: r.maxY - minSize)
            r = CGRect(x: newX, y: newY, width: r.maxX - newX, height: r.maxY - newY)
        case .topRight:
            let newMaxX = clamp(r.maxX + dx, lo: r.minX + minSize, hi: 1)
            let newY    = clamp(r.minY + dy, lo: 0,                hi: r.maxY - minSize)
            r = CGRect(x: r.minX, y: newY, width: newMaxX - r.minX, height: r.maxY - newY)
        case .bottomLeft:
            let newX    = clamp(r.minX + dx, lo: 0,                hi: r.maxX - minSize)
            let newMaxY = clamp(r.maxY + dy, lo: r.minY + minSize, hi: 1)
            r = CGRect(x: newX, y: r.minY, width: r.maxX - newX, height: newMaxY - r.minY)
        case .bottomRight:
            let newMaxX = clamp(r.maxX + dx, lo: r.minX + minSize, hi: 1)
            let newMaxY = clamp(r.maxY + dy, lo: r.minY + minSize, hi: 1)
            r = CGRect(x: r.minX, y: r.minY, width: newMaxX - r.minX, height: newMaxY - r.minY)
        }
        return r
    }

    private func clamp<T: Comparable>(_ v: T, lo: T, hi: T) -> T { min(max(v, lo), hi) }

    // MARK: - Apply crop

    private func applyCrop() -> UIImage? {
        // Bake EXIF orientation so pixel coords are correct.
        let renderer = UIGraphicsImageRenderer(size: image.size)
        let normalized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
        guard let cgImage = normalized.cgImage else { return nil }
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let pixelRect = CGRect(
            x: cropRect.minX * w, y: cropRect.minY * h,
            width: cropRect.width * w, height: cropRect.height * h
        )
        guard let cropped = cgImage.cropping(to: pixelRect) else { return nil }
        return UIImage(cgImage: cropped)
    }
}

// MARK: - Handle enum

extension ManualCropView {
    enum Handle: String, CaseIterable, Hashable {
        case topLeft, topRight, bottomLeft, bottomRight
    }
}

// MARK: - Dimming overlay

/// Darkens everything outside the crop rect using an even-odd fill "hole".
private struct CropDimmingOverlay: View {
    let cropRect: CGRect   // normalized 0-1 in image coords
    let imageFrame: CGRect // in view coords

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.addRect(CGRect(origin: .zero, size: size))
            path.addRect(holeRect)
            context.fill(path, with: .color(.black.opacity(0.55)),
                         style: FillStyle(eoFill: true))
        }
        .allowsHitTesting(false)
    }

    private var holeRect: CGRect {
        CGRect(
            x: imageFrame.minX + cropRect.minX * imageFrame.width,
            y: imageFrame.minY + cropRect.minY * imageFrame.height,
            width:  cropRect.width  * imageFrame.width,
            height: cropRect.height * imageFrame.height
        )
    }
}

// MARK: - Preview

#Preview {
    ManualCropView(image: UIImage(systemName: "photo")!) { _ in }
}
#endif
