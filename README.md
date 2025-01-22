# Photo Deleter

A SwiftUI app that helps users efficiently organize their photo library using a Tinder-like swipe interface.

## Features

- 📱 Simple swipe-based interface for photo management
- 🗑️ Safe deletion process with a dedicated "To Delete" album
- 📊 Real-time statistics tracking
- 🔒 Privacy-focused with proper photo library permissions
- 💫 Smooth animations and intuitive gestures
- ✨ Modern iOS design patterns

## How It Works

1. **Permission**: The app requests access to your photo library
2. **Browse**: View your photos one at a time
3. **Organize**:
   - Swipe left to mark a photo for deletion
   - Swipe right to keep the photo
4. **Review**: Marked photos are moved to a "To Delete" album for final review
5. **Summary**: View statistics about your organizing session

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+
- Photo Library access

## Installation

1. Clone the repository
2. Open `photo-deleter.xcodeproj` in Xcode
3. Build and run the project on your iOS device or simulator

## Privacy

The app requires photo library access to function. All photo management happens locally on your device, and no photos are uploaded or shared externally.

## Technical Details

- Built with SwiftUI and PhotoKit
- Uses modern Swift concurrency
- Implements MVVM architecture
- Handles photo library permissions safely
- Includes error handling and retry logic
- Maintains state persistence for processed photos
