
//
//  PhotoLibraryService.swift
//  DualCam Pro
//
//  Photo library integration for saving recordings
//

import Photos
import AVFoundation
import UIKit

final class PhotoLibraryService {
    nonisolated(unsafe) static let shared = PhotoLibraryService()
    
    private let albumName = "DualCam Pro"
    private var albumPlaceholder: PHObjectPlaceholder?
    
    private init() {}
    
    // MARK: - Authorization
    
    func requestAuthorization() async -> PHAuthorizationStatus {
        return await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    }
    
    func checkAuthorizationStatus() -> PHAuthorizationStatus {
        return PHPhotoLibrary.authorizationStatus(for: .addOnly)
    }
    
    // MARK: - Save Video
    
    func saveVideo(at url: URL, createAlbum: Bool = true) async throws -> String {
        let status = await requestAuthorization()
        
        guard status == .authorized || status == .limited else {
            throw NSError(domain: "PhotoLibraryService", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Photo library access denied"
            ])
        }
        
        var localIdentifier: String?
        
        try await PHPhotoLibrary.shared().performChanges {
            let creationRequest = PHAssetCreationRequest.forAsset()
            creationRequest.addResource(with: .video, fileURL: url, options: nil)
            
            if createAlbum {
                if let album = self.getAlbum() {
                    if let placeholder = creationRequest.placeholderForCreatedAsset {
                        let albumChangeRequest = PHAssetCollectionChangeRequest(for: album)
                        albumChangeRequest?.addAssets([placeholder] as NSArray)
                    }
                } else {
                    // Create album
                    let albumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: self.albumName)
                    self.albumPlaceholder = albumRequest.placeholderForCreatedAssetCollection
                    
                    if let placeholder = creationRequest.placeholderForCreatedAsset {
                        albumRequest.addAssets([placeholder] as NSArray)
                    }
                }
            }
            
            localIdentifier = creationRequest.placeholderForCreatedAsset?.localIdentifier
        }
        
        return localIdentifier ?? ""
    }
    
    func saveThreeVideos(
        dualView: URL,
        front: URL,
        back: URL,
        createAlbum: Bool = true
    ) async throws -> (String, String, String) {
        let dualID = try await saveVideo(at: dualView, createAlbum: createAlbum)
        let frontID = try await saveVideo(at: front, createAlbum: createAlbum)
        let backID = try await saveVideo(at: back, createAlbum: createAlbum)
        
        return (dualID, frontID, backID)
    }
    
    // MARK: - Album Management
    
    private func getAlbum() -> PHAssetCollection? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: fetchOptions
        )
        return collections.firstObject
    }
    
    func createAlbum() async throws {
        guard getAlbum() == nil else { return }
        
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: self.albumName)
        }
    }
    
    // MARK: - Fetch Videos
    
    func fetchDualCamVideos() -> PHFetchResult<PHAsset> {
        guard let album = getAlbum() else {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
            return PHAsset.fetchAssets(with: options)
        }
        
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(in: album, options: options)
    }
    
    // MARK: - Delete Video
    
    func deleteVideo(withIdentifier identifier: String) async throws {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        
        guard let asset = fetchResult.firstObject else {
            throw NSError(domain: "PhotoLibraryService", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Video not found"
            ])
        }
        
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        }
    }
    
    // MARK: - Thumbnail Generation
    
    func generateThumbnail(for url: URL, size: CGSize = CGSize(width: 200, height: 200)) async -> UIImage? {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = size
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }
}
