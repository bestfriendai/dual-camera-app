
//
//  ContentView.swift
//  DualCam Pro
//
//  Main navigation container
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            CameraView()
                .tag(0)
                .tabItem {
                    Label("Camera", systemImage: "camera.fill")
                }
            
            GalleryView()
                .tag(1)
                .tabItem {
                    Label("Gallery", systemImage: "photo.stack.fill")
                }
            
            SettingsView()
                .tag(2)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(.white)
    }
}

#Preview {
    ContentView()
        .environmentObject(SettingsManager())
}
