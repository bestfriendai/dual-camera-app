//
//  DeviceMonitorService.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/27/25.
//  System monitoring service for thermal state, battery, and memory pressure
//

import Foundation
import UIKit
import os

// MARK: - Device State
enum DeviceState {
    case nominal
    case warning
    case critical
}

// MARK: - Monitoring Delegate
protocol DeviceMonitorDelegate: AnyObject {
    func deviceMonitor(_ monitor: DeviceMonitorService, didUpdateThermalState state: ProcessInfo.ThermalState)
    func deviceMonitor(_ monitor: DeviceMonitorService, didUpdateBatteryLevel level: Float, state: UIDevice.BatteryState)
    func deviceMonitor(_ monitor: DeviceMonitorService, didReceiveMemoryWarning: Void)
}

// MARK: - Device Monitor Service
@MainActor
final class DeviceMonitorService: NSObject, @unchecked Sendable {

    // MARK: - Singleton
    static let shared = DeviceMonitorService()

    // MARK: - Delegate
    weak var delegate: DeviceMonitorDelegate?

    // MARK: - Published State
    @Published private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    @Published private(set) var batteryLevel: Float = 1.0
    @Published private(set) var batteryState: UIDevice.BatteryState = .unknown
    @Published private(set) var memoryUsageMB: UInt64 = 0
    @Published private(set) var deviceState: DeviceState = .nominal

    // MARK: - Internal State
    private var isMonitoring = false
    private var lastBatteryWarningLevel: Float = 1.0
    private let logger = Logger(subsystem: "com.duallens.pro", category: "DeviceMonitor")

    // MARK: - Initialization
    private override init() {
        super.init()
        logger.info("📊 DeviceMonitorService initialized")
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Monitoring Control

    /// Start monitoring thermal state, battery, and memory
    func startMonitoring() {
        guard !isMonitoring else {
            logger.warning("⚠️ DeviceMonitor already monitoring")
            return
        }

        isMonitoring = true
        logger.info("✅ DeviceMonitor starting monitoring")

        // Enable battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true

        // Register for thermal state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateDidChange),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )

        // Register for battery level changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryLevelDidChange),
            name: UIDevice.batteryLevelDidChangeNotification,
            object: nil
        )

        // Register for battery state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryStateDidChange),
            name: UIDevice.batteryStateDidChangeNotification,
            object: nil
        )

        // Register for memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(memoryWarningReceived),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        // Check initial states
        checkThermalState()
        checkBatteryLevel()
        updateMemoryUsage()

        logger.info("✅ DeviceMonitor monitoring started")
    }

    /// Stop monitoring
    func stopMonitoring() {
        guard isMonitoring else { return }

        isMonitoring = false
        logger.info("🛑 DeviceMonitor stopping monitoring")

        // Remove all observers
        NotificationCenter.default.removeObserver(
            self,
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: UIDevice.batteryLevelDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: UIDevice.batteryStateDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        // Disable battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = false

        logger.info("✅ DeviceMonitor monitoring stopped")
    }

    // MARK: - Thermal State Monitoring

    @objc nonisolated private func thermalStateDidChange(notification: Notification) {
        Task { @MainActor in
            checkThermalState()
        }
    }

    private func checkThermalState() {
        let newState = ProcessInfo.processInfo.thermalState

        guard newState != thermalState else { return }

        thermalState = newState

        switch thermalState {
        case .nominal:
            logger.info("📊 Thermal state: Nominal")
            updateDeviceState()

        case .fair:
            logger.warning("⚠️ Thermal state: Fair - device warming up")
            updateDeviceState()

        case .serious:
            logger.error("🌡️ Thermal state: Serious - device is hot")
            updateDeviceState()

        case .critical:
            logger.critical("🔥 Thermal state: CRITICAL - device overheating!")
            updateDeviceState()

        @unknown default:
            logger.warning("⚠️ Unknown thermal state")
        }

        // Notify delegate
        delegate?.deviceMonitor(self, didUpdateThermalState: thermalState)
    }

    /// Check if thermal state allows recording
    func canStartRecordingThermal() -> (allowed: Bool, reason: String?) {
        switch thermalState {
        case .nominal, .fair:
            return (true, nil)
        case .serious:
            return (false, "Device is too hot. Please let it cool down.")
        case .critical:
            return (false, "Device is overheating. Recording disabled for safety.")
        @unknown default:
            return (true, nil)
        }
    }

    /// Check if recording should be stopped due to thermal state
    func shouldStopRecordingThermal() -> (stop: Bool, reason: String?) {
        switch thermalState {
        case .serious:
            return (true, "Recording stopped - device is overheating")
        case .critical:
            return (true, "Recording stopped - critical thermal state")
        default:
            return (false, nil)
        }
    }

    // MARK: - Battery Monitoring

    @objc nonisolated private func batteryLevelDidChange(notification: Notification) {
        Task { @MainActor in
            checkBatteryLevel()
        }
    }

    @objc nonisolated private func batteryStateDidChange(notification: Notification) {
        Task { @MainActor in
            checkBatteryLevel()
        }
    }

    private func checkBatteryLevel() {
        let newLevel = UIDevice.current.batteryLevel
        let newState = UIDevice.current.batteryState

        // batteryLevel returns -1.0 if battery state is unknown
        guard newLevel >= 0 else {
            logger.warning("⚠️ Battery level unknown")
            return
        }

        batteryLevel = newLevel
        batteryState = newState

        // Only warn if unplugged
        guard batteryState == .unplugged else {
            logger.info("🔌 Device is charging/plugged in")
            return
        }

        let percentage = Int(batteryLevel * 100)

        // Log battery warnings at specific thresholds
        if batteryLevel <= 0.10 && lastBatteryWarningLevel > 0.10 {
            logger.critical("🔋 Critical battery: \(percentage)%")
        } else if batteryLevel <= 0.15 && lastBatteryWarningLevel > 0.15 {
            logger.error("🔋 Low battery: \(percentage)%")
        } else if batteryLevel <= 0.20 && lastBatteryWarningLevel > 0.20 {
            logger.warning("🔋 Battery warning: \(percentage)%")
        }

        lastBatteryWarningLevel = batteryLevel
        updateDeviceState()

        // Notify delegate
        delegate?.deviceMonitor(self, didUpdateBatteryLevel: batteryLevel, state: batteryState)
    }

    /// Check if battery level allows recording
    func canStartRecordingBattery() -> (allowed: Bool, reason: String?) {
        // Always allow if charging
        guard batteryState == .unplugged else {
            return (true, nil)
        }

        if batteryLevel <= 0.10 {
            return (false, "Battery too low to record (< 10%). Please charge device.")
        }

        return (true, nil)
    }

    /// Check if recording should be stopped due to low battery
    func shouldStopRecordingBattery() -> (stop: Bool, reason: String?, warning: String?) {
        // Never stop if charging
        guard batteryState == .unplugged else {
            return (false, nil, nil)
        }

        let percentage = Int(batteryLevel * 100)

        if batteryLevel <= 0.10 {
            return (true, "Recording stopped - battery critically low (\(percentage)%)", nil)
        } else if batteryLevel <= 0.15 {
            return (false, nil, "Low battery (\(percentage)%) - recording may stop soon")
        } else if batteryLevel <= 0.20 {
            return (false, nil, "Battery at \(percentage)% - consider charging")
        }

        return (false, nil, nil)
    }

    // MARK: - Memory Monitoring

    @objc nonisolated private func memoryWarningReceived(notification: Notification) {
        Task { @MainActor in
            handleMemoryWarning()
        }
    }

    private func handleMemoryWarning() {
        updateMemoryUsage()
        logger.error("⚠️ Memory warning received - usage: \(memoryUsageMB)MB")
        updateDeviceState()

        // Notify delegate
        delegate?.deviceMonitor(self, didReceiveMemoryWarning: ())
    }

    /// Update current memory usage
    func updateMemoryUsage() {
        memoryUsageMB = getMemoryUsage()
    }

    /// Get current memory usage in MB
    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        return kerr == KERN_SUCCESS ? info.resident_size / 1_048_576 : 0 // Convert to MB
    }

    /// Check if memory usage is acceptable for recording
    func canStartRecordingMemory() -> (allowed: Bool, reason: String?) {
        updateMemoryUsage()

        if memoryUsageMB > 1500 {  // 1.5GB threshold for high memory usage
            return (false, "Memory usage too high. Please close other apps.")
        }

        return (true, nil)
    }

    /// Check if recording should be stopped due to memory pressure
    func shouldStopRecordingMemory() -> (stop: Bool, reason: String?, warning: String?) {
        updateMemoryUsage()

        if memoryUsageMB > 1800 {  // 1.8GB critical threshold
            return (true, "Recording stopped - critical memory pressure", nil)
        } else if memoryUsageMB > 1500 {  // 1.5GB warning threshold
            return (false, nil, "High memory usage - may drop frames")
        }

        return (false, nil, nil)
    }

    // MARK: - Overall Device State

    private func updateDeviceState() {
        let newState: DeviceState

        // Critical conditions
        if thermalState == .critical ||
           (batteryState == .unplugged && batteryLevel <= 0.10) ||
           memoryUsageMB > 1800 {
            newState = .critical
        }
        // Warning conditions
        else if thermalState == .serious ||
                (batteryState == .unplugged && batteryLevel <= 0.20) ||
                memoryUsageMB > 1500 {
            newState = .warning
        }
        // Nominal
        else {
            newState = .nominal
        }

        if newState != deviceState {
            deviceState = newState
            logger.info("📊 Device state updated: \(String(describing: deviceState))")
        }
    }

    // MARK: - Combined Checks

    /// Check all conditions before starting recording
    func canStartRecording() -> (allowed: Bool, reasons: [String]) {
        var reasons: [String] = []

        let thermal = canStartRecordingThermal()
        if !thermal.allowed, let reason = thermal.reason {
            reasons.append(reason)
        }

        let battery = canStartRecordingBattery()
        if !battery.allowed, let reason = battery.reason {
            reasons.append(reason)
        }

        let memory = canStartRecordingMemory()
        if !memory.allowed, let reason = memory.reason {
            reasons.append(reason)
        }

        return (reasons.isEmpty, reasons)
    }

    /// Check all conditions during recording
    func shouldStopRecording() -> (stop: Bool, reasons: [String], warnings: [String]) {
        var reasons: [String] = []
        var warnings: [String] = []

        let thermal = shouldStopRecordingThermal()
        if thermal.stop, let reason = thermal.reason {
            reasons.append(reason)
        }

        let battery = shouldStopRecordingBattery()
        if battery.stop, let reason = battery.reason {
            reasons.append(reason)
        } else if let warning = battery.warning {
            warnings.append(warning)
        }

        let memory = shouldStopRecordingMemory()
        if memory.stop, let reason = memory.reason {
            reasons.append(reason)
        } else if let warning = memory.warning {
            warnings.append(warning)
        }

        return (!reasons.isEmpty, reasons, warnings)
    }

    // MARK: - Memory Cleanup

    /// Perform aggressive memory cleanup
    func performMemoryCleanup() {
        logger.info("🧹 Performing memory cleanup")

        // Force release cached resources
        URLCache.shared.removeAllCachedResponses()

        updateMemoryUsage()
        logger.info("✅ Memory cleanup complete - current usage: \(memoryUsageMB)MB")
    }
}

// MARK: - Device Monitor Extensions

extension DeviceMonitorService {

    /// Get human-readable thermal state description
    var thermalStateDescription: String {
        switch thermalState {
        case .nominal:
            return "Normal"
        case .fair:
            return "Warm"
        case .serious:
            return "Hot"
        case .critical:
            return "Overheating"
        @unknown default:
            return "Unknown"
        }
    }

    /// Get battery level percentage
    var batteryPercentage: Int {
        Int(batteryLevel * 100)
    }

    /// Get battery state description
    var batteryStateDescription: String {
        switch batteryState {
        case .unknown:
            return "Unknown"
        case .unplugged:
            return "On Battery"
        case .charging:
            return "Charging"
        case .full:
            return "Full"
        @unknown default:
            return "Unknown"
        }
    }
}
