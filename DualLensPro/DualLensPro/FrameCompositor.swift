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

/// Real-time compositor for creating stacked dual-camera frames
/// Uses Core Image for GPU-accelerated composition
final class FrameCompositor {
    private let context: CIContext
    private let width: Int
    private let height: Int
    private var pixelBufferPool: CVPixelBufferPool?
    
    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        
        // Create Core Image context with low priority for background processing
        self.context = CIContext(options: [
            .priorityRequestLow: true,
            .cacheIntermediates: false
        ])
        
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
            self.pixelBufferPool = pool
            print("✅ FrameCompositor: Pixel buffer pool created")
        } else {
            print("⚠️ FrameCompositor: Failed to create pixel buffer pool (status: \(status))")
        }
        
        print("✅ FrameCompositor initialized: \(width)x\(height)")
    }
    
    /// Create a stacked composition with front camera on top, back camera on bottom
    /// - Parameters:
    ///   - front: Front camera pixel buffer (optional)
    ///   - back: Back camera pixel buffer (optional)
    /// - Returns: Composed pixel buffer, or nil if composition fails
    func stacked(front: CVPixelBuffer?, back: CVPixelBuffer?) -> CVPixelBuffer? {
        // Need at least one buffer
        guard let primaryBuffer = back ?? front else {
            print("⚠️ FrameCompositor: No buffers provided")
            return nil
        }
        
        // If only one buffer, use it for both halves
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
        
        // Calculate dimensions for stacking
        let outputWidth = CGFloat(width)
        let outputHeight = CGFloat(height)
        let halfHeight = outputHeight / 2
        
        // Scale images to fit half-height
        let frontScaled = scaleToFit(image: frontImage, width: outputWidth, height: halfHeight)
        let backScaled = scaleToFit(image: backImage, width: outputWidth, height: halfHeight)
        
        // Position front on top, back on bottom
        let frontPositioned = frontScaled.transformed(by: CGAffineTransform(translationX: 0, y: halfHeight))
        let backPositioned = backScaled
        
        // Composite: front over back
        let composed = frontPositioned.composited(over: backPositioned)
        
        // Render to output buffer
        context.render(composed, to: outputBuffer)
        
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
        let scale = min(scaleX, scaleY)
        
        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        // Center the image
        let scaledSize = scaledImage.extent.size
        let offsetX = (width - scaledSize.width) / 2
        let offsetY = (height - scaledSize.height) / 2
        
        return scaledImage.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
    }
}

// MARK: - PiP Position

enum PiPPosition {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

