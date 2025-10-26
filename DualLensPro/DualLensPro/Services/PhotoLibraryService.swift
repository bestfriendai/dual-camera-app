//
//  PhotoLibraryService.swift
//  DualLensPro
//
//  Created by DualLens Pro Team on 10/24/25.
//

import Foundation
import Photos
import UIKit

@MainActor
class PhotoLibraryService: ObservableObject {
    // MARK: - Published Properties
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var latestAsset: PHAsset?
    @Published var latestThumbnail: UIImage?
    @Published var errorMessage: String?

    // MARK: - Initialization
    init() {
        // Don't call checkAuthorizationStatus here - it can crash on iOS 26 during app initialization
        // Authorization will be checked when needed (in fetchLatestAsset or when explicitly called)
    }

    // MARK: - Authorization
    func checkAuthorizationStatus() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        return status == .authorized || status == .limited
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    // MARK: - Fetch Latest Asset
    func fetchLatestAsset() async {
        guard isAuthorized else {
            let granted = await requestAuthorization()
            guard granted else {
                errorMessage = "Photo library access not granted"
                return
            }
            // Authorization granted, continue with fetch
            return await fetchLatestAsset()
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1

        let result = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        guard let asset = result.firstObject else {
            // Try fetching videos if no images
            let videoResult = PHAsset.fetchAssets(with: .video, options: fetchOptions)
            latestAsset = videoResult.firstObject
            if let videoAsset = videoResult.firstObject {
                await fetchThumbnail(for: videoAsset)
            }
            return
        }

        latestAsset = asset
        await fetchThumbnail(for: asset)
    }

    // MARK: - Fetch Thumbnail
    func fetchThumbnail(for asset: PHAsset) async {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true

        let targetSize = CGSize(width: 100, height: 100)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            manager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { [weak self] image, _ in
                Task { @MainActor in
                    self?.latestThumbnail = image
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Fetch Recent Assets
    func fetchRecentAssets(limit: Int = 20) -> PHFetchResult<PHAsset> {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = limit

        return PHAsset.fetchAssets(with: fetchOptions)
    }

    // MARK: - Fetch DualLensPro Videos
    func fetchDualLensProVideos(limit: Int = 100) -> PHFetchResult<PHAsset> {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = limit
        // In production, you might want to filter by album or metadata
        return PHAsset.fetchAssets(with: .video, options: fetchOptions)
    }

    // MARK: - Delete Asset
    func deleteAsset(_ asset: PHAsset) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        }
    }

    // MARK: - Save Image
    func saveImage(_ image: UIImage) async throws -> String {
        var assetIdentifier: String?

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
            assetIdentifier = request.placeholderForCreatedAsset?.localIdentifier
        }

        guard let identifier = assetIdentifier else {
            throw PhotoLibraryError.failedToSave
        }

        // Update latest asset
        await fetchLatestAsset()

        return identifier
    }

    // MARK: - Save Video
    func saveVideo(at url: URL) async throws -> String {
        var assetIdentifier: String?

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            assetIdentifier = request?.placeholderForCreatedAsset?.localIdentifier
        }

        guard let identifier = assetIdentifier else {
            throw PhotoLibraryError.failedToSave
        }

        // Update latest asset
        await fetchLatestAsset()

        return identifier
    }

    // MARK: - Get Asset URL
    func getVideoURL(for asset: PHAsset) async -> URL? {
        guard asset.mediaType == .video else { return nil }

        return await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat

            PHImageManager.default().requestAVAsset(
                forVideo: asset,
                options: options
            ) { avAsset, _, _ in
                if let urlAsset = avAsset as? AVURLAsset {
                    continuation.resume(returning: urlAsset.url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Create Album
    func createDualLensProAlbum() async throws -> PHAssetCollection? {
        let albumName = "DualLensPro"

        // Check if album already exists
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
        let collection = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: fetchOptions
        )

        if let existingAlbum = collection.firstObject {
            return existingAlbum
        }

        // Create new album
        var albumPlaceholder: PHObjectPlaceholder?

        try await PHPhotoLibrary.shared().performChanges {
            let createAlbumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
            albumPlaceholder = createAlbumRequest.placeholderForCreatedAssetCollection
        }

        guard let placeholder = albumPlaceholder else {
            return nil
        }

        let fetchResult = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [placeholder.localIdentifier],
            options: nil
        )

        return fetchResult.firstObject
    }

    // MARK: - Add Asset to Album
    func addAsset(_ asset: PHAsset, to album: PHAssetCollection) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            if let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) {
                albumChangeRequest.addAssets([asset] as NSArray)
            }
        }
    }
}

// MARK: - Photo Library Error
enum PhotoLibraryError: LocalizedError {
    case notAuthorized
    case failedToSave
    case assetNotFound
    case invalidAssetType

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Photo library access not authorized"
        case .failedToSave:
            return "Failed to save to photo library"
        case .assetNotFound:
            return "Asset not found"
        case .invalidAssetType:
            return "Invalid asset type"
        }
    }
}
