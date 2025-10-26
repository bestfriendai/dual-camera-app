
//
//  PermissionView.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI
import AVFoundation

struct PermissionView: View {
    @Binding var showAlert: Bool
    @State private var isRequesting = false
    @State private var debugInfo: String = ""
    @EnvironmentObject var cameraViewModel: CameraViewModel

    var body: some View {
        VStack(spacing: 30) {
            // App Icon Placeholder
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "video.badge.plus")
                    .font(.system(size: 50, weight: .light))
                    .foregroundStyle(.white)
            }
            .shadow(color: .purple.opacity(0.3), radius: 20)
            
            VStack(spacing: 12) {
                Text("Welcome to DualLens Pro")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                
                Text("Record from both cameras simultaneously")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 16) {
                PermissionRow(
                    icon: "video.fill",
                    title: "Camera Access",
                    description: "Required to capture video from both cameras"
                )
                
                PermissionRow(
                    icon: "mic.fill",
                    title: "Microphone Access",
                    description: "Required to record audio with your videos"
                )
                
                PermissionRow(
                    icon: "photo.fill",
                    title: "Photo Library Access",
                    description: "Required to save your recorded videos"
                )
            }
            .padding(.vertical, 20)
            
            Button(action: {
                requestPermissions()
            }) {
                HStack(spacing: 8) {
                    if isRequesting {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isRequesting ? "Requesting..." : "Grant Permissions")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .glassButton(tint: .blue, isActive: !isRequesting)
            .disabled(isRequesting)
            .padding(.horizontal, 40)

            // Debug info
            if !debugInfo.isEmpty {
                Text(debugInfo)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Show camera error from ViewModel
            if !cameraViewModel.errorMessage.isEmpty {
                VStack(spacing: 8) {
                    Text("Camera Setup Error:")
                        .font(.caption.bold())
                        .foregroundStyle(.red)

                    Text(cameraViewModel.errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
                .background(.red.opacity(0.2))
                .cornerRadius(12)
                .padding(.horizontal, 20)
            }

            // Try Again button (for debugging)
            if debugInfo.contains("granted") || !cameraViewModel.errorMessage.isEmpty {
                Button(action: {
                    print("🔄 Manual retry button tapped")
                    // Trigger checkAuthorization
                    NotificationCenter.default.post(name: .init("ForceCheckAuthorization"), object: nil)
                }) {
                    Text("Try Again / Refresh")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .underline()
                }
                .padding(.top, 8)
            }
        }
        .padding(40)
        .onAppear {
            checkCurrentStatus()
        }
    }

    private func checkCurrentStatus() {
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        debugInfo = "Camera: \(statusString(cameraStatus))\nMicrophone: \(statusString(audioStatus))"
        print("📊 Current status - Camera: \(statusString(cameraStatus)), Mic: \(statusString(audioStatus))")
    }

    private func statusString(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "Authorized"
        case .denied: return "DENIED"
        case .notDetermined: return "Not Asked"
        case .restricted: return "Restricted"
        @unknown default: return "Unknown"
        }
    }

    private func requestPermissions() {
        print("🔐 Button tapped - Requesting permissions...")

        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        print("📊 Before request - Camera: \(statusString(cameraStatus)), Mic: \(statusString(audioStatus))")

        // If already authorized, trigger camera initialization directly
        if cameraStatus == .authorized && audioStatus == .authorized {
            print("✅ Permissions already granted - triggering camera initialization via notification")
            debugInfo = "Permissions already granted! Initializing camera..."

            // Post notification to trigger camera initialization in ContentView
            NotificationCenter.default.post(name: .init("ForceCheckAuthorization"), object: nil)
            return
        }

        // If already denied, must go to Settings
        if cameraStatus == .denied || audioStatus == .denied {
            print("⚠️ Permissions already denied - must use Settings")
            debugInfo = "Permissions denied. Please enable in Settings."
            showAlert = true
            return
        }

        isRequesting = true
        debugInfo = "Requesting permissions..."

        Task {
            // Request camera permission
            print("📹 Requesting camera access...")
            let cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
            print("📹 Camera access: \(cameraGranted ? "✅ GRANTED" : "❌ DENIED")")

            // Request microphone permission
            print("🎤 Requesting microphone access...")
            let audioGranted = await AVCaptureDevice.requestAccess(for: .audio)
            print("🎤 Microphone access: \(audioGranted ? "✅ GRANTED" : "❌ DENIED")")

            await MainActor.run {
                isRequesting = false
                print("🔐 Permission request complete")

                checkCurrentStatus()

                // If either permission was denied, show alert to go to Settings
                if !cameraGranted || !audioGranted {
                    print("⚠️ Showing settings alert")
                    debugInfo = "Permissions denied. Please enable in Settings."
                    showAlert = true
                } else {
                    print("✅ All permissions granted - ContentView should detect this")
                    debugInfo = "Permissions granted!"

                    // Post notification to trigger camera initialization
                    NotificationCenter.default.post(name: .init("ForceCheckAuthorization"), object: nil)
                }
            }
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 44, height: 44)
                .circleGlass(tint: .blue, size: 44)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        PermissionView(showAlert: .constant(false))
    }
}
