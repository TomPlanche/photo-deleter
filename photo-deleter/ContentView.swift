//
//  ContentView.swift
//  photo-deleter
//
//  Created by Tom Planche on 22/01/2025.
//

import SwiftUI
import SwiftData
import Photos

/// Name of the album where photos marked for deletion will be stored
private let TO_DELETE_ALBUM_NAME = "To Delete"

/// A view that provides a Tinder-like interface for managing photos in the user's photo library.
///
/// This view allows users to:
/// - Browse through their photos sequentially
/// - Swipe left to mark photos for deletion (moves them to a "To Delete" album)
/// - Swipe right to keep photos
/// - View progress and completion statistics
///
/// The view handles photo library permissions and maintains state for:
/// - Current photo being displayed
/// - Processing statistics
/// - Permission status
/// - Completion status
struct ContentView: View {
    /// The currently displayed image
    @State private var currentImage: UIImage?
    
    /// Reference to the current photo asset being displayed
    @State private var currentAsset: PHAsset?
    
    /// The horizontal offset for the swipe animation
    @State private var offset: CGFloat = 0
    
    /// Indicates whether photo library access has been granted
    @State private var isPhotoAccessGranted = false
    
    /// Indicates whether all photos have been processed
    @State private var isFinished = false
    
    /// Statistics about the current processing session
    @State private var stats = ProcessingStats()
    
    /// Stores statistics about the photo processing session
    ///
    /// This struct maintains counts of:
    /// - Total photos processed
    /// - Photos marked for deletion
    struct ProcessingStats {
        /// The total number of photos that have been processed
        var totalProcessed: Int = 0
        
        /// The number of photos that have been marked for deletion
        var markedForDeletion: Int = 0
    }
    
    /// Handles the swipe gesture for photo management
    ///
    /// This gesture recognizer:
    /// - Tracks horizontal movement for the swipe animation
    /// - Triggers deletion when swiped left past threshold
    /// - Loads the next photo after any complete swipe
    ///
    /// - Returns: A gesture that handles the swipe interaction
    var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = value.translation.width
            }
            .onEnded { value in
                let width = UIScreen.main.bounds.width
                if value.translation.width < -width * 0.3 {
                    moveToDeleteAlbum()
                }
                
                // Reset position and load next image
                withAnimation {
                    offset = 0
                }
                stats.totalProcessed += 1
                loadRandomImage()
            }
    }
    
    var body: some View {
        Group {
            if isPhotoAccessGranted {
                if isFinished {
                    SummaryView(stats: stats)
                } else {
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
                        
                        Text("Processed: \(stats.totalProcessed)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
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
    
    /// Requests access to the photo library and initializes the app if granted
    /// - Note: This function is called automatically when the view appears
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
    
    /// Loads the next unprocessed photo from the photo library
    ///
    /// This function:
    /// - Fetches photos sorted by creation date
    /// - Excludes photos from the "To Delete" album
    /// - Loads the photo at the current processing index
    /// - Updates the UI with the loaded image
    /// - Sets completion status when all photos are processed
    ///
    /// - Note: This function will set isFinished to true when all photos have been processed
    ///
    /// - Important: This method requires photo library access to be granted
    private func loadRandomImage() {
        // Find the "To Delete" album
        var toDeleteAlbum: PHAssetCollection?
        
        let albumsFetchResult = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: nil
        )
        
        albumsFetchResult.enumerateObjects { collection, _, stop in
            if collection.localizedTitle == TO_DELETE_ALBUM_NAME {
                toDeleteAlbum = collection
                stop.pointee = true
            }
        }
        
        // Create fetch options for all photos
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        
        // If we found the to-delete album, exclude its photos
        if let toDeleteAlbum = toDeleteAlbum {
            let toDeletePhotos = PHAsset.fetchAssets(in: toDeleteAlbum, options: nil)
            let notInToDelete = "NOT (localIdentifier IN %@)"
            let identifiers = (0..<toDeletePhotos.count).compactMap { 
                toDeletePhotos.object(at: $0).localIdentifier 
            }
            fetchOptions.predicate = NSPredicate(format: notInToDelete, identifiers)
        }
        
        // Fetch all photos except those in to-delete album
        let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        guard allPhotos.count > stats.totalProcessed else {
            isFinished = true
            return
        }
        
        // Get next unprocessed photo
        let asset = allPhotos.object(at: stats.totalProcessed)
        currentAsset = asset
        
        // Request image
        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = false
        requestOptions.deliveryMode = .highQualityFormat
        
        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 800, height: 800),
            contentMode: .aspectFit,
            options: requestOptions
        ) { image, info in
            DispatchQueue.main.async {
                self.currentImage = image
            }
        }
    }
    
    /// Moves the current photo to the "To Delete" album
    ///
    /// This function will:
    /// 1. Find the "To Delete" album if it exists
    /// 2. Create the album if it doesn't exist
    /// 3. Add the current photo to the album
    /// 4. Update deletion statistics
    ///
    /// - Note: Creates the album if it doesn't exist
    ///
    /// - Important: This operation requires write access to the photo library
    ///
    /// - SeeAlso: ``addAssetToAlbum``
    private func moveToDeleteAlbum() {
        guard let asset = currentAsset else { return }
        
        // Find or create the "To Delete" album
        var toDeleteAlbum: PHAssetCollection?
        
        // Try to find existing album
        let albumsFetchResult = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: nil
        )
        
        albumsFetchResult.enumerateObjects { collection, _, stop in
            if collection.localizedTitle == TO_DELETE_ALBUM_NAME {
                toDeleteAlbum = collection
                stop.pointee = true
            }
        }
        
        // If album doesn't exist, create it
        if toDeleteAlbum == nil {
            PHPhotoLibrary.shared().performChanges({
                PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: TO_DELETE_ALBUM_NAME)
            }) { success, error in
                if success {
                    print("SUCCESS: Created 'To Delete' album")
                    
                    // Fetch the newly created album
                    let collections = PHAssetCollection.fetchAssetCollections(
                        with: .album,
                        subtype: .albumRegular,
                        options: nil
                    )
                    collections.enumerateObjects { collection, _, stop in
                        if collection.localizedTitle == TO_DELETE_ALBUM_NAME {
                            toDeleteAlbum = collection
                            stop.pointee = true
                        }
                    }
                    // Add the asset to the new album
                    self.addAssetToAlbum(asset: asset, album: toDeleteAlbum)
                } else if let error = error {
                    print("Error creating album: \(error.localizedDescription)")
                }
            }
        } else {
            print("ALREADY EXISTS: 'To Delete' album")
            // Album exists, add the asset to it
            addAssetToAlbum(asset: asset, album: toDeleteAlbum)
        }
        
        stats.markedForDeletion += 1
    }
    
    /// Adds a photo asset to a specified album
    ///
    /// - Parameters:
    ///   - asset: The photo asset to add to the album
    ///   - album: The destination album. If nil, the operation is skipped
    ///
    /// - Note: This operation is performed asynchronously
    ///
    /// - Important: This operation requires write access to the photo library
    private func addAssetToAlbum(asset: PHAsset, album: PHAssetCollection?) {
        guard let album = album else { return }
        
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCollectionChangeRequest(for: album)
            request?.addAssets([asset] as NSFastEnumeration)
        }) { success, error in
            if !success, let error = error {
                print("Error adding asset to album: \(error.localizedDescription)")
            }
        }
    }
}

/// A view that displays statistics after all photos have been processed
///
/// This view shows:
/// - Total number of photos processed
/// - Number of photos marked for deletion
/// - Number of photos kept
/// - Instructions for finding marked photos
struct SummaryView: View {
    /// Statistics about the completed photo processing session
    let stats: ContentView.ProcessingStats
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Processing Complete!")
                .font(.title)
                .padding()
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Total photos processed: \(stats.totalProcessed)")
                Text("Photos marked for deletion: \(stats.markedForDeletion)")
                Text("Photos kept: \(stats.totalProcessed - stats.markedForDeletion)")
            }
            .padding()
            
            Text("You can find photos marked for deletion in the 'To Delete' album")
                .multilineTextAlignment(.center)
                .padding()
                .foregroundColor(.gray)
        }
    }
}

#Preview {
    ContentView()
}
