
//
//  VideoOutput.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import Foundation

struct VideoOutput: Identifiable {
    let id = UUID()
    let url: URL
    let type: OutputType
    let duration: TimeInterval
    let createdAt: Date
    
    enum OutputType: String {
        case frontCamera = "Front Camera"
        case backCamera = "Back Camera"
        case combined = "Combined (PiP)"
    }
    
    var filename: String {
        url.lastPathComponent
    }
}
