//
//  GalleryButtonView.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI

struct GalleryButtonView: View {
    @EnvironmentObject var viewModel: CameraViewModel

    var body: some View {
        Button(action: {
            viewModel.openGallery()
        }) {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.2))
                    .frame(width: 56, height: 56)

                // Thumbnail or placeholder
                if let thumbnail = viewModel.latestPhotoThumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title2)
                        .foregroundStyle(.white)
                }

                // Border
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.4), lineWidth: 2)
                    .frame(width: 56, height: 56)
            }
        }
        .onAppear {
            viewModel.loadLatestPhoto()
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        GalleryButtonView()
            .environmentObject(CameraViewModel())
    }
}
