//
//  HapticManager.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import UIKit

/// Centralized haptic feedback manager for consistent tactile responses
@MainActor
class HapticManager {
    // MARK: - Singleton
    static let shared = HapticManager()

    // MARK: - Properties
    private var isEnabled: Bool {
        // Default to true if not set
        UserDefaults.standard.object(forKey: "settings.hapticFeedback") as? Bool ?? true
    }

    // MARK: - Generators (lazy to avoid initialization issues)
    private lazy var lightImpactGenerator: UIImpactFeedbackGenerator = {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        return generator
    }()

    private lazy var mediumImpactGenerator: UIImpactFeedbackGenerator = {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        return generator
    }()

    private lazy var heavyImpactGenerator: UIImpactFeedbackGenerator = {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        return generator
    }()

    private lazy var selectionGenerator: UISelectionFeedbackGenerator = {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        return generator
    }()

    private lazy var notificationGenerator: UINotificationFeedbackGenerator = {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        return generator
    }()

    // MARK: - Initialization
    private init() {
        // Empty init - generators are lazy loaded
    }

    // MARK: - Public Methods

    /// Light impact - for button taps, UI interactions
    func light() {
        guard isEnabled else { return }
        lightImpactGenerator.impactOccurred()
        lightImpactGenerator.prepare()
    }

    /// Medium impact - for recording start/stop, photo capture
    func medium() {
        guard isEnabled else { return }
        mediumImpactGenerator.impactOccurred()
        mediumImpactGenerator.prepare()
    }

    /// Heavy impact - for important actions, errors
    func heavy() {
        guard isEnabled else { return }
        heavyImpactGenerator.impactOccurred()
        heavyImpactGenerator.prepare()
    }

    /// Selection feedback - for mode switching, zoom changes
    func selection() {
        guard isEnabled else { return }
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    /// Success notification - for successful saves, completions
    func success() {
        guard isEnabled else { return }
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()
    }

    /// Warning notification - for time warnings, alerts
    func warning() {
        guard isEnabled else { return }
        notificationGenerator.notificationOccurred(.warning)
        notificationGenerator.prepare()
    }

    /// Error notification - for errors, failures
    func error() {
        guard isEnabled else { return }
        notificationGenerator.notificationOccurred(.error)
        notificationGenerator.prepare()
    }

    // MARK: - Specialized Haptics

    /// Haptic for recording start
    func recordingStart() {
        guard isEnabled else { return }
        mediumImpactGenerator.impactOccurred()
        mediumImpactGenerator.prepare()
    }

    /// Haptic for recording stop
    func recordingStop() {
        guard isEnabled else { return }
        mediumImpactGenerator.impactOccurred()
        mediumImpactGenerator.prepare()
    }

    /// Haptic for photo capture
    func photoCapture() {
        guard isEnabled else { return }
        mediumImpactGenerator.impactOccurred()
        mediumImpactGenerator.prepare()
    }

    /// Haptic for timer countdown tick
    func timerTick() {
        guard isEnabled else { return }
        lightImpactGenerator.impactOccurred()
        lightImpactGenerator.prepare()
    }

    /// Haptic for timer final countdown
    func timerFinal() {
        guard isEnabled else { return }
        heavyImpactGenerator.impactOccurred()
        heavyImpactGenerator.prepare()
    }

    /// Haptic for mode change
    func modeChange() {
        guard isEnabled else { return }
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    /// Haptic for zoom change
    func zoomChange() {
        guard isEnabled else { return }
        lightImpactGenerator.impactOccurred()
        lightImpactGenerator.prepare()
    }

    /// Haptic for premium feature locked
    func premiumLocked() {
        guard isEnabled else { return }
        notificationGenerator.notificationOccurred(.warning)
        notificationGenerator.prepare()
    }

    /// Haptic for time limit warning
    func timeLimitWarning() {
        guard isEnabled else { return }
        notificationGenerator.notificationOccurred(.warning)
        notificationGenerator.prepare()
    }

    /// Haptic for time limit reached
    func timeLimitReached() {
        guard isEnabled else { return }
        // Double haptic for emphasis
        let generator = notificationGenerator  // Capture generator, not self
        generator.notificationOccurred(.error)
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            generator.notificationOccurred(.error)
            generator.prepare()
        }
    }
}
