
//
//  RecordingState.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import Foundation

enum RecordingState: Sendable {
    case idle
    case recording
    case paused
    case processing

    var isRecording: Bool {
        self == .recording
    }

    var displayText: String {
        switch self {
        case .idle: return "Ready"
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .processing: return "Processing"
        }
    }
}
