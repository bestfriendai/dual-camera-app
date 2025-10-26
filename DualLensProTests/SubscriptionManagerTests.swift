//
//  SubscriptionManagerTests.swift
//  DualLensProTests
//
//  Created by DualLens Pro Team on 10/26/25.
//

import XCTest
@testable import DualLensPro

@MainActor
final class SubscriptionManagerTests: XCTestCase {
    var subscriptionManager: SubscriptionManager!

    override func setUp() async throws {
        // Reset UserDefaults
        UserDefaults.standard.removeObject(forKey: "subscriptionTier")

        subscriptionManager = SubscriptionManager()
    }

    override func tearDown() async throws {
        subscriptionManager = nil
    }

    // MARK: - Free User Tests

    func testFreeUserInitialState() {
        XCTAssertEqual(subscriptionManager.subscriptionTier, .free)
        XCTAssertTrue(subscriptionManager.isFree)
        XCTAssertFalse(subscriptionManager.isPremium)
        XCTAssertTrue(subscriptionManager.canRecord)
        XCTAssertFalse(subscriptionManager.recordingLimitReached)
    }

    func testFreeUserRecordingLimit() {
        // Should be able to record initially
        XCTAssertTrue(subscriptionManager.canRecord)
        XCTAssertEqual(subscriptionManager.remainingRecordingTime, 180.0)

        // Simulate recording for 2:30
        subscriptionManager.updateRecordingDuration(150)
        XCTAssertTrue(subscriptionManager.showTimeWarning)
        XCTAssertTrue(subscriptionManager.canRecord)
        XCTAssertEqual(subscriptionManager.remainingRecordingTime, 30.0)

        // Simulate recording for 3:00
        subscriptionManager.updateRecordingDuration(180)
        XCTAssertTrue(subscriptionManager.recordingLimitReached)
        XCTAssertFalse(subscriptionManager.canRecord)
        XCTAssertEqual(subscriptionManager.remainingRecordingTime, 0.0)
        XCTAssertTrue(subscriptionManager.showUpgradePrompt)
    }

    func testResetRecordingDuration() {
        subscriptionManager.updateRecordingDuration(180)
        XCTAssertTrue(subscriptionManager.recordingLimitReached)

        subscriptionManager.resetRecordingDuration()
        XCTAssertEqual(subscriptionManager.currentRecordingDuration, 0)
        XCTAssertFalse(subscriptionManager.showTimeWarning)
        XCTAssertTrue(subscriptionManager.canRecord)
    }

    // MARK: - Premium User Tests

    func testPremiumUserNoLimit() {
        // Manually set premium (in production, this would come from StoreKit)
        subscriptionManager.subscriptionTier = .premium

        XCTAssertTrue(subscriptionManager.isPremium)
        XCTAssertFalse(subscriptionManager.isFree)
        XCTAssertTrue(subscriptionManager.canRecord)

        // Simulate recording for 10 minutes
        subscriptionManager.updateRecordingDuration(600)
        XCTAssertTrue(subscriptionManager.canRecord)
        XCTAssertFalse(subscriptionManager.showTimeWarning)
        XCTAssertFalse(subscriptionManager.recordingLimitReached)
        XCTAssertEqual(subscriptionManager.remainingRecordingTime, .infinity)
    }

    func testPremiumUserFeatureAccess() {
        subscriptionManager.subscriptionTier = .premium

        XCTAssertTrue(subscriptionManager.canAccessFeature(.unlimitedRecording))
        XCTAssertTrue(subscriptionManager.canAccessFeature(.actionMode))
        XCTAssertTrue(subscriptionManager.canAccessFeature(.switchScreenMode))
        XCTAssertTrue(subscriptionManager.canAccessFeature(.advancedControls))
        XCTAssertTrue(subscriptionManager.canAccessFeature(.noWatermark))
    }

    // MARK: - Product Information Tests

    func testGetProductInfoMonthly() {
        let productInfo = subscriptionManager.getProductInfo(for: .monthly)
        XCTAssertEqual(productInfo.id, "com.duallens.premium.monthly")
        XCTAssertEqual(productInfo.displayName, "Premium Monthly")
        XCTAssertEqual(productInfo.period, "month")
        XCTAssertEqual(productInfo.pricePerMonth, "$4.99")
    }

    func testGetProductInfoYearly() {
        let productInfo = subscriptionManager.getProductInfo(for: .yearly)
        XCTAssertEqual(productInfo.id, "com.duallens.premium.yearly")
        XCTAssertEqual(productInfo.displayName, "Premium Yearly")
        XCTAssertEqual(productInfo.period, "year")
        XCTAssertEqual(productInfo.pricePerMonth, "$2.50")  // $29.99 / 12
    }

    // MARK: - Subscription Benefits Tests

    func testFreeTierBenefits() {
        let benefits = SubscriptionTier.free.benefits
        XCTAssertTrue(benefits.contains("3 minute recording limit"))
        XCTAssertTrue(benefits.contains("Basic dual camera recording"))
    }

    func testPremiumTierBenefits() {
        let benefits = SubscriptionTier.premium.benefits
        XCTAssertTrue(benefits.contains("Unlimited recording time"))
        XCTAssertTrue(benefits.contains("All capture modes"))
        XCTAssertTrue(benefits.contains("No watermark"))
    }

    // MARK: - Persistence Tests

    func testSubscriptionPersistence() {
        subscriptionManager.subscriptionTier = .premium
        subscriptionManager.saveSubscriptionStatus()

        // Create new instance
        let newManager = SubscriptionManager()
        XCTAssertEqual(newManager.subscriptionTier, .premium)
    }
}
