
//
//  CameraPosition.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import AVFoundation

enum CameraPosition: String, CaseIterable, Identifiable, Sendable {
    case front
    case back
    
    var id: String { rawValue }
    
    var avPosition: AVCaptureDevice.Position {
        switch self {
        case .front: return .front
        case .back: return .back
        }
    }
    
    var displayName: String {
        switch self {
        case .front: return "Front Camera"
        case .back: return "Back Camera"
        }
    }
}
