
//
//  CameraPreviewView.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer?
    let position: CameraPosition
    let onZoomChange: (CGFloat) -> Void
    let currentZoom: CGFloat
    let minZoom: CGFloat  // ✅ FIX: Use actual device zoom range
    let maxZoom: CGFloat
    let onFocusTap: ((CGPoint) -> Void)?
    
    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.backgroundColor = .black

        guard let layer = previewLayer else {
            print("⚠️ Preview layer is nil for \(position) camera - camera not initialized")

            // Add error indicator view
            let errorLabel = UILabel()
            errorLabel.text = "Camera Unavailable"
            errorLabel.textColor = .white
            errorLabel.textAlignment = .center
            errorLabel.font = .systemFont(ofSize: 14, weight: .medium)
            errorLabel.translatesAutoresizingMaskIntoConstraints = false

            view.addSubview(errorLabel)
            NSLayoutConstraint.activate([
                errorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])

            return view
        }

        layer.frame = view.bounds
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)

        // Add pinch gesture for zoom
        let pinchGesture = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        pinchGesture.delegate = context.coordinator  // ✅ Enable simultaneous gesture recognition
        view.addGestureRecognizer(pinchGesture)

        // Add tap gesture for focus
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tapGesture.delegate = context.coordinator
        view.addGestureRecognizer(tapGesture)

        return view
    }
    
    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if let layer = previewLayer {
            layer.frame = uiView.bounds
        }
        context.coordinator.currentZoom = currentZoom
        context.coordinator.minZoom = minZoom  // ✅ FIX: Update zoom ranges
        context.coordinator.maxZoom = maxZoom
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onZoomChange: onZoomChange,
            initialZoom: currentZoom,
            minZoom: minZoom,
            maxZoom: maxZoom,
            onFocusTap: onFocusTap
        )
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let onZoomChange: (CGFloat) -> Void
        let onFocusTap: ((CGPoint) -> Void)?
        var currentZoom: CGFloat
        var minZoom: CGFloat  // ✅ FIX: Actual device zoom range
        var maxZoom: CGFloat
        var lastScale: CGFloat = 1.0

        init(
            onZoomChange: @escaping (CGFloat) -> Void,
            initialZoom: CGFloat,
            minZoom: CGFloat,
            maxZoom: CGFloat,
            onFocusTap: ((CGPoint) -> Void)?
        ) {
            self.onZoomChange = onZoomChange
            self.currentZoom = initialZoom
            self.minZoom = minZoom
            self.maxZoom = maxZoom
            self.onFocusTap = onFocusTap
        }

        @MainActor
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                lastScale = currentZoom
                print("🤏 Pinch began - currentZoom: \(currentZoom), range: \(minZoom)-\(maxZoom)")
            case .changed:
                // ✅ IMPROVED ZOOM: Use gesture.scale directly multiplied by initial zoom
                // This provides more natural and responsive pinch-to-zoom behavior
                let newZoom = lastScale * gesture.scale

                // ✅ CRITICAL ZOOM FIX: Clamp to actual device capabilities
                // This fixes the "zoom stuck at 1.0x" issue where gestures requested invalid zoom levels
                let clampedZoom = min(max(newZoom, minZoom), maxZoom)

                print("🤏 Pinch changed - gestureScale: \(gesture.scale), newZoom: \(newZoom), clamped: \(clampedZoom)")
                onZoomChange(clampedZoom)
                currentZoom = clampedZoom
            case .ended, .cancelled:
                lastScale = currentZoom
                print("🤏 Pinch ended - final zoom: \(currentZoom)")
            default:
                break
            }
        }

        @MainActor
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            let location = gesture.location(in: view)

            // Call the focus tap handler with the tap location
            onFocusTap?(location)
        }

        // ✅ Allow simultaneous gesture recognition for better button responsiveness
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                              shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
    }
    
    class PreviewUIView: UIView {
        override func layoutSubviews() {
            super.layoutSubviews()
            
            // Update all sublayers frames
            layer.sublayers?.forEach { sublayer in
                if sublayer is AVCaptureVideoPreviewLayer {
                    sublayer.frame = bounds
                }
            }
        }
    }
}
