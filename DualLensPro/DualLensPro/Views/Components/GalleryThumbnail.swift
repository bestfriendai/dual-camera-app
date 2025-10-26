//
//  GalleryThumbnail.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import SwiftUI
import Photos

struct GalleryThumbnail: View {
    let onTap: () -> Void

    @State private var thumbnailImage: UIImage?
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            HapticManager.shared.light()
            onTap()
        }) {
            ZStack {
                // Background material
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .frame(width: 56, height: 56)

                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .frame(width: 52, height: 52)
                        .overlay {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 22))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                }

                // Liquid glass border
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.5),
                                .white.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 56, height: 56)
            }
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        }
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .onAppear {
            loadLatestPhoto()
        }
    }

    private func loadLatestPhoto() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1

        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        guard let asset = fetchResult.firstObject else { return }

        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = false
        requestOptions.deliveryMode = .opportunistic

        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 100, height: 100),
            contentMode: .aspectFill,
            options: requestOptions
        ) { image, _ in
            if let image = image {
                DispatchQueue.main.async {
                    self.thumbnailImage = image
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        GalleryThumbnail {}
    }
}
