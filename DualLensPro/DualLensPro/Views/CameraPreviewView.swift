
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
        view.addGestureRecognizer(pinchGesture)

        return view
    }
    
    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if let layer = previewLayer {
            layer.frame = uiView.bounds
        }
        context.coordinator.currentZoom = currentZoom
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onZoomChange: onZoomChange, initialZoom: currentZoom)
    }
    
    class Coordinator: NSObject {
        let onZoomChange: (CGFloat) -> Void
        var currentZoom: CGFloat
        var lastScale: CGFloat = 1.0
        
        init(onZoomChange: @escaping (CGFloat) -> Void, initialZoom: CGFloat) {
            self.onZoomChange = onZoomChange
            self.currentZoom = initialZoom
        }
        
        @MainActor
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                lastScale = 1.0
            case .changed:
                let scale = gesture.scale

                // Calculate new zoom factor
                let delta = (scale - lastScale) * 0.5
                let newZoom = currentZoom * (1 + delta)

                // Clamp between 0.5 and 10.0 (allow zoom out to 0.5x)
                let clampedZoom = min(max(newZoom, 0.5), 10.0)

                onZoomChange(clampedZoom)
                lastScale = scale
            case .ended, .cancelled:
                lastScale = 1.0
            default:
                break
            }
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
