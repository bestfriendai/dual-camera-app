//
//  RecordingService.swift
//  DualCam Pro
//
//  Triple output recording service with Metal compositing
//

import AVFoundation
import CoreImage
import UIKit
import os.log

private let logger = Logger(subsystem: "com.dualcamera.app", category: "RecordingService")

final class RecordingService {
    // MARK: - Properties

    private var dualViewWriter: AVAssetWriter?
    private var frontWriter: AVAssetWriter?
    private var backWriter: AVAssetWriter?

    private var dualViewVideoInput: AVAssetWriterInput?
    private var frontVideoInput: AVAssetWriterInput?
    private var backVideoInput: AVAssetWriterInput?

    private var dualViewAudioInput: AVAssetWriterInput?
    private var frontAudioInput: AVAssetWriterInput?
    private var backAudioInput: AVAssetWriterInput?

    private(set) var isRecording = false
    private(set) var isPaused = false
    private(set) var recordingDuration: TimeInterval = 0

    private var startTime: CMTime?
    private var pauseTime: CMTime?
    private var resumeTime: CMTime?
    private var totalPausedDuration: CMTime = .zero

    private var frontFrameBuffer: CMSampleBuffer?
    private var backFrameBuffer: CMSampleBuffer?

    private let ciContext = CIContext()

    // File URLs
    private var dualViewURL: URL?
    private var frontURL: URL?
    private var backURL: URL?
    
    // MARK: - Recording Control
    
    func startRecording(settings: CameraSettings) async throws -> (dualView: URL, front: URL, back: URL) {
        logger.info("Starting triple recording")
        
        // Generate file URLs
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        let dualURL = documentsPath.appendingPathComponent("dualview_\(timestamp).mov")
        let frontURL = documentsPath.appendingPathComponent("front_\(timestamp).mov")
        let backURL = documentsPath.appendingPathComponent("back_\(timestamp).mov")
        
        self.dualViewURL = dualURL
        self.frontURL = frontURL
        self.backURL = backURL
        
        // Create asset writers
        try await createWriters(
            dualViewURL: dualURL,
            frontURL: frontURL,
            backURL: backURL,
            settings: settings
        )
        
        // Start writing
        guard let dualViewWriter = dualViewWriter,
              let frontWriter = frontWriter,
              let backWriter = backWriter else {
            throw RecordingError.writerFailed(NSError(domain: "RecordingService", code: -1))
        }
        
        dualViewWriter.startWriting()
        frontWriter.startWriting()
        backWriter.startWriting()
        
        isRecording = true
        isPaused = false
        recordingDuration = 0
        startTime = nil
        totalPausedDuration = .zero
        
        logger.info("Triple recording started")
        
        return (dualURL, frontURL, backURL)
    }
    
    private func createWriters(
        dualViewURL: URL,
        frontURL: URL,
        backURL: URL,
        settings: CameraSettings
    ) async throws {
        let resolution = settings.resolution.dimensions
        let codec = settings.codec.avCodec
        let bitRate = settings.bitRate.value(for: settings.resolution)
        
        // Video settings
        var videoSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: resolution.width,
            AVVideoHeightKey: resolution.height
        ]
        
        if bitRate > 0 {
            videoSettings[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        }
        
        // Audio settings
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 256000
        ]
        
        // Dual view writer
        let dualWriter = try AVAssetWriter(url: dualViewURL, fileType: .mov)
        let dualVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        dualVideoInput.expectsMediaDataInRealTime = true
        
        let dualAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        dualAudioInput.expectsMediaDataInRealTime = true
        
        if dualWriter.canAdd(dualVideoInput) {
            dualWriter.add(dualVideoInput)
        }
        if dualWriter.canAdd(dualAudioInput) {
            dualWriter.add(dualAudioInput)
        }
        
        self.dualViewWriter = dualWriter
        self.dualViewVideoInput = dualVideoInput
        self.dualViewAudioInput = dualAudioInput
        
        // Front writer
        let frontWriter = try AVAssetWriter(url: frontURL, fileType: .mov)
        let frontVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        frontVideoInput.expectsMediaDataInRealTime = true
        
        let frontAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        frontAudioInput.expectsMediaDataInRealTime = true
        
        if frontWriter.canAdd(frontVideoInput) {
            frontWriter.add(frontVideoInput)
        }
        if frontWriter.canAdd(frontAudioInput) {
            frontWriter.add(frontAudioInput)
        }
        
        self.frontWriter = frontWriter
        self.frontVideoInput = frontVideoInput
        self.frontAudioInput = frontAudioInput
        
        // Back writer
        let backWriter = try AVAssetWriter(url: backURL, fileType: .mov)
        let backVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        backVideoInput.expectsMediaDataInRealTime = true
        
        let backAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        backAudioInput.expectsMediaDataInRealTime = true
        
        if backWriter.canAdd(backVideoInput) {
            backWriter.add(backVideoInput)
        }
        if backWriter.canAdd(backAudioInput) {
            backWriter.add(backAudioInput)
        }
        
        self.backWriter = backWriter
        self.backVideoInput = backVideoInput
        self.backAudioInput = backAudioInput
        
        logger.info("Created three asset writers")
    }
    
    func pauseRecording() async {
        guard isRecording && !isPaused else { return }
        
        pauseTime = CMClockGetTime(CMClockGetHostTimeClock())
        isPaused = true
        
        logger.info("Recording paused")
    }
    
    func resumeRecording() async {
        guard isRecording && isPaused else { return }
        
        if let pauseTime = pauseTime {
            let currentTime = CMClockGetTime(CMClockGetHostTimeClock())
            let pauseDuration = CMTimeSubtract(currentTime, pauseTime)
            totalPausedDuration = CMTimeAdd(totalPausedDuration, pauseDuration)
        }
        
        isPaused = false
        self.pauseTime = nil
        
        logger.info("Recording resumed")
    }
    
    func stopRecording() async throws -> (dualView: URL, front: URL, back: URL)? {
        guard isRecording else { return nil }
        
        logger.info("Stopping recording")
        
        isRecording = false
        isPaused = false
        
        // Finish writing
        let dualInput = dualViewVideoInput
        let frontInput = frontVideoInput
        let backInput = backVideoInput
        
        dualInput?.markAsFinished()
        frontInput?.markAsFinished()
        backInput?.markAsFinished()
        
        dualViewAudioInput?.markAsFinished()
        frontAudioInput?.markAsFinished()
        backAudioInput?.markAsFinished()
        
        // Wait for writers to finish
        await dualViewWriter?.finishWriting()
        await frontWriter?.finishWriting()
        await backWriter?.finishWriting()
        
        let urls = (
            dualView: dualViewURL!,
            front: frontURL!,
            back: backURL!
        )
        
        // Clean up
        cleanup()
        
        logger.info("Recording stopped successfully")
        
        return urls
    }
    
    // MARK: - Sample Buffer Processing
    
    func processFrontSample(_ sampleBuffer: CMSampleBuffer) async {
        guard isRecording && !isPaused else { return }
        
        // Initialize start time
        if startTime == nil {
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            startTime = presentationTime
            
            dualViewWriter?.startSession(atSourceTime: presentationTime)
            frontWriter?.startSession(atSourceTime: presentationTime)
            backWriter?.startSession(atSourceTime: presentationTime)
        }
        
        // Write to front writer
        if let frontVideoInput = frontVideoInput,
           frontVideoInput.isReadyForMoreMediaData {
            frontVideoInput.append(sampleBuffer)
        }
        
        // Store for compositing
        frontFrameBuffer = sampleBuffer
        
        // Try to composite if we have both frames
        await tryComposite()
        
        // Update duration
        updateDuration(sampleBuffer)
    }
    
    func processBackSample(_ sampleBuffer: CMSampleBuffer) async {
        guard isRecording && !isPaused else { return }
        
        // Initialize start time
        if startTime == nil {
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            startTime = presentationTime
            
            dualViewWriter?.startSession(atSourceTime: presentationTime)
            frontWriter?.startSession(atSourceTime: presentationTime)
            backWriter?.startSession(atSourceTime: presentationTime)
        }
        
        // Write to back writer
        if let backVideoInput = backVideoInput,
           backVideoInput.isReadyForMoreMediaData {
            backVideoInput.append(sampleBuffer)
        }
        
        // Store for compositing
        backFrameBuffer = sampleBuffer
        
        // Try to composite if we have both frames
        await tryComposite()
        
        // Update duration
        updateDuration(sampleBuffer)
    }
    
    func processAudioSample(_ sampleBuffer: CMSampleBuffer) async {
        guard isRecording && !isPaused else { return }
        
        // Write audio to all three outputs
        if let dualAudioInput = dualViewAudioInput,
           dualAudioInput.isReadyForMoreMediaData {
            dualAudioInput.append(sampleBuffer)
        }
        
        if let frontAudioInput = frontAudioInput,
           frontAudioInput.isReadyForMoreMediaData {
            frontAudioInput.append(sampleBuffer)
        }
        
        if let backAudioInput = backAudioInput,
           backAudioInput.isReadyForMoreMediaData {
            backAudioInput.append(sampleBuffer)
        }
    }
    
    private func tryComposite() async {
        guard let frontBuffer = frontFrameBuffer,
              let backBuffer = backFrameBuffer else {
            return
        }
        
        // Composite the frames
        if let compositedBuffer = compositeFrames(front: frontBuffer, back: backBuffer) {
            if let dualVideoInput = dualViewVideoInput,
               dualVideoInput.isReadyForMoreMediaData {
                dualVideoInput.append(compositedBuffer)
            }
        }
        
        // Clear buffers
        frontFrameBuffer = nil
        backFrameBuffer = nil
    }
    
    private func compositeFrames(front: CMSampleBuffer, back: CMSampleBuffer) -> CMSampleBuffer? {
        guard let frontImageBuffer = CMSampleBufferGetImageBuffer(front),
              let backImageBuffer = CMSampleBufferGetImageBuffer(back) else {
            return nil
        }
        
        let frontImage = CIImage(cvPixelBuffer: frontImageBuffer)
        let backImage = CIImage(cvPixelBuffer: backImageBuffer)
        
        let width = CVPixelBufferGetWidth(frontImageBuffer)
        let height = CVPixelBufferGetHeight(frontImageBuffer)
        
        // Create stacked composition (front on top, back on bottom)
        let halfHeight = CGFloat(height) / 2.0
        
        // Transform front image to top half
        let frontTransformed = frontImage
            .transformed(by: CGAffineTransform(scaleX: 1.0, y: 0.5))
        
        // Transform back image to bottom half
        let backTransformed = backImage
            .transformed(by: CGAffineTransform(scaleX: 1.0, y: 0.5))
            .transformed(by: CGAffineTransform(translationX: 0, y: halfHeight))
        
        // Composite
        let composited = frontTransformed.composited(over: backTransformed)
        
        // Create pixel buffer
        var pixelBuffer: CVPixelBuffer?
        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            options as CFDictionary,
            &pixelBuffer
        )
        
        guard let outputBuffer = pixelBuffer else {
            return nil
        }
        
        ciContext.render(composited, to: outputBuffer)
        
        // Create sample buffer from pixel buffer
        var sampleBuffer: CMSampleBuffer?
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: outputBuffer,
            formatDescriptionOut: &formatDescription
        )
        
        guard let format = formatDescription else {
            return nil
        }
        
        var timingInfo = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(front),
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(front),
            decodeTimeStamp: CMSampleBufferGetDecodeTimeStamp(front)
        )
        
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: outputBuffer,
            formatDescription: format,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        
        return sampleBuffer
    }
    
    private func updateDuration(_ sampleBuffer: CMSampleBuffer) {
        guard let startTime = startTime else { return }
        
        let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let elapsed = CMTimeSubtract(currentTime, startTime)
        let adjustedElapsed = CMTimeSubtract(elapsed, totalPausedDuration)
        
        recordingDuration = CMTimeGetSeconds(adjustedElapsed)
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        dualViewWriter = nil
        frontWriter = nil
        backWriter = nil
        dualViewVideoInput = nil
        frontVideoInput = nil
        backVideoInput = nil
        dualViewAudioInput = nil
        frontAudioInput = nil
        backAudioInput = nil
        frontFrameBuffer = nil
        backFrameBuffer = nil
        startTime = nil
        pauseTime = nil
        resumeTime = nil
        totalPausedDuration = .zero
    }
    
    // MARK: - Recording Info
    
    func getRecordingInfo() -> (duration: TimeInterval, isRecording: Bool, isPaused: Bool) {
        return (recordingDuration, isRecording, isPaused)
    }
}
