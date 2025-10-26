
//
//  DualCameraApp.swift
//  DualCam Pro
//
//  Created on October 23, 2025
//  Swift 6.0 | iOS 18.0+
//

import SwiftUI

@main
struct DualCameraApp: App {
    @StateObject private var settingsManager = SettingsManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settingsManager)
                .preferredColorScheme(.dark) // Default to dark mode for camera app
        }
    }
}
