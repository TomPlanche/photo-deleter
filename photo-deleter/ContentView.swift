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
private let PROCESSED_PHOTOS_KEY = "ProcessedPhotoIds"

/// Main view states to control the app flow
private enum AppState {
    case welcome
    case processing
    case finished
}

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
    @State private var appState: AppState = .welcome
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
    
    /// Set of photo identifiers that have already been processed
    @State private var processedPhotoIds: Set<String> = Set(UserDefaults.standard.stringArray(forKey: PROCESSED_PHOTOS_KEY) ?? [])
    
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
        let minimumActionDistance: CGFloat = 75 // Minimum distance between action is recognized
        let response = 0.3
        let dampingFraction: CGFloat = 0.6
        
        
        return DragGesture()
            .onChanged { value in
                withAnimation(.interactiveSpring(response: response, dampingFraction: dampingFraction)) {
                    offset = value.translation.width
                }
                
            }
            .onEnded { value in
                // Only process the gesture if minimum distance was reached
                if abs(value.translation.width) >= minimumActionDistance {
                    
                    if (value.translation.width < 0) {
                        moveToDeleteAlbum()
                    }
                    
                    stats.totalProcessed += 1
                    loadRandomImage()
                }
                
                withAnimation(.spring(response: response, dampingFraction: dampingFraction)) {
                    offset = 0
                }
            }
    }
    
    var body: some View {
        Group {
            if isPhotoAccessGranted {
                switch appState {
                case .welcome:
                    WelcomeView(startProcessing: {
                        appState = .processing
                        loadRandomImage()
                    })
                case .processing:
                    mainProcessingView
                case .finished:
                    SummaryView(stats: stats)
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
    
    /// The main photo processing interface
    private var mainProcessingView: some View {
        VStack {
            Text("Photo Deleter")
                .font(.title)
                .padding()
            
            Spacer()
            
            if let image = currentImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 400)
                    .offset(x: offset)
                    .rotationEffect(.degrees(Double(offset) / 40))
                    .scaleEffect(1.0 - abs(Double(offset)) / 4000)
                    .gesture(dragGesture)
                    .overlay(
                        ZStack {
                            // Delete icon (appears when dragging left)
                            Image(systemName: "trash.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.red)
                                .opacity(offset < -20 ? -Double(offset) / 200 : 0)
                                .offset(x: -40)
                            
                            // Keep icon (appears when dragging right)
                            Image(systemName: "heart.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.green)
                                .opacity(offset > 20 ? Double(offset) / 200 : 0)
                                .offset(x: 40)
                            
                            // Photo counter overlay
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Text("Photo \(processedPhotoIds.count)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(Color.black.opacity(0.6))
                                        )
                                        .padding(8)
                                }
                            }
                        }
                    )
            } else {
                Text("No photos available")
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Modern progress indicator with total
            HStack(spacing: 8) {
                Image(systemName: "photo.stack")
                    .foregroundColor(.blue)
                Text("\(stats.totalProcessed)/\(totalPhotosCount)")
                    .fontWeight(.semibold)
                Text("processed")
            }
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.blue.opacity(0.1))
            )
            .padding(.bottom)
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
    
    /// Loads a random unprocessed photo from the photo library
    private func loadRandomImage(retryCount: Int = 0) {
        let maxRetries = 3
        
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
        
        // Get all unprocessed photos
        let unprocessedPhotos = (0..<allPhotos.count).compactMap { index -> PHAsset? in
            let asset = allPhotos.object(at: index)
            return processedPhotoIds.contains(asset.localIdentifier) ? nil : asset
        }
        
        guard !unprocessedPhotos.isEmpty else {
            appState = .finished
            return
        }
        
        // Get a random unprocessed photo
        let randomAsset = unprocessedPhotos.randomElement()!
        currentAsset = randomAsset
        processedPhotoIds.insert(randomAsset.localIdentifier)
        
        // Save to UserDefaults
        UserDefaults.standard.set(Array(processedPhotoIds), forKey: PROCESSED_PHOTOS_KEY)
        
        // Request image
        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = false
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.isNetworkAccessAllowed = true
        
        imageManager.requestImage(
            for: randomAsset,
            targetSize: CGSize(width: 800, height: 800),
            contentMode: .aspectFit,
            options: requestOptions
        ) { image, info in
            DispatchQueue.main.async {
                if let error = info?[PHImageErrorKey] as? Error {
                    print("Error loading image: \(error.localizedDescription)")
                    
                    // If we haven't exceeded max retries, try loading another image
                    if retryCount < maxRetries {
                        print("Retrying with different image (attempt \(retryCount + 1)/\(maxRetries))")
                        self.loadRandomImage(retryCount: retryCount + 1)
                    } else {
                        // Skip problematic image after max retries
                        print("Skipping problematic image after \(maxRetries) attempts")
                        self.stats.totalProcessed += 1
                        self.loadRandomImage(retryCount: 0)
                    }
                } else if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                    print("Image loading was cancelled")
                    self.loadRandomImage(retryCount: retryCount)
                } else if let image = image {
                    self.currentImage = image
                } else {
                    // If we get here, we have no error but also no image
                    print("No image data available")
                    if retryCount < maxRetries {
                        self.loadRandomImage(retryCount: retryCount + 1)
                    } else {
                        self.stats.totalProcessed += 1
                        self.loadRandomImage(retryCount: 0)
                    }
                }
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
    
    /// Computed property to get the total number of unprocessed photos
    private var totalPhotosCount: Int {
        let fetchOptions = PHFetchOptions()
        if let toDeleteAlbum = findToDeleteAlbum() {
            let toDeletePhotos = PHAsset.fetchAssets(in: toDeleteAlbum, options: nil)
            let notInToDelete = "NOT (localIdentifier IN %@)"
            let identifiers = (0..<toDeletePhotos.count).compactMap { 
                toDeletePhotos.object(at: $0).localIdentifier 
            }
            fetchOptions.predicate = NSPredicate(format: notInToDelete, identifiers)
        }
        let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        return allPhotos.count
    }
    
    /// Helper method to find the "To Delete" album
    private func findToDeleteAlbum() -> PHAssetCollection? {
        let albumsFetchResult = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: nil
        )
        
        var toDeleteAlbum: PHAssetCollection?
        albumsFetchResult.enumerateObjects { collection, _, stop in
            if collection.localizedTitle == TO_DELETE_ALBUM_NAME {
                toDeleteAlbum = collection
                stop.pointee = true
            }
        }
        return toDeleteAlbum
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
        VStack(spacing: 40) {
            // Success Icon and Title
            VStack(spacing: 15) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
                
                Text("All Done!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Your photos have been organized")
                    .font(.title3)
                    .foregroundColor(.gray)
            }
            
            // Statistics Cards
            VStack(spacing: 15) {
                StatCard(
                    icon: "photo.stack",
                    title: "Total Processed",
                    value: stats.totalProcessed,
                    color: .blue
                )
                
                StatCard(
                    icon: "trash.circle",
                    title: "Marked for Deletion",
                    value: stats.markedForDeletion,
                    color: .red
                )
                
                StatCard(
                    icon: "heart.circle",
                    title: "Photos Kept",
                    value: stats.totalProcessed - stats.markedForDeletion,
                    color: .green
                )
            }
            .padding(.horizontal)
            
            // Open Album Button
            Link(destination: URL(string: "photos-redirect://")!) {
                HStack {
                    Image(systemName: "photo.stack.fill")
                    Text("Open Photos App")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(10)
            }
            .padding(.horizontal)
            
            Text("Review your marked photos in the '\(TO_DELETE_ALBUM_NAME)' album")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

/// A card displaying a statistic with an icon and color
private struct StatCard: View {
    let icon: String
    let title: String
    let value: Int
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                Text("\(value)")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            Spacer()
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

/// A row showing a numbered instruction
private struct InstructionRow: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(spacing: 15) {
            Text("\(number)")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.blue))
            
            Text(text)
                .font(.body)
            
            Spacer()
        }
    }
}

/// Welcome screen that explains the app's functionality
struct WelcomeView: View {
    let startProcessing: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "photo.stack.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Welcome to Photo Deleter")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 20) {
                FeatureRow(
                    icon: "photo.stack",
                    title: "Organize Your Photos",
                    description: "Quickly review your photo library and mark unwanted photos for deletion"
                )
                
                FeatureRow(
                    icon: "hand.draw",
                    title: "Simple Gestures",
                    description: "Swipe left to mark for deletion, right to keep"
                )
                
                FeatureRow(
                    icon: "folder",
                    title: "Safe Process",
                    description: "Photos are moved to a 'To Delete' album for your final review"
                )
            }
            .padding()
            
            Button(action: startProcessing) {
                Text("Start Organizing")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
        }
        .padding()
    }
}

/// A row showing a feature with an icon and description
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    ContentView()
}
