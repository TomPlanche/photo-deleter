//
//  ContentView.swift
//  photo-deleter
//
//  Created by Tom Planche on 22/01/2025.
//

import SwiftUI
import SwiftData
import Photos

struct ContentView: View {
    @State private var currentImage: UIImage?
    @State private var offset: CGFloat = 0
    @State private var isPhotoAccessGranted = false
    
    var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = value.translation.width
            }
            .onEnded { value in
                let width = UIScreen.main.bounds.width
                if value.translation.width < -width * 0.3 {
                    // Swipe left - mark for deletion
                    moveToDeleteAlbum()
                }
                
                // Reset position and load next image
                withAnimation {
                    offset = 0
                }
                loadRandomImage()
            }
    }
    
    var body: some View {
        Group {
            if isPhotoAccessGranted {
                VStack {
                    Text("Photo Deleter")
                        .font(.title)
                        .padding()
                    
                    if let image = currentImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 400)
                            .offset(x: offset)
                            .gesture(dragGesture)
                    } else {
                        Text("No photos available")
                            .foregroundColor(.gray)
                    }
                    
                    HStack {
                        Text("← Swipe left to delete")
                            .foregroundColor(.gray)
                        Spacer()
                        Text("Swipe right to keep →")
                            .foregroundColor(.gray)
                    }
                    .padding()
                }
            } else {
                VStack {
                    Text("Requesting Photo Access...")
                        .font(.title)
                    ProgressView()
                }
            }
        }
        .onAppear {
            requestPhotoAccess()
        }
    }
    
    private func requestPhotoAccess() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                isPhotoAccessGranted = status == .authorized
                if isPhotoAccessGranted {
                    loadRandomImage()
                }
            }
        }
    }
    
    private func loadRandomImage() {
        // Create fetch options
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        
        // Fetch all photos
        let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        guard allPhotos.count > 0 else {
            self.currentImage = nil
            return
        }
        
        // Get a random index
        let randomIndex = Int.random(in: 0..<allPhotos.count)
        let asset = allPhotos.object(at: randomIndex)
        
        // Request image
        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = false
        requestOptions.deliveryMode = .highQualityFormat
        
        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 800, height: 800), // Reasonable size for display
            contentMode: .aspectFit,
            options: requestOptions
        ) { image, info in
            DispatchQueue.main.async {
                self.currentImage = image
            }
        }
    }
    
    private func moveToDeleteAlbum() {
        // TODO: Implement moving current image to 'to-delete' album
    }
}

#Preview {
    ContentView()
}
