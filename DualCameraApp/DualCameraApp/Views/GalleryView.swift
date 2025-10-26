//
//  GalleryView.swift
//  DualCam Pro
//
//  Gallery of recorded videos
//

import SwiftUI
import Photos

struct GalleryView: View {
    @StateObject private var viewModel = GalleryViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if viewModel.recordings.isEmpty {
                    VStack {
                        Image(systemName: "video.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No recordings yet")
                            .font(.headline)
                            .foregroundColor(.gray)
                            .padding(.top)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 10) {
                            ForEach(viewModel.recordings) { recording in
                                RecordingThumbnail(recording: recording)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Gallery")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await viewModel.loadRecordings()
            }
        }
    }
}

struct RecordingThumbnail: View {
    let recording: Recording

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.gray.opacity(0.3))
            .aspectRatio(16/9, contentMode: .fit)
            .overlay(
                VStack {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                    Text(recording.createdAt, style: .date)
                        .font(.caption)
                        .foregroundColor(.white)
                }
            )
    }
}

#Preview {
    GalleryView()
}
