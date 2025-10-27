//
//  AnalyticsService.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/27/25.
//  Analytics integration scaffold for Firebase Analytics
//

import Foundation

@MainActor
final class AnalyticsService: @unchecked Sendable {
    static let shared = AnalyticsService()

    private init() {
        print("📊 AnalyticsService initialized")
        // TODO: Initialize Firebase Analytics when ready
        // FirebaseApp.configure()
    }

    // MARK: - Camera Events

    func trackCameraSetupCompleted(multiCamSupported: Bool, duration: TimeInterval) {
        logEvent("camera_setup_completed", parameters: [
            "multi_cam_supported": multiCamSupported,
            "setup_duration_ms": Int(duration * 1000)
        ])
    }

    func trackRecordingStarted(mode: String, quality: String) {
        logEvent("recording_started", parameters: [
            "capture_mode": mode,
            "quality": quality,
            "device_model": deviceModel
        ])
    }

    func trackRecordingCompleted(duration: TimeInterval, mode: String, quality: String) {
        logEvent("recording_completed", parameters: [
            "duration_seconds": Int(duration),
            "capture_mode": mode,
            "quality": quality,
            "device_model": deviceModel
        ])
    }

    func trackRecordingFailed(error: String, mode: String) {
        logEvent("recording_failed", parameters: [
            "error": error,
            "capture_mode": mode
        ])
    }

    func trackPhotoCaptured(mode: String) {
        logEvent("photo_captured", parameters: [
            "capture_mode": mode,
            "device_model": deviceModel
        ])
    }

    // MARK: - Premium Events

    func trackPremiumUpgradeShown(source: String) {
        logEvent("premium_upgrade_shown", parameters: [
            "source": source
        ])
    }

    func trackPurchaseInitiated(productType: String) {
        logEvent("purchase_initiated", parameters: [
            "product_type": productType
        ])
    }

    func trackPurchaseCompleted(productType: String, price: String, currency: String) {
        logEvent("purchase_completed", parameters: [
            "product_type": productType,
            "price": price,
            "currency": currency
        ])
    }

    func trackPurchaseFailed(productType: String, error: String) {
        logEvent("purchase_failed", parameters: [
            "product_type": productType,
            "error": error
        ])
    }

    func trackRestorePurchases(success: Bool) {
        logEvent("restore_purchases", parameters: [
            "success": success
        ])
    }

    // MARK: - App Lifecycle

    func trackAppLaunched(isFirstLaunch: Bool) {
        logEvent("app_launched", parameters: [
            "is_first_launch": isFirstLaunch,
            "device_model": deviceModel,
            "os_version": osVersion
        ])
    }

    func trackPermissionRequested(permission: String) {
        logEvent("permission_requested", parameters: [
            "permission_type": permission
        ])
    }

    func trackPermissionGranted(permission: String) {
        logEvent("permission_granted", parameters: [
            "permission_type": permission
        ])
    }

    func trackPermissionDenied(permission: String) {
        logEvent("permission_denied", parameters: [
            "permission_type": permission
        ])
    }

    // MARK: - User Actions

    func trackModeChanged(from: String, to: String) {
        logEvent("capture_mode_changed", parameters: [
            "from_mode": from,
            "to_mode": to
        ])
    }

    func trackZoomChanged(camera: String, zoomLevel: Double) {
        logEvent("zoom_changed", parameters: [
            "camera_position": camera,
            "zoom_level": zoomLevel
        ])
    }

    func trackSettingsOpened() {
        logEvent("settings_opened", parameters: [:])
    }

    func trackGalleryOpened() {
        logEvent("gallery_opened", parameters: [:])
    }

    // MARK: - Error Events

    func trackError(domain: String, code: Int, description: String) {
        logEvent("app_error", parameters: [
            "error_domain": domain,
            "error_code": code,
            "error_description": description
        ])
    }

    func trackStorageWarning(availableGB: Double) {
        logEvent("storage_warning", parameters: [
            "available_gb": availableGB
        ])
    }

    // MARK: - Private Helpers

    private func logEvent(_ name: String, parameters: [String: Any]) {
        // TODO: Replace with Firebase Analytics when integrated
        // Analytics.logEvent(name, parameters: parameters)

        #if DEBUG
        print("📊 Analytics Event: \(name)")
        if !parameters.isEmpty {
            print("   Parameters: \(parameters)")
        }
        #endif
    }

    private var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }
        return modelCode ?? "Unknown"
    }

    private var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}

// MARK: - Crashlytics Integration Scaffold

extension AnalyticsService {
    func setUserProperty(_ value: String, forKey key: String) {
        // TODO: Replace with Firebase Analytics when integrated
        // Analytics.setUserProperty(value, forName: key)

        #if DEBUG
        print("📊 User Property Set: \(key) = \(value)")
        #endif
    }

    func recordError(_ error: Error, userInfo: [String: Any] = [:]) {
        // TODO: Replace with Firebase Crashlytics when integrated
        // Crashlytics.crashlytics().record(error: error, userInfo: userInfo)

        #if DEBUG
        print("❌ Error Recorded: \(error.localizedDescription)")
        if !userInfo.isEmpty {
            print("   User Info: \(userInfo)")
        }
        #endif
    }

    func setCustomKey(_ key: String, value: Any) {
        // TODO: Replace with Firebase Crashlytics when integrated
        // Crashlytics.crashlytics().setCustomValue(value, forKey: key)

        #if DEBUG
        print("📊 Custom Key Set: \(key) = \(value)")
        #endif
    }
}
