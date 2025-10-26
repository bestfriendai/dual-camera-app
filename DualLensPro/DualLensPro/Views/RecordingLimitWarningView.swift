//
//  RecordingLimitWarningView.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI

struct RecordingLimitWarningView: View {
    @EnvironmentObject var viewModel: CameraViewModel

    var remainingTime: TimeInterval {
        viewModel.remainingRecordingTime
    }

    var formattedTime: String {
        let seconds = Int(remainingTime)
        return "\(seconds)s"
    }

    var shouldShow: Bool {
        viewModel.shouldShowTimeWarning && !viewModel.isPremium
    }

    var body: some View {
        if shouldShow {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.yellow)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Recording Limit Approaching")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    Text("\(formattedTime) remaining • Upgrade for unlimited")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }

                Spacer()

                Button(action: {
                    viewModel.showPremiumPrompt()
                }) {
                    Text("Upgrade")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.black.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.yellow.opacity(0.5), lineWidth: 1)
            )
            .padding(.horizontal, 20)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            RecordingLimitWarningView()
            Spacer()
        }
    }
    .environmentObject({
        let vm = CameraViewModel()
        vm.subscriptionManager.updateRecordingDuration(150)
        return vm
    }())
}
