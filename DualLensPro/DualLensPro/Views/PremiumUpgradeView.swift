//
//  PremiumUpgradeView.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI

struct PremiumUpgradeView: View {
    @EnvironmentObject var viewModel: CameraViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedProductType: PremiumProductType = .yearly

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.yellow, .orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .padding(.top, 40)

                        Text("Upgrade to Premium")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)

                        Text("Unlock unlimited recording and all features")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }

                    // Features List
                    VStack(spacing: 16) {
                        ForEach(premiumFeatures, id: \.title) { feature in
                            FeatureRow(
                                icon: feature.icon,
                                title: feature.title,
                                description: feature.description
                            )
                        }
                    }
                    .padding(.horizontal, 20)

                    // Product Selection
                    VStack(spacing: 12) {
                        ForEach(PremiumProductType.allCases, id: \.self) { productType in
                            ProductCard(
                                productType: productType,
                                isSelected: selectedProductType == productType,
                                subscriptionManager: viewModel.subscriptionManager
                            ) {
                                selectedProductType = productType
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    // Purchase Button
                    Button(action: {
                        purchasePremium()
                    }) {
                        if viewModel.subscriptionManager.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Subscribe Now")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .padding(.horizontal, 20)
                    .disabled(viewModel.subscriptionManager.isLoading)

                    // Restore Button
                    Button(action: {
                        restorePurchases()
                    }) {
                        Text("Restore Purchases")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.bottom, 20)

                    // Terms
                    Text("Terms & Conditions • Privacy Policy")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.bottom, 40)
                }
            }

            // Close Button
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.top, 20)
                    .padding(.trailing, 20)
                }
                Spacer()
            }
        }
    }

    private func purchasePremium() {
        Task {
            await viewModel.purchasePremium(selectedProductType)
            if viewModel.isPremium {
                dismiss()
            }
        }
    }

    private func restorePurchases() {
        Task {
            await viewModel.restorePurchases()
            if viewModel.isPremium {
                dismiss()
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.blue)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.blue.opacity(0.2)))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.05))
        )
    }
}

struct ProductCard: View {
    let productType: PremiumProductType
    let isSelected: Bool
    let subscriptionManager: SubscriptionManager
    let action: () -> Void

    var productInfo: ProductInfo {
        subscriptionManager.getProductInfo(for: productType)
    }

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(productInfo.displayName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)

                        if productType == .yearly {
                            Text("SAVE 40%")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(.green))
                        }
                    }

                    Text(productInfo.description)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(productInfo.price)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)

                    Text("per \(productInfo.period)")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? .blue.opacity(0.3) : .white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? .blue : .clear, lineWidth: 2)
            )
        }
    }
}

// MARK: - Premium Features Data
private let premiumFeatures: [(icon: String, title: String, description: String)] = [
    ("infinity.circle.fill", "Unlimited Recording", "Record videos of any length without time limits"),
    ("bolt.circle.fill", "Action Mode", "High frame rate recording perfect for action shots"),
    ("arrow.up.arrow.down.circle.fill", "Switch Screen Mode", "Switch which camera appears on top or bottom"),
    ("slider.horizontal.3", "Advanced Controls", "Fine-tune exposure, white balance, and more"),
    ("wand.and.stars", "No Watermark", "Export videos without DualLensPro branding"),
    ("shield.checkered", "Priority Support", "Get help faster with priority customer support")
]

#Preview {
    PremiumUpgradeView()
        .environmentObject(CameraViewModel())
}
