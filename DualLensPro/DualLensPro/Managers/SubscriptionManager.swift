//
//  SubscriptionManager.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import Foundation
import StoreKit
import Combine

@MainActor
class SubscriptionManager: ObservableObject {
    // MARK: - Published Properties
    @Published var subscriptionTier: SubscriptionTier = .free
    @Published var isLoading = false
    @Published var showUpgradePrompt = false
    @Published var errorMessage: String?

    // Recording limits
    @Published var currentRecordingDuration: TimeInterval = 0
    @Published var showTimeWarning = false // Shows at 2:30 for free users

    // MARK: - Constants
    static let freeRecordingLimit: TimeInterval = 180 // 3 minutes in seconds
    static let warningThreshold: TimeInterval = 150 // 2:30 in seconds

    // MARK: - Product IDs (Mock for now)
    private let premiumMonthlyProductID = "com.duallens.premium.monthly"
    private let premiumYearlyProductID = "com.duallens.premium.yearly"

    // MARK: - UserDefaults Keys
    private let subscriptionTierKey = "subscriptionTier"

    // MARK: - Initialization
    init() {
        loadSubscriptionStatus()
        // IMPORTANT: Reset recording duration on app launch
        // This ensures users can record even if previous session hit the limit or crashed
        resetRecordingDuration()
        print("📱 SubscriptionManager initialized - isPremium: \(isPremium), canRecord: \(canRecord)")
    }

    // MARK: - Subscription Status
    var isPremium: Bool {
        subscriptionTier == .premium
    }

    var isFree: Bool {
        subscriptionTier == .free
    }

    var canRecord: Bool {
        if isPremium {
            return true
        }
        return currentRecordingDuration < Self.freeRecordingLimit
    }

    var remainingRecordingTime: TimeInterval {
        if isPremium {
            return .infinity
        }
        return max(0, Self.freeRecordingLimit - currentRecordingDuration)
    }

    var recordingLimitReached: Bool {
        if isPremium {
            return false
        }
        return currentRecordingDuration >= Self.freeRecordingLimit
    }

    // MARK: - Recording Time Tracking
    func updateRecordingDuration(_ duration: TimeInterval) {
        currentRecordingDuration = duration

        // Show warning at 2:30 for free users
        if isFree && duration >= Self.warningThreshold && !recordingLimitReached {
            showTimeWarning = true
        }

        // Show upgrade prompt when limit reached
        if recordingLimitReached && isFree {
            showUpgradePrompt = true
        }
    }

    func resetRecordingDuration() {
        currentRecordingDuration = 0
        showTimeWarning = false
    }

    // MARK: - Subscription Management
    func loadSubscriptionStatus() {
        // Load from UserDefaults (in production, verify with StoreKit)
        if let tierString = UserDefaults.standard.string(forKey: subscriptionTierKey),
           let tier = SubscriptionTier(rawValue: tierString) {
            subscriptionTier = tier
        } else {
            subscriptionTier = .free
        }
    }

    func saveSubscriptionStatus() {
        UserDefaults.standard.set(subscriptionTier.rawValue, forKey: subscriptionTierKey)
    }

    // MARK: - Purchase Flow (Mock Implementation)
    func purchasePremium(productType: PremiumProductType) async throws {
        isLoading = true
        defer { isLoading = false }

        // Simulate network delay
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // In production, use StoreKit 2 to handle purchases
        // For now, this is a mock implementation
        subscriptionTier = .premium
        saveSubscriptionStatus()
        showUpgradePrompt = false
    }

    func restorePurchases() async throws {
        isLoading = true
        defer { isLoading = false }

        // Simulate network delay
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // In production, use StoreKit 2 to restore purchases
        // For now, check UserDefaults
        loadSubscriptionStatus()
    }

    // MARK: - Product Information (Mock)
    func getProductInfo(for productType: PremiumProductType) -> ProductInfo {
        switch productType {
        case .monthly:
            return ProductInfo(
                id: premiumMonthlyProductID,
                displayName: "Premium Monthly",
                description: "Unlimited recording, all features",
                price: "$4.99",
                period: "month"
            )
        case .yearly:
            return ProductInfo(
                id: premiumYearlyProductID,
                displayName: "Premium Yearly",
                description: "Unlimited recording, all features, save 40%",
                price: "$29.99",
                period: "year"
            )
        }
    }

    // MARK: - Feature Access Control
    func canAccessFeature(_ feature: PremiumFeature) -> Bool {
        if isPremium {
            return true
        }
        return !feature.requiresPremium
    }

    func requiresPremiumAlert(for feature: PremiumFeature) {
        errorMessage = "\(feature.displayName) requires Premium subscription"
        showUpgradePrompt = true
    }

    // MARK: - Trial Management (Optional)
    func startFreeTrial() async throws {
        // Implement free trial logic if desired
    }
}

// MARK: - Subscription Tier
enum SubscriptionTier: String, Codable {
    case free
    case premium

    var displayName: String {
        switch self {
        case .free:
            return "Free"
        case .premium:
            return "Premium"
        }
    }

    var benefits: [String] {
        switch self {
        case .free:
            return [
                "3 minute recording limit",
                "Basic dual camera recording",
                "Photo capture",
                "Grid overlay"
            ]
        case .premium:
            return [
                "Unlimited recording time",
                "All capture modes",
                "High frame rate action mode",
                "Advanced camera controls",
                "No watermark",
                "Priority support"
            ]
        }
    }
}

// MARK: - Premium Product Types
enum PremiumProductType: String, CaseIterable {
    case monthly
    case yearly

    var displayName: String {
        switch self {
        case .monthly:
            return "Monthly"
        case .yearly:
            return "Yearly"
        }
    }
}

// MARK: - Product Info
struct ProductInfo {
    let id: String
    let displayName: String
    let description: String
    let price: String
    let period: String

    var pricePerMonth: String {
        switch period {
        case "month":
            return price
        case "year":
            // Calculate monthly price for yearly subscription
            if let yearlyPrice = Double(price.replacingOccurrences(of: "$", with: "")) {
                let monthly = yearlyPrice / 12
                return String(format: "$%.2f", monthly)
            }
            return price
        default:
            return price
        }
    }
}

// MARK: - Premium Features
enum PremiumFeature {
    case unlimitedRecording
    case actionMode
    case switchScreenMode
    case advancedControls
    case noWatermark

    var requiresPremium: Bool {
        switch self {
        case .unlimitedRecording, .actionMode, .switchScreenMode, .advancedControls, .noWatermark:
            return true
        }
    }

    var displayName: String {
        switch self {
        case .unlimitedRecording:
            return "Unlimited Recording"
        case .actionMode:
            return "Action Mode"
        case .switchScreenMode:
            return "Switch Screen Mode"
        case .advancedControls:
            return "Advanced Camera Controls"
        case .noWatermark:
            return "No Watermark"
        }
    }

    var description: String {
        switch self {
        case .unlimitedRecording:
            return "Record videos of any length without time limits"
        case .actionMode:
            return "High frame rate recording perfect for action shots"
        case .switchScreenMode:
            return "Switch which camera appears on top or bottom"
        case .advancedControls:
            return "Fine-tune exposure, white balance, and more"
        case .noWatermark:
            return "Export videos without DualLensPro watermark"
        }
    }
}
