
//
//  ContentView.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    // Delay CameraViewModel initialization until onAppear to prevent crashes during app launch
    @State private var cameraViewModel: CameraViewModel?
    @State private var showPermissionAlert = false
    @State private var permissionCheckTimer: Timer?
    @State private var debugAuthStatus = "Initializing..."

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let viewModel = cameraViewModel {
                if viewModel.isAuthorized {
                    DualCameraView()
                        .environmentObject(viewModel)
                        .onAppear {
                            print("✅ DualCameraView appeared - authorized!")
                            stopPermissionPolling()
                        }
                } else {
                    PermissionView(showAlert: $showPermissionAlert)
                        .onAppear {
                            print("⚠️ PermissionView appeared - NOT authorized")
                            startPermissionPolling()
                        }
                        .onDisappear {
                            stopPermissionPolling()
                        }
                }
            } else {
                // Loading state while initializing
                ProgressView()
                    .tint(.white)
            }

            // DEBUG: Show authorization status
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Debug Info:")
                        .font(.caption2.bold())
                        .foregroundStyle(.yellow)
                    Text("VM: \(cameraViewModel != nil ? "✓" : "✗")")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text("isAuth: \(cameraViewModel?.isAuthorized ?? false ? "✓" : "✗")")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text("Cam: \(statusText(AVCaptureDevice.authorizationStatus(for: .video)))")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text("Mic: \(statusText(AVCaptureDevice.authorizationStatus(for: .audio)))")
                        .font(.caption2)
                        .foregroundStyle(.yellow)

                    // Multi-cam support status
                    if let vm = cameraViewModel {
                        Text("Multi-Cam: \(vm.cameraManager.isMultiCamSupported ? "✓ SUPPORTED" : "✗ NOT SUPPORTED")")
                            .font(.caption2.bold())
                            .foregroundStyle(vm.cameraManager.isMultiCamSupported ? .green : .orange)
                        Text("Session: \(vm.cameraManager.isSessionRunning ? "✓ Running" : "✗ Stopped")")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }

                    Text(debugAuthStatus)
                        .font(.caption2)
                        .foregroundStyle(.yellow)

                    if let vm = cameraViewModel {
                        if !vm.errorMessage.isEmpty {
                            Text("ERROR: \(vm.errorMessage)")
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.leading)
                        } else if vm.isAuthorized == false {
                            Text("ERROR: Camera not initialized")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }

                    // Manual refresh button
                    Button("Force Refresh") {
                        print("🔄 FORCE REFRESH TAPPED")
                        cameraViewModel?.checkAuthorization()
                    }
                    .font(.caption2)
                    .foregroundStyle(.cyan)
                    .padding(.top, 4)
                }
                .padding(8)
                .background(.black.opacity(0.7))
                .cornerRadius(8)
                .padding()
            }
        }
        .onAppear {
            // Initialize CameraViewModel AFTER the view appears, not during init
            if cameraViewModel == nil {
                cameraViewModel = CameraViewModel()
            }
            cameraViewModel?.checkAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Re-check authorization when app returns to foreground (after permission dialog)
            cameraViewModel?.checkAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Re-check when app becomes active (handles iOS 26 overlay permission dialogs)
            cameraViewModel?.checkAuthorization()
        }
        .alert("Camera Access Required", isPresented: $showPermissionAlert) {
            Button("Settings", action: openSettings)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please enable camera and microphone access in Settings to use DualLens Pro.")
        }
    }

    private func startPermissionPolling() {
        print("🔄 Starting permission polling...")
        stopPermissionPolling()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [cameraViewModel, debugAuthStatus] _ in
            // No weak self needed - ContentView is a struct (value type)
            if let vm = cameraViewModel {
                let authStatus = vm.isAuthorized
                print("🔍 Polling - isAuthorized: \(authStatus)")
                vm.checkAuthorization()
            }
        }
    }

    private func stopPermissionPolling() {
        print("🛑 Stopping permission polling")
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
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
