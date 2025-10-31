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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        .onAppear {
            loadLatestPhoto()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("RefreshGalleryThumbnail"))) { _ in
            print("🔄 Refreshing gallery thumbnail")
            loadLatestPhoto()
        }
        .accessibilityLabel("Photo library")
        .accessibilityHint("Double tap to open your photo library")
        .accessibilityValue(thumbnailImage != nil ? "Shows recent photo" : "No photos")
    }

    private func loadLatestPhoto() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1

        // Fetch all media types (photos and videos) to get the most recent
        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)

        guard let asset = fetchResult.firstObject else {
            print("⚠️ No assets found in photo library")
            return
        }

        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = false
        requestOptions.deliveryMode = .opportunistic
        requestOptions.isNetworkAccessAllowed = true

        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 100, height: 100),
            contentMode: .aspectFill,
            options: requestOptions
        ) { image, info in
            if let image = image {
                Task { @MainActor in
                    self.thumbnailImage = image
                }
            }
        }
    }

    // Refresh thumbnail when called externally
    func refresh() {
        loadLatestPhoto()
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        GalleryThumbnail {}
    }
}
