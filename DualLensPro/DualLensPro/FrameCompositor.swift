//
//  FrameCompositor.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/26/25.
//  Real-time video frame compositor for stacked dual-camera output
//

import CoreImage
import CoreVideo
import AVFoundation
import Metal
import os.lock
import UIKit

/// Real-time compositor for creating stacked dual-camera frames
/// Uses Core Image for GPU-accelerated composition
/// Thread-safe using OSAllocatedUnfairLock
final class FrameCompositor: Sendable {
    private let context: CIContext
    private let width: Int
    private let height: Int

    // ✅ Device orientation tracking
    private let deviceOrientation: UIDeviceOrientation
    private let isPortrait: Bool

    // Thread-safe state - CVPixelBufferPool is thread-safe but not Sendable
    nonisolated(unsafe) private var pixelBufferPool: CVPixelBufferPool?
    private let poolLock = NSLock()

    // ✅ FIX: Shutdown state to prevent using stale buffers during recording stop
    private let stateLock = NSLock()
    nonisolated(unsafe) private var isShuttingDown = false
    nonisolated(unsafe) private var lastFrontBuffer: (buffer: CVPixelBuffer, time: CMTime)?

    init(width: Int, height: Int, deviceOrientation: UIDeviceOrientation) {
        self.width = width
        self.height = height
        self.deviceOrientation = deviceOrientation

        // Determine if we're in portrait mode
        self.isPortrait = (deviceOrientation == .portrait ||
                          deviceOrientation == .portraitUpsideDown ||
                          deviceOrientation == .unknown ||
                          deviceOrientation == .faceUp ||
                          deviceOrientation == .faceDown)

        // Use Metal for GPU acceleration
        let options: [CIContextOption: Any] = [
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .useSoftwareRenderer: false,
            .priorityRequestLow: true,
            .cacheIntermediates: false,
            .outputPremultiplied: true,
            .name: "DualLensPro.FrameCompositor"
        ]

        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.context = CIContext(mtlDevice: metalDevice, options: options)
            print("✅ FrameCompositor using Metal device: \(metalDevice.name)")
        } else {
            self.context = CIContext(options: options)
            print("⚠️ FrameCompositor using software rendering")
        }

        print("✅ FrameCompositor initialized: \(width)x\(height), orientation: \(deviceOrientation.rawValue), isPortrait: \(isPortrait)")

        // Create pixel buffer pool for efficient buffer reuse
        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 3
        ]

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            pixelBufferAttributes as CFDictionary,
            &pool
        )

        if status == kCVReturnSuccess {
            poolLock.lock()
            pixelBufferPool = pool
            poolLock.unlock()
            print("✅ FrameCompositor: Pixel buffer pool created")
        } else {
            print("⚠️ FrameCompositor: Failed to create pixel buffer pool (status: \(status))")
        }

        print("✅ FrameCompositor initialized (thread-safe with NSLock): \(width)x\(height)")
    }

    // MARK: - Lifecycle Methods

    /// ✅ FIX: Reset compositor state before starting new recording
    /// Clears any cached buffers from previous recording
    func beginRecording() {
        stateLock.lock()
        defer { stateLock.unlock() }

        isShuttingDown = false
        lastFrontBuffer = nil
        print("▶️ FrameCompositor ready for new recording")
    }

    /// ✅ FIX: Clear compositor cache and enter shutdown mode
    /// Prevents using stale cached buffers during recording finalization
    func reset() {
        stateLock.lock()
        defer { stateLock.unlock() }

        isShuttingDown = true
        lastFrontBuffer = nil
        print("🧹 FrameCompositor cache cleared and shutdown mode enabled")
    }

    /// ✅ FIX: Flush GPU render pipeline to ensure all pending renders complete
    /// Forces synchronization of Metal/GPU operations before finalizing video
    func flushGPU() {
        // Force GPU synchronization by rendering empty image
        // This ensures all pending Metal commands complete
        let emptyImage = CIImage.empty()
        if let tempBuffer = allocatePixelBuffer() {
            context.render(emptyImage, to: tempBuffer)
        }
        print("🎨 GPU render pipeline flushed")
    }

    deinit {
        // Clean up pool
        poolLock.lock()
        if let pool = pixelBufferPool {
            CVPixelBufferPoolFlush(pool, [])
        }
        pixelBufferPool = nil
        poolLock.unlock()
        print("🗑️ FrameCompositor deallocated")
    }
    
    /// Create a stacked composition with front camera on top, back camera on bottom
    /// - Parameters:
    ///   - front: Front camera pixel buffer (optional)
    ///   - back: Back camera pixel buffer (optional)
    /// - Returns: Composed pixel buffer, or nil if composition fails
    /// Thread-safe: CIContext operations are serialized by the compositor
    func stacked(front: CVPixelBuffer?, back: CVPixelBuffer?) -> CVPixelBuffer? {
        stateLock.lock()
        let shuttingDown = isShuttingDown
        stateLock.unlock()

        // ✅ FIX: During shutdown, require both buffers - don't use cached or fallback buffers
        if shuttingDown {
            guard let f = front, let b = back else {
                // Drop incomplete frames during shutdown to prevent frozen frames
                return nil
            }
            return stackedBuffers(front: f, back: b)
        }

        // Normal operation - cache front buffer for smoother compositing
        stateLock.lock()
        if let front = front {
            lastFrontBuffer = (buffer: front, time: CMTime.zero)
        }
        let cachedFront = lastFrontBuffer?.buffer
        stateLock.unlock()

        // Use cached buffer as fallback
        let frontBuffer = front ?? cachedFront
        let backBuffer = back

        // Need at least one buffer
        guard let primaryBuffer = backBuffer ?? frontBuffer else {
            print("⚠️ FrameCompositor: No buffers provided")
            return nil
        }

        // If only one buffer, use it for both halves
        let finalFront = frontBuffer ?? primaryBuffer
        let finalBack = backBuffer ?? primaryBuffer

        return stackedBuffers(front: finalFront, back: finalBack)
    }

    /// Internal method to compose two buffers into stacked output
    private func stackedBuffers(front: CVPixelBuffer, back: CVPixelBuffer) -> CVPixelBuffer? {
        guard let outputBuffer = allocatePixelBuffer() else {
            print("❌ FrameCompositor: Failed to allocate output buffer")
            return nil
        }

        let frontImage = CIImage(cvPixelBuffer: front)
        let backImage = CIImage(cvPixelBuffer: back)

        let outputWidth = CGFloat(width)
        let outputHeight = CGFloat(height)
        let halfHeight = outputHeight / 2

        // Scale both images to fill their half of the screen
        let frontScaled = scaleToFit(image: frontImage, width: outputWidth, height: halfHeight)
        let backScaled = scaleToFit(image: backImage, width: outputWidth, height: halfHeight)

        // Position back camera on top, front camera on bottom
        let backPositioned = backScaled.transformed(by: CGAffineTransform(translationX: 0, y: halfHeight))
        let frontPositioned = frontScaled

        // Create a solid black background to render onto
        let outputRect = CGRect(x: 0, y: 0, width: width, height: height)
        let background = CIImage(color: .black).cropped(to: outputRect)

        // Composite the frames over the black background
        let composed = frontPositioned
            .composited(over: backPositioned)
            .composited(over: background)

        context.render(composed, to: outputBuffer, bounds: outputRect, colorSpace: CGColorSpaceCreateDeviceRGB())

        return outputBuffer
    }
    
    /// Create a picture-in-picture composition with back camera full-screen and front camera in corner
    /// - Parameters:
    ///   - front: Front camera pixel buffer (optional)
    ///   - back: Back camera pixel buffer (optional)
    ///   - pipSize: Size ratio for PiP (0.0-1.0, default 0.25 = 25% of screen)
    ///   - position: Corner position (default: top-right)
    /// - Returns: Composed pixel buffer, or nil if composition fails
    func pictureInPicture(
        front: CVPixelBuffer?,
        back: CVPixelBuffer?,
        pipSize: CGFloat = 0.25,
        position: PiPPosition = .topRight
    ) -> CVPixelBuffer? {
        // Need at least one buffer
        guard let primaryBuffer = back ?? front else {
            print("⚠️ FrameCompositor: No buffers provided")
            return nil
        }
        
        // If only one buffer, use it for both
        let frontBuffer = front ?? primaryBuffer
        let backBuffer = back ?? primaryBuffer
        
        // Create output buffer from pool
        guard let outputBuffer = allocatePixelBuffer() else {
            print("❌ FrameCompositor: Failed to allocate output buffer")
            return nil
        }
        
        // Create CIImages from pixel buffers
        let frontImage = CIImage(cvPixelBuffer: frontBuffer)
        let backImage = CIImage(cvPixelBuffer: backBuffer)
        
        // Calculate dimensions
        let outputWidth = CGFloat(width)
        let outputHeight = CGFloat(height)
        let pipWidth = outputWidth * pipSize
        let pipHeight = outputHeight * pipSize
        let padding: CGFloat = 20
        
        // Scale back to full screen
        let backScaled = scaleToFit(image: backImage, width: outputWidth, height: outputHeight)
        
        // Scale front to PiP size
        let frontScaled = scaleToFit(image: frontImage, width: pipWidth, height: pipHeight)
        
        // Position PiP based on corner
        let pipTransform: CGAffineTransform
        switch position {
        case .topLeft:
            pipTransform = CGAffineTransform(translationX: padding, y: outputHeight - pipHeight - padding)
        case .topRight:
            pipTransform = CGAffineTransform(translationX: outputWidth - pipWidth - padding, y: outputHeight - pipHeight - padding)
        case .bottomLeft:
            pipTransform = CGAffineTransform(translationX: padding, y: padding)
        case .bottomRight:
            pipTransform = CGAffineTransform(translationX: outputWidth - pipWidth - padding, y: padding)
        }
        
        let frontPositioned = frontScaled.transformed(by: pipTransform)
        
        // Composite: front over back
        let composed = frontPositioned.composited(over: backScaled)
        
        // Render to output buffer
        context.render(composed, to: outputBuffer)
        
        return outputBuffer
    }
    
    // MARK: - Private Helpers
    
    private func allocatePixelBuffer() -> CVPixelBuffer? {
        // Try to get buffer from pool (thread-safe)
        poolLock.lock()
        defer { poolLock.unlock() }

        if let pool = pixelBufferPool {
            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
            if status == kCVReturnSuccess {
                return pixelBuffer
            } else {
                print("⚠️ FrameCompositor: Failed to create buffer from pool (status: \(status))")
            }
        }
        
        // Fallback: create buffer directly
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            pixelBufferAttributes as CFDictionary,
            &pixelBuffer
        )
        
        if status == kCVReturnSuccess {
            return pixelBuffer
        } else {
            print("❌ FrameCompositor: Failed to create pixel buffer (status: \(status))")
            return nil
        }
    }

    private func scaleToFit(image: CIImage, width: CGFloat, height: CGFloat) -> CIImage {
        let imageSize = image.extent.size
        let scaleX = width / imageSize.width
        let scaleY = height / imageSize.height

        // ✅ Use max to fill the entire space (aspect fill), not min (aspect fit)
        let scale = max(scaleX, scaleY)

        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Center the image and crop to fit
        let scaledSize = scaledImage.extent.size
        let offsetX = (width - scaledSize.width) / 2
        let offsetY = (height - scaledSize.height) / 2

        // Translate to center
        let centeredImage = scaledImage.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))

        // Crop to exact dimensions
        let cropRect = CGRect(x: 0, y: 0, width: width, height: height)
        return centeredImage.cropped(to: cropRect)
    }

    /// ✅ Apply proper orientation to camera images
    /// Rotates landscape buffers to portrait and mirrors front camera
    private func orientImage(_ image: CIImage, isFrontCamera: Bool) -> CIImage {
        var oriented = image

        // Step 1: Rotate based on device orientation
        // Camera buffers are always landscape (1920x1080), we need to rotate for portrait
        if isPortrait {
            // Rotate 90° clockwise to convert landscape → portrait
            oriented = oriented.oriented(.right)
        }

        // Step 2: Mirror front camera horizontally (selfie mirror effect)
        if isFrontCamera {
            // Mirror horizontally by flipping X axis
            let transform = CGAffineTransform(scaleX: -1, y: 1)
                .translatedBy(x: -oriented.extent.width, y: 0)
            oriented = oriented.transformed(by: transform)
        }

        return oriented
    }
}

// MARK: - PiP Position

enum PiPPosition {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

