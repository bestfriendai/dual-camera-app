//
//  OrientationDiagnostics.swift
//  DualLensPro
//
//  Created by Codex on 3/30/24.
//

import AVFoundation
import CoreMedia
import CoreVideo
import UIKit

#if DEBUG
enum OrientationDiagnostics {
    private static let subsystem = "DualLensPro.Orientation"

    private static var logFileURL: URL = {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = dateFormatter.string(from: Date())

        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = cacheURL.appendingPathComponent("OrientationLogs", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("orientation-\(timestamp).log")
    }()

    static func log(_ message: String, file: StaticString = #fileID, line: UInt = #line) {
        let entry = "🧭 [\(subsystem)] \(message) (\(file):\(line))"
        print(entry)

        guard let data = (entry + "\n").data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logFileURL.path) {
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: logFileURL, options: .atomic)
        }
    }

    static func describe(pixelBuffer: CVPixelBuffer) -> String {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let attachments = CVBufferGetAttachments(pixelBuffer, .shouldPropagate) as? [String: Any] ?? [:]
        return "PixelBuffer(width: \(width), height: \(height), format: 0x\(String(pixelFormat, radix: 16)), attachments: \(attachments))"
    }

    static func describe(sampleBuffer: CMSampleBuffer) -> String {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return "SampleBuffer(no format description)"
        }

        let dimensions = CMVideoFormatDescriptionGetDimensions(format)
        let mediaSubType = CMFormatDescriptionGetMediaSubType(format)
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]] ?? []

        var timingInfo = "n/a"
        if var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid) as CMSampleTimingInfo? {
            if CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timing) == noErr {
                timingInfo = "pts: \(timing.presentationTimeStamp.seconds), duration: \(timing.duration.seconds)"
            }
        }

        return "SampleBuffer(dimensions: \(dimensions.width)x\(dimensions.height), subtype: 0x\(String(mediaSubType, radix: 16)), timing: \(timingInfo), attachments: \(attachments))"
    }

    static func logDeviceOrientation(prefix: String) {
        let deviceOrientation = UIDevice.current.orientation
        log("\(prefix) UIDeviceOrientation=\(deviceOrientation.rawValue) (\(deviceOrientation.debugName))")
    }
}

private extension UIDeviceOrientation {
    var debugName: String {
        switch self {
        case .unknown: return "unknown"
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portraitUpsideDown"
        case .landscapeLeft: return "landscapeLeft"
        case .landscapeRight: return "landscapeRight"
        case .faceUp: return "faceUp"
        case .faceDown: return "faceDown"
        @unknown default: return "unhandled"
        }
    }
}
#endif

#if !DEBUG
enum OrientationDiagnostics {
    static func log(_ message: String, file: StaticString = #fileID, line: UInt = #line) { }
    static func describe(pixelBuffer: CVPixelBuffer) -> String { return "" }
    static func describe(sampleBuffer: CMSampleBuffer) -> String { return "" }
    static func logDeviceOrientation(prefix: String) { }
}
#endif
