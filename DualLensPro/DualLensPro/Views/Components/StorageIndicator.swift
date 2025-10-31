//
//  StorageIndicator.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/30/25.
//

import SwiftUI

struct StorageIndicator: View {
    @State private var availableSpace: Int64 = 0
    @State private var showDetailedInfo = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: {
            HapticManager.shared.light()
            showDetailedInfo.toggle()
        }) {
            HStack(spacing: 6) {
                Image(systemName: storageIcon)
                    .font(.system(size: 12, weight: .medium))

                Text(formattedStorage)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(storageColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                if !reduceTransparency {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule()
                                .fill(.black.opacity(0.2))
                        }
                } else {
                    Capsule()
                        .fill(.black.opacity(0.6))
                }
            }
            .shadow(color: .black.opacity(0.2), radius: 4, y: 1)
        }
        .overlay(alignment: .bottom) {
            if showDetailedInfo {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Available Storage")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))

                    Text(formattedStorageDetailed)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)

                    Text("Estimated recording time:")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))

                    Text(estimatedRecordingTime)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .padding(12)
                .background {
                    if !reduceTransparency {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.black.opacity(0.3))
                            }
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.black.opacity(0.8))
                    }
                }
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                .offset(y: 60)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .zIndex(1)
            }
        }
        .onAppear {
            updateStorageInfo()
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            updateStorageInfo()
        }
    }

    private var storageIcon: String {
        if availableGB < 1 {
            return "externaldrive.fill.badge.exclamationmark"
        } else if availableGB < 5 {
            return "externaldrive.fill.badge.minus"
        } else {
            return "externaldrive.fill"
        }
    }

    private var storageColor: Color {
        if availableGB < 1 {
            return .red
        } else if availableGB < 3 {
            return .orange
        } else if availableGB < 5 {
            return .yellow
        } else {
            return .white
        }
    }

    private var availableGB: Double {
        Double(availableSpace) / 1_000_000_000
    }

    private var formattedStorage: String {
        if availableGB >= 1 {
            return String(format: "%.1f GB", availableGB)
        } else {
            let availableMB = Double(availableSpace) / 1_000_000
            return String(format: "%.0f MB", availableMB)
        }
    }

    private var formattedStorageDetailed: String {
        if availableGB >= 1 {
            return String(format: "%.2f GB free", availableGB)
        } else {
            let availableMB = Double(availableSpace) / 1_000_000
            return String(format: "%.0f MB free", availableMB)
        }
    }

    private var estimatedRecordingTime: String {
        // Estimate based on 1080p high quality recording (~25 Mbps for dual camera)
        // 25 Mbps = ~3.125 MB/s per camera × 2 cameras = ~6.25 MB/s total
        let bytesPerSecond: Double = 6_250_000 // ~6.25 MB/s for dual camera
        let estimatedSeconds = Double(availableSpace) / bytesPerSecond

        if estimatedSeconds < 60 {
            return String(format: "~%.0f seconds", estimatedSeconds)
        } else if estimatedSeconds < 3600 {
            let minutes = estimatedSeconds / 60
            return String(format: "~%.0f minutes", minutes)
        } else {
            let hours = estimatedSeconds / 3600
            return String(format: "~%.1f hours", hours)
        }
    }

    private func updateStorageInfo() {
        let tempDir = FileManager.default.temporaryDirectory.path

        if let attributes = try? FileManager.default.attributesOfFileSystem(forPath: tempDir),
           let freeSpace = attributes[.systemFreeSize] as? Int64 {
            availableSpace = freeSpace
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 20) {
            StorageIndicator()
        }
        .padding()
    }
}
