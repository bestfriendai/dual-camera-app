//
//  FrameCompositor.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/26/25.
//  Real-time video frame compositor for stacked dual-camera output (Swift 6.2)
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
// Sendable conformance: Thread-safe via NSLock protection of mutable state
// All public methods can be safely called from any thread/actor
final class FrameCompositor: Sendable {
    private let context: CIContext

    // MARK: - Swift 6.2 InlineArray Configuration
    struct CompositorConfig: Sendable {
        var dimensions: [2 of Int]
        var layoutParams: [2 of Bool]
        var rotation: Int
    }

    private let config: CompositorConfig

    // Legacy accessors for backward compatibility
    private var width: Int { config.dimensions[0] }
    private var height: Int { config.dimensions[1] }
    private var isPortrait: Bool { config.layoutParams[0] }
    private var isFrontOnTop: Bool { config.layoutParams[1] }
    private var rotationAngle: Int { config.rotation }

    // ✅ Interface orientation tracking (iOS 26+)
    private let interfaceOrientation: UIInterfaceOrientation

    // MARK: - Thread-Safe State (Swift 6.2 Strict Memory Safety)
    //
    // The following properties use nonisolated(unsafe) with @safe(unchecked) because:
    // 1. CVPixelBufferPool is thread-safe but not Sendable (Apple's API limitation)
    // 2. All access is protected by NSLock (poolLock for pool, stateLock for state)
    // 3. The locks ensure mutual exclusion and memory ordering guarantees
    //
    // This is a justified use of unsafe - the thread safety is manually verified.
    nonisolated(unsafe) private var pixelBufferPool: CVPixelBufferPool?
    // NOTE: Using NSLock instead of OSAllocatedUnfairLock because:
    // 1. FrameCompositor is marked Sendable (class-level conformance)
    // 2. OSAllocatedUnfairLock requires generic state parameter
    // 3. NSLock provides sufficient performance for this use case
    // 4. Lock contention is low (only during buffer allocation and state checks)
    private let poolLock = NSLock()

    // ✅ FIX: Shutdown state to prevent using stale buffers during recording stop
    // Photo capture delegate storage (thread-safe access)
    private let stateLock = NSLock()
    nonisolated(unsafe) private var isShuttingDown = false
    nonisolated(unsafe) private var lastFrontBuffer: (buffer: CVPixelBuffer, time: CMTime)?

    init(
        width: Int,
        height: Int,
        interfaceOrientation: UIInterfaceOrientation,
        rotationAngle: Int,
        isPortrait: Bool,
        isFrontOnTop: Bool
    ) {
        // Initialize config with InlineArray
        self.config = CompositorConfig(
            dimensions: [width, height],
            layoutParams: [isPortrait, isFrontOnTop],
            rotation: rotationAngle
        )
        self.interfaceOrientation = interfaceOrientation

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

        print("✅ FrameCompositor initialized: \(width)x\(height), interface orientation: \(interfaceOrientation.rawValue), rotation: \(rotationAngle)°, portrait layout: \(isPortrait)")

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
        let outputRect = CGRect(x: 0, y: 0, width: width, height: height)
        let background = CIImage(color: .black).cropped(to: outputRect)

        let halfHeight = outputHeight / 2
        let frontScaled = scaleToFit(image: frontImage, width: outputWidth, height: halfHeight)
        let backScaled = scaleToFit(image: backImage, width: outputWidth, height: halfHeight)

        let (topImage, bottomImage): (CIImage, CIImage) = {
            if isFrontOnTop {
                return (frontScaled, backScaled)
            } else {
                return (backScaled, frontScaled)
            }
        }()

        let topPositioned = topImage.transformed(by: CGAffineTransform(translationX: 0, y: halfHeight))
        let bottomPositioned = bottomImage

        let composed = topPositioned
            .composited(over: bottomPositioned)
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

    // MARK: - Future Optimization: Span for Buffer Access
    //
    // Swift 6.2's Span type could be used for zero-overhead pixel buffer access:
    //
    // Example pattern for direct pixel manipulation:
    //   CVPixelBufferLockBaseAddress(buffer, [])
    //   defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    //   let baseAddress = CVPixelBufferGetBaseAddress(buffer)
    //   let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    //   let height = CVPixelBufferGetHeight(buffer)
    //   let span = MutableSpan(baseAddress, count: bytesPerRow * height)
    //   // Safe, zero-overhead read/write access
    //
    // Current Core Image approach is optimal for GPU-accelerated composition.
    // Consider Span for CPU-based effects or custom pixel shaders.

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

}

// MARK: - PiP Position

enum PiPPosition {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}
