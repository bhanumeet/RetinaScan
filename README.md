# FlashCapture App

**A specialized iOS camera app for ophthalmology research and clinical documentation of red reflex examination.**

<img width="1536" height="1024" alt="Medical Photography Session with Doctor and Patient" src="https://github.com/user-attachments/assets/e61c2c3e-0b53-432d-bae3-d4df7e2cc2cb" />



**Feature Overview:**
- **Precise Focus Control:** Lock focus at optimal distance for red reflex examination
- **Facial Auto Focus and Zoom:** Automatically recognises face and zooms to fill the screen
- **10 Frame Capture:** Takes 10 rapid frames (showing frames 4-9) to ensure perfect timing
- **Flash Synchronization:** Automatic torch/flash control for optimal red reflex illumination
- **Metadata Preservation:** Captures exact camera settings (focal length, aperture, ISO, focus distance) for clinical documentation
- **Hands-Free Operation:** Volume button trigger allows single-handed operation during examination and works with a Selfie stick

## Key Features

### 📸 **High-Speed Capture**
- Captures 10 frames in rapid succession
- Displays the middle 6 frames (4-9) for best quality selection
- 4K60 video format for maximum image quality
- Automatic torch activation during capture sequence

### 🎯 **Advanced Focus Control**
- **Focus Lock:** Tap the lock icon to maintain consistent focus distance
- **Tap-to-Focus:** Touch screen to set focus point (when unlocked)
- **Real-time Focus Display:** Shows exact lens position (0.000-1.000 scale)
- **Focus Distance Calculation:** Converts lens position to approximate distance in meters

### Face Detection & Auto-Zoom (YOLOv8 Face Detection)**
- Uses YOLOv8 face detection model (`yolov8s-face-lindevs.mlmodelc`)
- Automatically detects and zooms to patient's face
- Calculates optimal zoom level based on face bounding box
- Zooms until face touches frame edges, then pulls back to 75% for optimal framing
- Toggle on/off with the smile face icon

### 📊 **Comprehensive Camera Metadata**
- **Live Display:** Real-time camera settings overlay
  - Focal Length (mm)
  - Aperture (f-stop)
  - ISO sensitivity
  - Shutter Speed
  - Focus Position
  - Zoom Factor
- **EXIF Preservation:** All metadata frozen at capture moment and embedded in saved images

### 🎛️ **Professional Controls**
- **Volume Button Trigger:** Use hardware volume buttons for hands-free capture
- **Zoom Slider:** Vertical slider for precise zoom control
- **Format Selection:** Choose from available camera formats (resolution/frame rate)
- **Gesture Controls:** Tap and hold to enlarge image preview

### 💾 **Advanced Image Management**
- **Custom Naming:** Add text labels that get burned into images
- **Batch Save:** Save all frames with sequential naming
- **Rich Metadata Export:** EXIF data includes focus distance, camera settings, and custom descriptions
- **Gallery Integration:** Direct save to iOS Photos with complete metadata

## Simple User Interface


### Controls Legend
- **🔒 Focus Lock:** Toggle focus lock on/off
- **⚙️ Format:** Select video format (resolution/frame rate)
- **😊 Auto-Zoom:** Enable/disable AI face detection and auto-zoom
- **📷 Capture:** Start burst capture sequence
- **Volume Buttons:** Alternative capture trigger (hands-free)

## Technical Implementation

### Core Technologies
- **SwiftUI:** Modern iOS interface with camera integration
- **AVFoundation:** Professional camera control and video capture
- **CoreML + Vision:** YOLOv8 face detection for auto-zoom
- **CoreImage:** Real-time image processing
- **PhotoKit:** Gallery integration with metadata preservation

### Camera Pipeline
1. **Session Setup:** 4K60 format selection for maximum quality
2. **Real-time Processing:** Continuous camera info updates (5Hz)
3. **AI Processing:** Face detection runs on separate queue
4. **Burst Capture:** 10-frame sequence with torch control
5. **Metadata Freezing:** Camera settings captured at trigger moment
6. **EXIF Embedding:** Complete metadata written to image files

### Face Detection Details (YOLOv8)
```swift
// Model: yolov8s-face-lindevs.mlmodelc
// Input: Live camera feed (CVPixelBuffer)
// Output: Face bounding boxes with confidence scores
// Processing: Separate vision queue for performance
// Auto-zoom calculation:
let zoom = min(max(1/rect.width, 1/rect.height) * 0.50, maxZoom)
```

## Installation & Setup

### Prerequisites
- iOS 14.0 or later
- iPhone with wide-angle camera
- Camera and Photos permissions
- Microphone permission (for volume button detection)

### Required Assets
- `camera` icon image
- `zoombar` background image  
- `zoomslider` thumb image
- `yolov8s-face-lindevs.mlmodelc` CoreML model

### Permissions Required
```xml
<key>NSCameraUsageDescription</key>
<string>FlashCapture needs camera access to capture red reflex images for medical examination.</string>

<key>NSPhotoLibraryAddUsageDescription</key>
<string>FlashCapture needs photo library access to save captured images with medical metadata.</string>

<key>NSMicrophoneUsageDescription</key>
<string>FlashCapture needs microphone access to detect volume button presses for hands-free capture.</string>
```

## Developer Notes

### Architecture Overview
```
flashcaptureApp.swift
└── VideoView (Main UI)
└── ImagesView (Gallery/Export)
```

### Key Classes & Responsibilities

#### `CameraService` (Core Engine) - [Inside VideoView]
- **Camera Management:** AVCaptureSession configuration and control
- **Volume Button Integration:** MPVolumeView monitoring for hardware triggers
- **AI Processing:** YOLOv8 face detection and auto-zoom logic
- **Metadata Capture:** Real-time camera info collection and freezing
- **Burst Logic:** 10-frame capture sequence with flash control

#### `VideoView` (Main Interface)
- **UI Orchestration:** Manages all camera controls and overlays
- **State Management:** Handles recording state, zoom levels, format selection
- **Navigation:** Presents gallery view when capture completes

#### `ImagesView` (Gallery & Export)
- **Image Review:** Grid display of captured frames
- **Custom Naming:** Text input for image labeling
- **Batch Processing:** Save all frames with sequential naming
- **Text Burning:** Overlay custom text directly onto images
- **EXIF Export:** Complete metadata embedding for clinical documentation

### Critical Implementation Details

#### Volume Button Detection
```swift
// Challenge: iOS doesn't provide direct volume button events
// Solution: Monitor MPVolumeView slider changes
// Maintains 50% volume level for bidirectional detection
// Automatic re-setup on app lifecycle changes
```

#### Metadata Freezing Strategy
```swift
// Problem: The frames are extracted from Video but saved as JPEG so real meta data cant be reteained 
// Solution: Capture metadata at trigger moment, apply to all frames
let captureStartMetadata = captureCurrentMetadata(for: 0)
// Each frame gets identical frozen metadata for consistency
```

#### Focus Distance Calculation
```swift
// Convert lens position (0.0-1.0) to approximate distance
private func calculateFocusDistance(from lensPosition: Float) -> Double {
    if lensPosition <= 0.05 {
        return 999.0 // Infinity focus
    } else {
        return 0.1 + (1.0 - lensPosition) * 10.0 // ~0.1m to 10m range
    }
}
```

### Performance Optimizations
- **Separate Queues:** Vision processing on dedicated queue
- **Efficient Updates:** Camera info updates at 5Hz (200ms intervals)
- **Memory Management:** Proper cleanup of observers and timers
- **Format Selection:** Prioritizes 4K60 for clinical quality


## Usage Instructions

#### Basic Red Reflex Capture
1. **Setup:** Open app and allow camera/photo permissions
2. **Focus:** Tap screen to focus on patient's eye and use focus lock
3. **Distance:** Position device on appropriate distance from patient
4. **Capture:** Press volume button or on-screen button, or use connected trigger or selfie stick button
5. **Review:** Select best frames from the 6 displayed options
6. **Save:** Add patient identifier and save selected frames

## Troubleshooting

### Common Issues

#### Volume Buttons Not Working
- Ensure microphone permission is granted
- Try closing and reopening the app
- Check iOS Do Not Disturb settings

#### Images Too Dark/Bright
- Adjust distance from patient 
- Use focus lock to maintain consistent settings
- Try different zoom levels for better exposure

#### Face Detection Not Working
- Ensure patient is facing camera directly
- Adequate lighting on face required
- Model may not detect faces at extreme angles
