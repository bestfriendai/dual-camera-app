//
//  ContentView.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI
import AVFoundation
import Combine

struct ContentView: View {
    // Use StateObject to properly observe CameraViewModel's @Published properties
    @StateObject private var cameraViewModel = CameraViewModel()
    @State private var showPermissionAlert = false
    @State private var debugAuthStatus = "Initializing..."
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if cameraViewModel.isAuthorized {
                DualCameraView()
                    .environmentObject(cameraViewModel)
                    .onAppear {
                        print("✅ DualCameraView appeared - authorized!")
                    }
            } else {
                PermissionView(showAlert: $showPermissionAlert)
                    .environmentObject(cameraViewModel)
                    .onAppear {
                        print("⚠️ PermissionView appeared - NOT authorized")
                    }
            }

            // DEBUG: Show authorization status - Hidden in production
            // Uncomment the code below for debugging
            /*
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Debug Info:")
                        .font(.caption2.bold())
                        .foregroundStyle(.yellow)
                    Text("VM: ✓")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text("isAuth: \(cameraViewModel.isAuthorized ? "✓" : "✗")")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text("Cam: \(statusText(AVCaptureDevice.authorizationStatus(for: .video)))")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text("Mic: \(statusText(AVCaptureDevice.authorizationStatus(for: .audio)))")
                        .font(.caption2)
                        .foregroundStyle(.yellow)

                    // Multi-cam support status
                    Text("Multi-Cam: \(cameraViewModel.cameraManager.isMultiCamSupported ? "✓ SUPPORTED" : "✗ NOT SUPPORTED")")
                        .font(.caption2.bold())
                        .foregroundStyle(cameraViewModel.cameraManager.isMultiCamSupported ? .green : .orange)
                    Text("Session: \(cameraViewModel.cameraManager.isSessionRunning ? "✓ Running" : "✗ Stopped")")
                        .font(.caption2)
                        .foregroundStyle(.yellow)

                    if let errorMsg = cameraViewModel.errorMessage, !errorMsg.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ERROR:")
                                .font(.caption2.bold())
                                .foregroundStyle(.red)
                            Text(errorMsg)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.leading)
                        }
                    } else if cameraViewModel.isAuthorized == false {
                        Text("ERROR: Camera not initialized")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }

                    // Manual refresh button
                    Button("Force Refresh") {
                        print("🔄 FORCE REFRESH TAPPED")
                        cameraViewModel.checkAuthorization()
                    }
                    .font(.caption2)
                    .foregroundStyle(.cyan)
                    .padding(.top, 4)

                    // Show error in PermissionView too
                    if let errorMsg = cameraViewModel.errorMessage, !errorMsg.isEmpty {
                        Button("View Full Error") {
                            print("Full error: \(errorMsg)")
                        }
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    }
                }
                .padding(8)
                .background(.black.opacity(0.7))
                .cornerRadius(8)
                .padding()
            }
            */
        }
        .onAppear {
            setupNotificationObservers()
            cameraViewModel.checkAuthorization()
        }
        .onDisappear {
            teardownNotificationObservers()
        }
        .alert("Camera Access Required", isPresented: $showPermissionAlert) {
            Button("Settings", action: openSettings)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please enable camera and microphone access in Settings to use DualLens Pro.")
        }
    }

    private func setupNotificationObservers() {
        // App lifecycle - observe when app becomes active
        NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak cameraViewModel] _ in
                if let vm = cameraViewModel, !vm.isAuthorized {
                    print("🔔 App became active - re-checking authorization")
                    vm.checkAuthorization()
                }
            }
            .store(in: &cancellables)

        // Manual authorization check trigger
        NotificationCenter.default
            .publisher(for: .init("ForceCheckAuthorization"))
            .sink { [weak cameraViewModel] _ in
                print("🔔 Received ForceCheckAuthorization notification")
                cameraViewModel?.checkAuthorization()
            }
            .store(in: &cancellables)
    }

    private func teardownNotificationObservers() {
        cancellables.removeAll()
        print("🧹 ContentView notification observers cleaned up")
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func statusText(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "✓"
        case .denied: return "✗"
        case .notDetermined: return "?"
        case .restricted: return "R"
        @unknown default: return "U"
        }
    }
}

#Preview {
    ContentView()
}
