//
//  ThermalStateMonitor.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/30/25.
//

import Foundation
import Combine

@MainActor
class ThermalStateMonitor: ObservableObject {
    @Published var currentState: ProcessInfo.ThermalState = .nominal
    @Published var shouldReduceQuality = false
    @Published var shouldStopRecording = false
    @Published var thermalWarning: String?

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Set initial state
        currentState = ProcessInfo.processInfo.thermalState
        setupMonitoring()
    }

    private func setupMonitoring() {
        NotificationCenter.default.publisher(
            for: ProcessInfo.thermalStateDidChangeNotification
        )
        .sink { [weak self] _ in
            Task { @MainActor in
                self?.updateThermalState()
            }
        }
        .store(in: &cancellables)

        // Initial evaluation
        updateThermalState()
    }

    private func updateThermalState() {
        currentState = ProcessInfo.processInfo.thermalState

        switch currentState {
        case .nominal:
            shouldReduceQuality = false
            shouldStopRecording = false
            thermalWarning = nil

        case .fair:
            shouldReduceQuality = false
            shouldStopRecording = false
            thermalWarning = "Device temperature is elevated"

        case .serious:
            shouldReduceQuality = true
            shouldStopRecording = false
            thermalWarning = "High temperature detected. Reducing quality to prevent overheating."

        case .critical:
            shouldReduceQuality = true
            shouldStopRecording = true
            thermalWarning = "Critical temperature! Recording will be stopped."

        @unknown default:
            shouldReduceQuality = false
            shouldStopRecording = false
            thermalWarning = nil
        }
    }

    // MARK: - Quality Adjustment Recommendations

    func recommendedResolution(current: RecordingQuality) -> RecordingQuality {
        guard shouldReduceQuality else { return current }

        switch current {
        case .ultra:
            return .high
        case .high:
            return .medium
        case .medium:
            return .low
        case .low:
            return current
        }
    }

    func recommendedFrameRate(current: Int) -> Int {
        guard shouldReduceQuality else { return current }

        // Reduce frame rate to lower thermal load
        if current == 120 {
            return 60
        } else if current == 60 {
            return 30
        }
        return current
    }

    // MARK: - Human-Readable State

    var stateDescription: String {
        switch currentState {
        case .nominal:
            return "Normal"
        case .fair:
            return "Warm"
        case .serious:
            return "Hot"
        case .critical:
            return "Critical"
        @unknown default:
            return "Unknown"
        }
    }

    var stateColor: String {
        switch currentState {
        case .nominal:
            return "green"
        case .fair:
            return "yellow"
        case .serious:
            return "orange"
        case .critical:
            return "red"
        @unknown default:
            return "gray"
        }
    }
}
