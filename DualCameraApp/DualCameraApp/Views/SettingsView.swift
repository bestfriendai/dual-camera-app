//
//  SettingsView.swift
//  DualCam Pro
//
//  App settings and preferences
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        NavigationStack {
            Form {
                Section("Video Quality") {
                    Picker("Resolution", selection: $settingsManager.resolution) {
                        ForEach(VideoResolution.allCases, id: \.self) { resolution in
                            Text(resolution.rawValue).tag(resolution)
                        }
                    }

                    Picker("Frame Rate", selection: $settingsManager.frameRate) {
                        ForEach(FrameRate.allCases, id: \.self) { rate in
                            Text("\(rate.rawValue) fps").tag(rate)
                        }
                    }

                    Picker("Codec", selection: $settingsManager.codec) {
                        ForEach(VideoCodec.allCases, id: \.self) { codec in
                            Text(codec.rawValue).tag(codec)
                        }
                    }
                }

                Section("Camera") {
                    Picker("Stabilization", selection: $settingsManager.stabilization) {
                        ForEach(StabilizationMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }

                    Picker("Focus Mode", selection: $settingsManager.focusMode) {
                        ForEach(FocusMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }

                    Picker("Exposure Mode", selection: $settingsManager.exposureMode) {
                        ForEach(ExposureMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text("1")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// Extensions already defined in Enums.swift - using rawValue for display

#Preview {
    SettingsView()
        .environmentObject(SettingsManager())
}
