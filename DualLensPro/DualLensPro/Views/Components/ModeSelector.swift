//
//  ModeSelector.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI

struct ModeSelector: View {
    @Binding var selectedMode: CaptureMode
    var isPremium: Bool = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(CaptureMode.allCases) { mode in
                    ModeButton(
                        mode: mode,
                        isSelected: selectedMode == mode,
                        isPremium: isPremium,
                        action: {
                            HapticManager.shared.modeChange()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedMode = mode
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 50)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()
            ModeSelector(selectedMode: .constant(.video))
                .padding(.bottom, 20)
        }
    }
}
