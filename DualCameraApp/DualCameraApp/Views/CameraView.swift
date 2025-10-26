//
//  CameraView.swift
//  DualCam Pro
//
//  Main camera recording interface
//

import SwiftUI
import AVFoundation

struct CameraView: View {
    @StateObject private var viewModel = CameraViewModel()
    @EnvironmentObject var settings: SettingsManager
    @State private var showError = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isSessionReady {
                // Camera preview would go here
                VStack {
                    Spacer()

                    // Recording button
                    Button(action: {
                        Task {
                            await viewModel.toggleRecording(settings: settings.settings)
                        }
                    }) {
                        Circle()
                            .fill(viewModel.recordingState == .recording ? Color.red : Color.white)
                            .frame(width: 70, height: 70)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 3)
                                    .frame(width: 80, height: 80)
                            )
                    }
                    .padding(.bottom, 40)

                    // Recording duration
                    if viewModel.recordingState == .recording {
                        Text(formatDuration(viewModel.recordingDuration))
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.bottom, 20)
                    }
                }
            } else {
                VStack {
                    ProgressView("Setting up camera...")
                        .foregroundColor(.white)
                }
            }
        }
        .task {
            await viewModel.setupCamera(settings: settings.settings)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
        .onChange(of: viewModel.errorMessage) { oldValue, newValue in
            if newValue != nil {
                showError = true
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    CameraView()
        .environmentObject(SettingsManager())
}
