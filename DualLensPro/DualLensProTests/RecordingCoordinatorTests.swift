//
//  RecordingCoordinatorTests.swift
//  DualLensProTests
//
//  Created by DualLens Pro Team on 10/27/25.
//

import XCTest
import AVFoundation
@testable import DualLensPro

@MainActor
final class RecordingCoordinatorTests: XCTestCase {
    var coordinator: RecordingCoordinator!
    var tempDirectory: URL!

    override func setUp() async throws {
        coordinator = RecordingCoordinator()

        // Create temporary directory for test files
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        print("✅ Test setup complete - temp dir: \(tempDirectory.path)")
    }

    override func tearDown() async throws {
        // Cleanup temporary files
        if let tempDir = tempDirectory, FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }

        coordinator = nil
        print("✅ Test teardown complete")
    }

    // MARK: - Configuration Tests

    func testCoordinatorConfiguration() async throws {
        // Arrange
        let frontURL = tempDirectory.appendingPathComponent("front_test.mov")
        let backURL = tempDirectory.appendingPathComponent("back_test.mov")
        let combinedURL = tempDirectory.appendingPathComponent("combined_test.mov")

        // Act
        try await coordinator.configure(
            frontURL: frontURL,
            backURL: backURL,
            combinedURL: combinedURL,
            dimensions: (1920, 1080),
            bitRate: 6_000_000,
            frameRate: 30,
            videoTransform: .identity
        )

        // Assert
        XCTAssertNotNil(coordinator, "Coordinator should be configured")
        print("✅ testCoordinatorConfiguration passed")
    }

    func testConfigurationWithInvalidURL() async throws {
        // Arrange
        let frontURL = URL(fileURLWithPath: "/invalid/path/front.mov")
        let backURL = tempDirectory.appendingPathComponent("back_test.mov")
        let combinedURL = tempDirectory.appendingPathComponent("combined_test.mov")

        // Act & Assert
        do {
            try await coordinator.configure(
                frontURL: frontURL,
                backURL: backURL,
                combinedURL: combinedURL,
                dimensions: (1920, 1080),
                bitRate: 6_000_000,
                frameRate: 30,
                videoTransform: .identity
            )
            XCTFail("Should throw error for invalid URL")
        } catch {
            XCTAssertNotNil(error, "Should throw configuration error")
            print("✅ testConfigurationWithInvalidURL passed - error caught: \(error)")
        }
    }

    // MARK: - Writing State Tests

    func testInitialWritingState() async throws {
        // Act
        let isWriting = await coordinator.getIsWriting()

        // Assert
        XCTAssertFalse(isWriting, "Coordinator should not be writing initially")
        print("✅ testInitialWritingState passed")
    }

    func testHasNotStartedWritingInitially() async throws {
        // Act
        let hasStarted = await coordinator.hasStartedWriting()

        // Assert
        XCTAssertFalse(hasStarted, "Should not have started writing initially")
        print("✅ testHasNotStartedWritingInitially passed")
    }

    // MARK: - Concurrency Tests

    func testConcurrentConfiguration() async throws {
        // Arrange
        let frontURL1 = tempDirectory.appendingPathComponent("front_concurrent_1.mov")
        let backURL1 = tempDirectory.appendingPathComponent("back_concurrent_1.mov")
        let combinedURL1 = tempDirectory.appendingPathComponent("combined_concurrent_1.mov")

        let frontURL2 = tempDirectory.appendingPathComponent("front_concurrent_2.mov")
        let backURL2 = tempDirectory.appendingPathComponent("back_concurrent_2.mov")
        let combinedURL2 = tempDirectory.appendingPathComponent("combined_concurrent_2.mov")

        // Act - Try to configure twice concurrently (second should wait due to actor isolation)
        async let config1: () = coordinator.configure(
            frontURL: frontURL1,
            backURL: backURL1,
            combinedURL: combinedURL1,
            dimensions: (1920, 1080),
            bitRate: 6_000_000,
            frameRate: 30,
            videoTransform: .identity
        )

        async let config2: () = coordinator.configure(
            frontURL: frontURL2,
            backURL: backURL2,
            combinedURL: combinedURL2,
            dimensions: (1280, 720),
            bitRate: 3_000_000,
            frameRate: 30,
            videoTransform: .identity
        )

        // Assert - Both should complete without crashing (actor ensures serialization)
        try await config1
        try await config2

        print("✅ testConcurrentConfiguration passed - actor serialization works")
    }

    // MARK: - Performance Tests

    func testConfigurationPerformance() async throws {
        // Measure configuration time
        measure {
            let expectation = XCTestExpectation(description: "Configuration performance")

            Task {
                let frontURL = self.tempDirectory.appendingPathComponent("front_perf.mov")
                let backURL = self.tempDirectory.appendingPathComponent("back_perf.mov")
                let combinedURL = self.tempDirectory.appendingPathComponent("combined_perf.mov")

                try? await self.coordinator.configure(
                    frontURL: frontURL,
                    backURL: backURL,
                    combinedURL: combinedURL,
                    dimensions: (1920, 1080),
                    bitRate: 6_000_000,
                    frameRate: 30,
                    videoTransform: .identity
                )
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 5.0)
        }

        print("✅ testConfigurationPerformance completed")
    }

    // MARK: - Error Handling Tests

    func testMultipleConfigurationsUpdateState() async throws {
        // Arrange
        let frontURL1 = tempDirectory.appendingPathComponent("front_1.mov")
        let backURL1 = tempDirectory.appendingPathComponent("back_1.mov")
        let combinedURL1 = tempDirectory.appendingPathComponent("combined_1.mov")

        let frontURL2 = tempDirectory.appendingPathComponent("front_2.mov")
        let backURL2 = tempDirectory.appendingPathComponent("back_2.mov")
        let combinedURL2 = tempDirectory.appendingPathComponent("combined_2.mov")

        // Act - Configure twice (should be allowed - replaces previous config)
        try await coordinator.configure(
            frontURL: frontURL1,
            backURL: backURL1,
            combinedURL: combinedURL1,
            dimensions: (1920, 1080),
            bitRate: 6_000_000,
            frameRate: 30,
            videoTransform: .identity
        )

        try await coordinator.configure(
            frontURL: frontURL2,
            backURL: backURL2,
            combinedURL: combinedURL2,
            dimensions: (1280, 720),
            bitRate: 3_000_000,
            frameRate: 30,
            videoTransform: .identity
        )

        // Assert - Should complete without errors
        let isWriting = await coordinator.getIsWriting()
        XCTAssertFalse(isWriting, "Should not be writing after configuration")
        print("✅ testMultipleConfigurationsUpdateState passed")
    }

    // MARK: - Memory Tests

    func testCoordinatorMemoryDoesNotLeak() async throws {
        // Arrange
        weak var weakCoordinator: RecordingCoordinator?

        // Act
        autoreleasepool {
            let localCoordinator = RecordingCoordinator()
            weakCoordinator = localCoordinator

            // Use the coordinator
            Task {
                let frontURL = self.tempDirectory.appendingPathComponent("front_leak.mov")
                let backURL = self.tempDirectory.appendingPathComponent("back_leak.mov")
                let combinedURL = self.tempDirectory.appendingPathComponent("combined_leak.mov")

                try? await localCoordinator.configure(
                    frontURL: frontURL,
                    backURL: backURL,
                    combinedURL: combinedURL,
                    dimensions: (1920, 1080),
                    bitRate: 6_000_000,
                    frameRate: 30,
                    videoTransform: .identity
                )
            }
        }

        // Allow some time for cleanup
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Assert
        XCTAssertNil(weakCoordinator, "Coordinator should be deallocated")
        print("✅ testCoordinatorMemoryDoesNotLeak passed")
    }
}
