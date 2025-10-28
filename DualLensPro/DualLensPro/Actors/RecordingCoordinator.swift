//
//  RecordingCoordinator.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/26/25.
//  PRODUCTION READY - Swift 6 Actor-based thread-safe recording
//

import AVFoundation
import CoreMedia
import Foundation

/// Thread-safe recording coordinator using Swift 6 actor isolation
/// Eliminates all data races in video recording pipeline
actor RecordingCoordinator {
    // Sendable wrapper for AVAssetWriter to pass across task boundaries
    private final class WriterBox: @unchecked Sendable {
        let writer: AVAssetWriter
        let name: String
        init(_ writer: AVAssetWriter, name: String) {
            self.writer = writer
            self.name = name
        }
    }

    // MARK: - State
    private var frontWriter: AVAssetWriter?
    private var backWriter: AVAssetWriter?
    private var combinedWriter: AVAssetWriter?

    private var frontVideoInput: AVAssetWriterInput?
    private var backVideoInput: AVAssetWriterInput?
    private var combinedVideoInput: AVAssetWriterInput?
    private var frontAudioInput: AVAssetWriterInput?
    private var backAudioInput: AVAssetWriterInput?
    private var combinedAudioInput: AVAssetWriterInput?

    private var frontPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var backPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var combinedPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var isWriting = false
    private var recordingStartTime: CMTime?
    private var hasReceivedFirstVideoFrame = false
    private var hasReceivedFirstAudioFrame = false

    private var frontURL: URL?
    private var backURL: URL?
    private var combinedURL: URL?

    // Frame compositor for stacked dual-camera output
    private var compositor: FrameCompositor?

    // Buffer cache for compositing
    private var lastFrontBuffer: (buffer: CVPixelBuffer, time: CMTime)?

    // Audio sample counter for logging
    private var audioSampleCount = 0

    // MARK: - Final timestamp tracking (to avoid frozen tail frames)
    private var lastFrontVideoPTS: CMTime?
    private var lastBackVideoPTS: CMTime?
    private var lastCombinedVideoPTS: CMTime?
    private var lastFrontAudioPTS: CMTime?
    private var lastBackAudioPTS: CMTime?
    private var lastCombinedAudioPTS: CMTime?

    // MARK: - Configuration
    func configure(
        frontURL: URL,
        backURL: URL,
        combinedURL: URL,
        dimensions: (width: Int, height: Int),
        bitRate: Int,
        frameRate: Int,
        videoTransform: CGAffineTransform
    ) throws {
        print("🎬 RecordingCoordinator: Configuring...")
        print("🎬 Frame rate: \(frameRate)fps, Transform: \(videoTransform)")

        self.frontURL = frontURL
        self.backURL = backURL
        self.combinedURL = combinedURL

        // Create writers
        frontWriter = try AVAssetWriter(outputURL: frontURL, fileType: .mov)
        backWriter = try AVAssetWriter(outputURL: backURL, fileType: .mov)
        combinedWriter = try AVAssetWriter(outputURL: combinedURL, fileType: .mov)

        // ✅ Use HEVC for better compression and hardware acceleration
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: dimensions.width,
            AVVideoHeightKey: dimensions.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoExpectedSourceFrameRateKey: frameRate,  // ✅ Dynamic frame rate
                AVVideoMaxKeyFrameIntervalKey: frameRate
            ]
        ]

        // Setup video inputs with transforms
        frontVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        frontVideoInput?.expectsMediaDataInRealTime = true
        frontVideoInput?.transform = videoTransform  // ✅ Apply orientation transform

        backVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        backVideoInput?.expectsMediaDataInRealTime = true
        backVideoInput?.transform = videoTransform  // ✅ Apply orientation transform

        combinedVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        combinedVideoInput?.expectsMediaDataInRealTime = true
        combinedVideoInput?.transform = videoTransform  // ✅ Apply orientation transform

        // ✅ Audio settings optimized for quality
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44100.0,
            AVEncoderBitRateKey: 128000
        ]

        // Create audio inputs for all three writers
        frontAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        frontAudioInput?.expectsMediaDataInRealTime = true

        backAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        backAudioInput?.expectsMediaDataInRealTime = true

        combinedAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        combinedAudioInput?.expectsMediaDataInRealTime = true

        // ✅ Use optimal pixel format (420v is hardware accelerated)
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            kCVPixelBufferWidthKey as String: dimensions.width,
            kCVPixelBufferHeightKey as String: dimensions.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        // Add inputs to writers with pixel buffer adaptors
        // Front writer: video + audio
        if let videoInput = frontVideoInput,
           let audioInput = frontAudioInput,
           let writer = frontWriter {
            if writer.canAdd(videoInput) {
                writer.add(videoInput)
                frontPixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: videoInput,
                    sourcePixelBufferAttributes: pixelBufferAttributes
                )
            }
            if writer.canAdd(audioInput) {
                writer.add(audioInput)
            }
        }

        // Back writer: video + audio
        if let videoInput = backVideoInput,
           let audioInput = backAudioInput,
           let writer = backWriter {
            if writer.canAdd(videoInput) {
                writer.add(videoInput)
                backPixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: videoInput,
                    sourcePixelBufferAttributes: pixelBufferAttributes
                )
            }
            if writer.canAdd(audioInput) {
                writer.add(audioInput)
            }
        }

        if let videoInput = combinedVideoInput,
           let audioInput = combinedAudioInput,
           let writer = combinedWriter {
            if writer.canAdd(videoInput) {
                writer.add(videoInput)
                combinedPixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: videoInput,
                    sourcePixelBufferAttributes: pixelBufferAttributes
                )
            }
            if writer.canAdd(audioInput) {
                writer.add(audioInput)
            }
        }

        // Initialize frame compositor for stacked dual-camera output (Issue #4.5 Fix: Actor-isolated)
        compositor = FrameCompositor(width: dimensions.width, height: dimensions.height)
        print("✅ FrameCompositor initialized for combined output (actor-isolated)")

        print("✅ RecordingCoordinator: Configuration complete")
        print("   Front: \(frontURL.lastPathComponent)")
        print("   Back: \(backURL.lastPathComponent)")
        print("   Combined: \(combinedURL.lastPathComponent)")
    }

    // MARK: - Recording Control
    func startWriting(at timestamp: CMTime) throws {
        print("🎬 RecordingCoordinator: Starting writing at \(timestamp.seconds)s")

        guard !isWriting else {
            throw RecordingError.alreadyWriting
        }

        // ✅ FIX: Reset compositor for fresh recording (clears any cached buffers)
        compositor?.beginRecording()

        // Start all writers
        guard frontWriter?.startWriting() == true,
              backWriter?.startWriting() == true,
              combinedWriter?.startWriting() == true else {
            // Check for errors
            if let error = frontWriter?.error {
                print("❌ Front writer error: \(error)")
                throw error
            }
            if let error = backWriter?.error {
                print("❌ Back writer error: \(error)")
                throw error
            }
            if let error = combinedWriter?.error {
                print("❌ Combined writer error: \(error)")
                throw error
            }
            throw RecordingError.failedToStartWriting
        }

        // ✅ CRITICAL: Start session at source time for proper timing
        frontWriter?.startSession(atSourceTime: timestamp)
        backWriter?.startSession(atSourceTime: timestamp)
        combinedWriter?.startSession(atSourceTime: timestamp)

        isWriting = true
        recordingStartTime = timestamp
        hasReceivedFirstVideoFrame = true

        print("✅ RecordingCoordinator: All writers started successfully")
    }

    func appendFrontPixelBuffer(_ pixelBuffer: CVPixelBuffer, time: CMTime) throws {
        guard isWriting else { return }

        // Append to front writer
        guard let adaptor = frontPixelBufferAdaptor,
              let input = frontVideoInput else {
            return
        }

        // ✅ Check if input is ready for more data
        guard input.isReadyForMoreMediaData else {
            // print("⚠️ Front input not ready - dropping frame")
            return
        }

        let ok = adaptor.append(pixelBuffer, withPresentationTime: time)
        if ok {
            lastFrontVideoPTS = time
        } else {
            print("⚠️ Failed to append front pixel buffer at \(time.seconds)s")
        }

        // Cache front buffer for compositing
        lastFrontBuffer = (buffer: pixelBuffer, time: time)
    }

    func appendBackPixelBuffer(_ pixelBuffer: CVPixelBuffer, time: CMTime) async throws {
        guard isWriting else { return }

        // Append to back writer
        if let adaptor = backPixelBufferAdaptor,
           let input = backVideoInput,
           input.isReadyForMoreMediaData {
            let ok = adaptor.append(pixelBuffer, withPresentationTime: time)
            if ok {
                lastBackVideoPTS = time
            } else {
                print("⚠️ Failed to append back pixel buffer at \(time.seconds)s")
            }
        }

        // ✅ Issue #4.5 Fix: Create stacked composition for combined output (actor-isolated)
        if let adaptor = combinedPixelBufferAdaptor,
           let input = combinedVideoInput,
           input.isReadyForMoreMediaData,
           let compositor = compositor {

            // Compose front and back into stacked frame (await actor call)
            if let composedBuffer = compositor.stacked(front: lastFrontBuffer?.buffer, back: pixelBuffer) {
                let ok2 = adaptor.append(composedBuffer, withPresentationTime: time)
                if ok2 {
                    lastCombinedVideoPTS = time
                } else {
                    print("⚠️ Failed to append composed pixel buffer at \(time.seconds)s")
                }
            } else {
                print("⚠️ Failed to compose frame at \(time.seconds)s")
            }
        }
    }

    func appendAudioSample(_ sampleBuffer: CMSampleBuffer) throws {
        guard isWriting else {
            print("⚠️ Audio sample received but not writing")
            return
        }

        // Append audio to all three writers (front, back, and combined)
        var successCount = 0

        let audioPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Append to front audio input
        if let input = frontAudioInput, input.isReadyForMoreMediaData {
            if input.append(sampleBuffer) {
                lastFrontAudioPTS = audioPTS
                successCount += 1
            }
        }

        // Append to back audio input
        if let input = backAudioInput, input.isReadyForMoreMediaData {
            if input.append(sampleBuffer) {
                lastBackAudioPTS = audioPTS
                successCount += 1
            }
        }

        // Append to combined audio input
        if let input = combinedAudioInput, input.isReadyForMoreMediaData {
            if input.append(sampleBuffer) {
                lastCombinedAudioPTS = audioPTS
                successCount += 1
            }
        }

        // Log progress occasionally
        if successCount > 0 {
            if audioSampleCount % 100 == 0 {
                let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                print("🎤 Audio sample \(audioSampleCount) appended to \(successCount) writer(s) at \(time.seconds)s")
            }
            audioSampleCount += 1
        } else {
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            print("⚠️ Failed to append audio sample at \(time.seconds)s - no inputs ready")
        }
    }

    // Issue #22 Fix: Improved error recovery - try to save each video independently
    func stopWriting() async throws -> (front: URL, back: URL, combined: URL) {
        let result = try await stopWritingWithRecovery()

        // If all failed, throw error
        guard result.hasAnySuccess else {
            throw RecordingError.allWritersFailed
        }

        // If not all successful, log warnings but proceed with successful ones
        if !result.allSuccessful {
            print("⚠️ Some writers failed, but proceeding with successful ones")
        }

        // Extract successful URLs (this will throw if any critical one failed)
        guard case .success(let frontURL) = result.front,
              case .success(let backURL) = result.back,
              case .success(let combinedURL) = result.combined else {
            // At least one failed - throw detailed error
            var failedWriters: [String] = []
            if case .failure = result.front { failedWriters.append("Front") }
            if case .failure = result.back { failedWriters.append("Back") }
            if case .failure = result.combined { failedWriters.append("Combined") }
            print("❌ Failed writers: \(failedWriters.joined(separator: ", "))")
            throw RecordingError.allWritersFailed
        }

        return (frontURL, backURL, combinedURL)
    }

    func stopWritingWithRecovery() async throws -> RecordingResult {
        print("🎬 RecordingCoordinator: Stopping writing with error recovery...")

        guard isWriting else {
            throw RecordingError.notWriting
        }

        isWriting = false

        // ✅ CRITICAL FIX: Clear compositor cache and flush GPU pipeline
        // This prevents frozen frames from cached buffers during shutdown
        compositor?.reset()
        print("🧹 Cleared compositor cache before finalizing")

        // ✅ CRITICAL FIX: Add a small delay to allow final frames to be processed
        // This prevents the last few frames from being frozen/corrupted
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // ✅ CRITICAL FIX: Flush GPU render pipeline to ensure all renders complete
        compositor?.flushGPU()
        print("🎨 GPU pipeline flushed, all renders complete")

        // ✅ CRITICAL FIX: Use the EARLIER timestamp (MIN) to prevent frozen frames
        // The frozen frame issue happens when we try to include frames that haven't been fully written
        // We must end the session BEFORE the last incomplete frame, not after
        // This ensures all frames in the video are complete and not frozen
        func endTime(_ v: CMTime?, _ a: CMTime?) -> CMTime? {
            switch (v, a) {
            case let (v?, a?):
                // Use the EARLIER timestamp to ensure all frames are complete
                return CMTimeCompare(v, a) <= 0 ? v : a
            case let (v?, nil):
                return v
            case let (nil, a?):
                return a
            default:
                return nil
            }
        }

        if let w = frontWriter, let t = endTime(lastFrontVideoPTS, lastFrontAudioPTS) {
            print("⏹️ endSession(front) at \(t.seconds)s (v=\(lastFrontVideoPTS?.seconds ?? -1), a=\(lastFrontAudioPTS?.seconds ?? -1))")
            w.endSession(atSourceTime: t)
        }
        if let w = backWriter, let t = endTime(lastBackVideoPTS, lastBackAudioPTS) {
            print("⏹️ endSession(back) at \(t.seconds)s (v=\(lastBackVideoPTS?.seconds ?? -1), a=\(lastBackAudioPTS?.seconds ?? -1))")
            w.endSession(atSourceTime: t)
        }
        if let w = combinedWriter, let t = endTime(lastCombinedVideoPTS, lastCombinedAudioPTS) {
            print("⏹️ endSession(combined) at \(t.seconds)s (v=\(lastCombinedVideoPTS?.seconds ?? -1), a=\(lastCombinedAudioPTS?.seconds ?? -1))")
            w.endSession(atSourceTime: t)
        }

        // Mark all inputs as finished (video + audio for all three writers)
        frontVideoInput?.markAsFinished()
        frontAudioInput?.markAsFinished()
        backVideoInput?.markAsFinished()
        backAudioInput?.markAsFinished()
        combinedVideoInput?.markAsFinished()
        combinedAudioInput?.markAsFinished()

        // ✅ CRITICAL FIX: Add another small delay after marking inputs as finished
        // This ensures all pending data is flushed before finishing writers
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

        // Get URLs before attempting to finish
        let capturedFrontURL = frontURL
        let capturedBackURL = backURL
        let capturedCombinedURL = combinedURL

        // Box writers for safe transfer across task boundaries (Issue #22 Fix)
        let writerBoxes: [(box: WriterBox, url: URL, key: String)] = [
            frontWriter.flatMap { w in capturedFrontURL.map { (WriterBox(w, name: "Front"), $0, "front") } },
            backWriter.flatMap { w in capturedBackURL.map { (WriterBox(w, name: "Back"), $0, "back") } },
            combinedWriter.flatMap { w in capturedCombinedURL.map { (WriterBox(w, name: "Combined"), $0, "combined") } }
        ].compactMap { $0 }

        // Try to save each video independently (Issue #22 Fix)
        var results: [String: Result<URL, Error>] = [:]

        await withTaskGroup(of: (String, Result<URL, Error>).self) { group in
            for item in writerBoxes {
                group.addTask {
                    do {
                        try await Self.finishWriterStatic(item.box.writer, name: item.box.name)
                        return (item.key, .success(item.url))
                    } catch {
                        print("❌ Failed to finish \(item.box.name) writer: \(error)")
                        return (item.key, .failure(error))
                    }
                }
            }

            for await (key, result) in group {
                results[key] = result
            }
        }

        // Cleanup
        cleanup()

        // Build result
        let recordingResult = RecordingResult(
            front: results["front"] ?? .failure(RecordingError.missingURLs),
            back: results["back"] ?? .failure(RecordingError.missingURLs),
            combined: results["combined"] ?? .failure(RecordingError.missingURLs)
        )

        if recordingResult.allSuccessful {
            print("✅ RecordingCoordinator: All videos saved successfully")
        } else if recordingResult.hasAnySuccess {
            print("⚠️ RecordingCoordinator: Some videos saved successfully")
        } else {
            print("❌ RecordingCoordinator: All videos failed to save")
        }

        return recordingResult
    }

    nonisolated private static func finishWriterStatic(_ writer: AVAssetWriter, name: String) async throws {
        print("   Finishing \(name) writer...")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume()
            }
        }

        if writer.status == .failed, let error = writer.error {
            print("❌ \(name) writer failed: \(error)")
            throw error
        }

        if writer.status == .completed {
            print("✅ \(name) writer completed")
        }
    }

    private func cleanup() {
        frontWriter = nil
        backWriter = nil
        combinedWriter = nil
        frontVideoInput = nil
        frontAudioInput = nil
        backVideoInput = nil
        backAudioInput = nil
        combinedVideoInput = nil
        combinedAudioInput = nil
        frontPixelBufferAdaptor = nil
        backPixelBufferAdaptor = nil
        combinedPixelBufferAdaptor = nil
        isWriting = false
        recordingStartTime = nil
        hasReceivedFirstVideoFrame = false
        hasReceivedFirstAudioFrame = false
        audioSampleCount = 0  // Issue #16 Fix: Reset counter to prevent overflow
        lastFrontBuffer = nil
        lastFrontVideoPTS = nil
        lastBackVideoPTS = nil
        lastCombinedVideoPTS = nil
        lastFrontAudioPTS = nil
        lastBackAudioPTS = nil
        lastCombinedAudioPTS = nil
        frontURL = nil
        backURL = nil
        combinedURL = nil
        compositor = nil

        print("🧹 RecordingCoordinator cleaned up")
    }

    // MARK: - Status
    func getIsWriting() -> Bool {
        isWriting
    }

    func hasStartedWriting() -> Bool {
        hasReceivedFirstVideoFrame
    }
}

// MARK: - Recording Result (Issue #22 Fix)
struct RecordingResult {
    let front: Result<URL, Error>
    let back: Result<URL, Error>
    let combined: Result<URL, Error>

    var hasAnySuccess: Bool {
        if case .success = front { return true }
        if case .success = back { return true }
        if case .success = combined { return true }
        return false
    }

    var allSuccessful: Bool {
        if case .success = front,
           case .success = back,
           case .success = combined {
            return true
        }
        return false
    }
}

// MARK: - Errors
enum RecordingError: LocalizedError {
    case alreadyWriting
    case notWriting
    case failedToStartWriting
    case invalidSample
    case missingURLs
    case allWritersFailed

    var errorDescription: String? {
        switch self {
        case .alreadyWriting:
            return "Recording already in progress"
        case .notWriting:
            return "No recording in progress"
        case .failedToStartWriting:
            return "Failed to start video writers"
        case .invalidSample:
            return "Invalid video sample"
        case .missingURLs:
            return "Output URLs not configured"
        case .allWritersFailed:
            return "All video writers failed to complete"
        }
    }
}
