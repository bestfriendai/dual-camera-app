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
                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white.opacity(0.2))
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                }

                // Simple border
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.white.opacity(0.3), lineWidth: 1.5)
                    .frame(width: 44, height: 44)
            }
        }
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
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
