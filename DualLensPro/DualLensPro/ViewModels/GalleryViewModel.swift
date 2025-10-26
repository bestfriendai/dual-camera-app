//
//  GalleryViewModel.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import Foundation
import Photos
import SwiftUI

@MainActor
class GalleryViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var assets: [PHAsset] = []
    @Published var selectedAsset: PHAsset?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false

    // MARK: - Services
    private let photoLibraryService: PhotoLibraryService

    // MARK: - Initialization
    init(photoLibraryService: PhotoLibraryService = PhotoLibraryService()) {
        self.photoLibraryService = photoLibraryService
    }

    // MARK: - Authorization
    var isAuthorized: Bool {
        photoLibraryService.isAuthorized
    }

    func requestAuthorization() async {
        let granted = await photoLibraryService.requestAuthorization()
        if granted {
            await loadAssets()
        } else {
            showError(message: "Photo library access is required to view your media")
        }
    }

    // MARK: - Load Assets
    func loadAssets() async {
        guard photoLibraryService.isAuthorized else {
            await requestAuthorization()
            return
        }

        isLoading = true
        defer { isLoading = false }

        let fetchResult = photoLibraryService.fetchRecentAssets(limit: 100)
        assets = fetchResult.objects(at: IndexSet(integersIn: 0..<fetchResult.count))
    }

    // MARK: - Load DualLensPro Videos
    func loadDualLensProVideos() async {
        guard photoLibraryService.isAuthorized else {
            await requestAuthorization()
            return
        }

        isLoading = true
        defer { isLoading = false }

        let fetchResult = photoLibraryService.fetchDualLensProVideos(limit: 100)
        assets = fetchResult.objects(at: IndexSet(integersIn: 0..<fetchResult.count))
    }

    // MARK: - Asset Selection
    func selectAsset(_ asset: PHAsset) {
        selectedAsset = asset
    }

    func deselectAsset() {
        selectedAsset = nil
    }

    // MARK: - Delete Asset
    func deleteAsset(_ asset: PHAsset) async {
        do {
            try await photoLibraryService.deleteAsset(asset)
            assets.removeAll { $0.localIdentifier == asset.localIdentifier }

            if selectedAsset?.localIdentifier == asset.localIdentifier {
                selectedAsset = nil
            }
        } catch {
            showError(message: "Failed to delete: \(error.localizedDescription)")
        }
    }

    // MARK: - Get Thumbnail
    func getThumbnail(for asset: PHAsset, size: CGSize) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            let manager = PHImageManager.default()
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true

            manager.requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: - Get Full Image
    func getFullImage(for asset: PHAsset) async -> UIImage? {
        guard asset.mediaType == .image else { return nil }

        return await withCheckedContinuation { continuation in
            let manager = PHImageManager.default()
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            manager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: - Get Video URL
    func getVideoURL(for asset: PHAsset) async -> URL? {
        return await photoLibraryService.getVideoURL(for: asset)
    }

    // MARK: - Share Asset
    func shareAsset(_ asset: PHAsset) async -> [Any] {
        var items: [Any] = []

        if asset.mediaType == .image {
            if let image = await getFullImage(for: asset) {
                items.append(image)
            }
        } else if asset.mediaType == .video {
            if let url = await getVideoURL(for: asset) {
                items.append(url)
            }
        }

        return items
    }

    // MARK: - Error Handling
    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}
