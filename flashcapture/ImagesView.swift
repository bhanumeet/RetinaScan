import SwiftUI
import Photos
import UIKit
import ImageIO
import UniformTypeIdentifiers

struct ImagesView: View {
    let images: [UIImage]
    let capturedMetadata: [CaptureMetadata]
    let onDone: () -> Void

    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var pressedIndex: Int? = nil
    @State private var saveName: String = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        ZStack {
            NavigationView {
                ScrollView {
                    VStack(spacing: 16) {
                        // Image grid
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(images.indices, id: \.self) { idx in
                                let img = images[idx]
                                Image(uiImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 100)
                                    .clipped()
                                    .overlay(
                                        // Preview overlay (shows what will be burned into image)
                                        VStack {
                                            HStack {
                                                Text(displayNameForFrame(idx + 1))
                                                    .font(.caption.bold())
                                                    .foregroundColor(.white)
                                                    .padding(4)
                                                    .background(Color.black.opacity(0.7))
                                                    .cornerRadius(4)
                                                Spacer()
                                            }
                                            Spacer()
                                        }
                                        .padding(4)
                                    )
                                    .onTapGesture {
                                        saveToGalleryWithMetadata(img, frameIndex: idx)
                                    }
                                    .onLongPressGesture(
                                        minimumDuration: 1.0,
                                        maximumDistance: 50,
                                        pressing: { isPressing in
                                            if !isPressing && pressedIndex == idx {
                                                pressedIndex = nil
                                            }
                                        },
                                        perform: {
                                            pressedIndex = idx
                                        }
                                    )
                            }
                        }
                        .padding(.horizontal)
                        
                        // Custom save name input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Save Name")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            TextField("Enter Text", text: $saveName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .autocapitalization(.words)
                                .disableAutocorrection(true)
                            
                            if !saveName.isEmpty {
                                Text("Images will be saved as: \(saveName)-1, \(saveName)-2, ..., \(saveName)-\(images.count)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                        }
                        .padding(.horizontal)
                        
                        // Save All button
                        Button(action: saveAllFramesWithMetadata) {
                            HStack {
                                Image(systemName: "square.and.arrow.down.fill")
                                Text(saveName.isEmpty ? "Save All Frames" : "Save All as '\(saveName)-#'")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack {
                            Text("Select Frames")
                                .font(.headline)
                            Text("Tap to save • Hold to enlarge")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            onDone()
                        }
                    }
                }
                .alert(alertMessage, isPresented: $showAlert) {
                    Button("OK", role: .cancel) { }
                }
            }

            // overlay enlarged image while pressing
            if let idx = pressedIndex {
                Color.black.opacity(0.8)
                    .ignoresSafeArea()
                VStack {
                    Text(displayNameForFrame(idx + 1))
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .padding(.bottom, 10)
                    
                    Image(uiImage: images[idx])
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(20)
                }
                .onTapGesture { }
            }
        }
    }
    
    // Helper function to generate display name for frames
    private func displayNameForFrame(_ frameNumber: Int) -> String {
        if saveName.isEmpty {
            return "\(frameNumber)"
        } else {
            return "\(saveName)-\(frameNumber)"
        }
    }

    // MARK: - Image Text Burning
    
    private func addTextToImage(_ image: UIImage, text: String) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        
        return renderer.image { context in
            // Draw the original image
            image.draw(at: .zero)
            
            // Configure text attributes
            let fontSize = max(image.size.width * 0.04, 24) // Responsive font size
            let font = UIFont.boldSystemFont(ofSize: fontSize)
            let textColor = UIColor.white
            let strokeColor = UIColor.black
            
            // Create text attributes with stroke for visibility
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
                .strokeColor: strokeColor,
                .strokeWidth: -3.0 // Negative for fill + stroke
            ]
            
            // Calculate text position (top-left with padding)
            let padding = max(image.size.width * 0.02, 10)
            let textRect = CGRect(
                x: padding,
                y: padding,
                width: image.size.width - (padding * 2),
                height: fontSize * 1.5
            )
            
            // Draw the text
            (text as NSString).draw(in: textRect, withAttributes: textAttributes)
        }
    }

    private func saveToGalleryWithMetadata(_ image: UIImage, frameIndex: Int) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    alertMessage = "Photo library access denied."
                    showAlert = true
                }
                return
            }

            guard frameIndex < capturedMetadata.count else {
                DispatchQueue.main.async {
                    alertMessage = "⚠️ No metadata available for this frame"
                    showAlert = true
                }
                return
            }
            
            let metadata = capturedMetadata[frameIndex]
            let customName = generateFileName(for: frameIndex + 1)
            
            // ADD TEXT TO IMAGE before saving
            let imageWithText = addTextToImage(image, text: customName)
            
            // Save with metadata AND caption
            saveImageWithEXIFAndCaption(image: imageWithText, metadata: metadata, customName: customName) { success, error in
                DispatchQueue.main.async {
                    if let err = error {
                        alertMessage = "⚠️ Save error: \(err.localizedDescription)"
                    } else if success {
                        alertMessage = "✅ Frame saved as '\(customName)' with text burned in!"
                    } else {
                        alertMessage = "⚠️ Unknown save error."
                    }
                    showAlert = true
                }
            }
        }
    }
    
    private func saveAllFramesWithMetadata() {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    alertMessage = "Photo library access denied."
                    showAlert = true
                }
                return
            }
            
            let baseNameForAlert = saveName.isEmpty ? "Frame" : saveName
            
            DispatchQueue.main.async {
                alertMessage = "🔥 Saving all \(images.count) frames as '\(baseNameForAlert)-#' with text burned in..."
                showAlert = true
            }
            
            var savedCount = 0
            var totalFrames = images.count
            
            // Save all frames with their metadata
            for (index, image) in images.enumerated() {
                if index < capturedMetadata.count {
                    let metadata = capturedMetadata[index]
                    let customName = generateFileName(for: index + 1)
                    
                    // ADD TEXT TO IMAGE before saving
                    let imageWithText = addTextToImage(image, text: customName)
                    
                    saveImageWithEXIFAndCaption(image: imageWithText, metadata: metadata, customName: customName) { success, error in
                        savedCount += 1
                        
                        if savedCount == totalFrames {
                            DispatchQueue.main.async {
                                if success {
                                    alertMessage = "✅ All \(totalFrames) frames saved as '\(baseNameForAlert)-#' with text burned in!"
                                } else {
                                    alertMessage = "⚠️ Some frames may not have saved correctly"
                                }
                                showAlert = true
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Generate filename based on user input
    private func generateFileName(for frameNumber: Int) -> String {
        if saveName.isEmpty {
            return "Frame-\(frameNumber)"
        } else {
            return "\(saveName)-\(frameNumber)"
        }
    }
    
    // MARK: - EXIF + Caption Saving
    
    private func saveImageWithEXIFAndCaption(image: UIImage, metadata: CaptureMetadata, customName: String, completion: @escaping (Bool, Error?) -> Void) {
        print("🔥 Saving frame \(metadata.frameNumber) as '\(customName)' with metadata - Focus: \(String(format: "%.3f", metadata.lensPosition))")
        
        // Convert image to JPEG data
        guard let jpegData = image.jpegData(compressionQuality: 0.95) else {
            completion(false, NSError(domain: "ImageConversion", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to JPEG"]))
            return
        }
        
        // Create image source from JPEG data
        guard let imageSource = CGImageSourceCreateWithData(jpegData as CFData, nil) else {
            completion(false, NSError(domain: "ImageSource", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create image source"]))
            return
        }
        
        // Get existing metadata (if any)
        let existingMetadata = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] ?? [:]
        let mutableMetadata = NSMutableDictionary(dictionary: existingMetadata)
        
        // Create timestamp
        let exifDateString = DateFormatter.exifDateFormatter.string(from: metadata.timestamp)
        
        // COMPREHENSIVE METADATA from captured moment
        var exifDict = mutableMetadata[kCGImagePropertyExifDictionary as String] as? NSMutableDictionary ?? NSMutableDictionary()
        
        // PRIMARY focus metadata - lens position as subject distance
        let focusDistance = calculateFocusDistance(from: metadata.lensPosition)
        exifDict[kCGImagePropertyExifSubjectDistance as String] = focusDistance
        
        // COMPREHENSIVE camera metadata from the frozen moment
        exifDict[kCGImagePropertyExifFocalLength as String] = Double(metadata.focalLength)
        exifDict[kCGImagePropertyExifFNumber as String] = Double(metadata.aperture)
        exifDict[kCGImagePropertyExifISOSpeedRatings as String] = [Int(metadata.iso)]
        exifDict[kCGImagePropertyExifExposureTime as String] = CMTimeGetSeconds(metadata.exposureDuration)
        
        // FOCUS metadata in multiple places for reliability
        exifDict[kCGImagePropertyExifUserComment as String] = "\(customName) | Focus: \(String(format: "%.3f", metadata.lensPosition)) | Distance: \(String(format: "%.2f", focusDistance))m | FL: \(String(format: "%.1f", metadata.focalLength))mm | f/\(String(format: "%.1f", metadata.aperture)) | ISO\(Int(metadata.iso)) | \(metadata.shutterSpeed)"
        
        // Additional focus-related fields
        exifDict[kCGImagePropertyExifSubjectArea as String] = [Int(image.size.width/2), Int(image.size.height/2), 100, 100]
        
        // Timestamps
        exifDict[kCGImagePropertyExifDateTimeOriginal as String] = exifDateString
        exifDict[kCGImagePropertyExifDateTimeDigitized as String] = exifDateString
        
        // Lens info
        exifDict[kCGImagePropertyExifLensModel as String] = "iPhone Wide"
        exifDict[kCGImagePropertyExifLensMake as String] = "Apple"
        
        mutableMetadata[kCGImagePropertyExifDictionary as String] = exifDict
        
        // Enhanced TIFF metadata with custom name AND caption
        var tiffDict = mutableMetadata[kCGImagePropertyTIFFDictionary as String] as? NSMutableDictionary ?? NSMutableDictionary()
        tiffDict[kCGImagePropertyTIFFMake as String] = "Apple"
        tiffDict[kCGImagePropertyTIFFModel as String] = UIDevice.current.model
        tiffDict[kCGImagePropertyTIFFSoftware as String] = "FlashCapture-Pro"
        tiffDict[kCGImagePropertyTIFFDateTime as String] = exifDateString
        
        // Set CAPTION in image description
        let caption = "\(customName) | Focus: \(String(format: "%.3f", metadata.lensPosition)) | Distance: \(String(format: "%.2f", focusDistance))m"
        tiffDict[kCGImagePropertyTIFFImageDescription as String] = caption
        
        mutableMetadata[kCGImagePropertyTIFFDictionary as String] = tiffDict
        
        // GPS metadata
        var gpsDict = mutableMetadata[kCGImagePropertyGPSDictionary as String] as? NSMutableDictionary ?? NSMutableDictionary()
        gpsDict[kCGImagePropertyGPSProcessingMethod as String] = "FlashCapture Focus Stack"
        mutableMetadata[kCGImagePropertyGPSDictionary as String] = gpsDict
        
        print("🎯 Complete metadata prepared: \(customName), Focus=\(String(format: "%.3f", metadata.lensPosition)), Caption=\(caption)")
        
        // Create output data
        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(outputData as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            completion(false, NSError(domain: "ImageDestination", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create destination"]))
            return
        }
        
        // Add image with comprehensive metadata
        if let cgImage = image.cgImage {
            CGImageDestinationAddImage(destination, cgImage, mutableMetadata as CFDictionary)
            
            if CGImageDestinationFinalize(destination) {
                print("✅ \(customName) processed with complete metadata and caption")
                
                // Save to Photos with caption using PHAssetCreationRequest
                PHPhotoLibrary.shared().performChanges({
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    creationRequest.addResource(with: .photo, data: outputData as Data, options: nil)
                    
                    // Set caption in Photos app
                    creationRequest.location = nil // No location
                    // Note: PHAssetCreationRequest doesn't have a direct caption property
                    // The caption will be in the TIFF metadata and can be viewed in Photos app details
                    
                }, completionHandler: { success, error in
                    if success {
                        print("✅ \(customName) saved with complete frozen metadata and caption")
                    } else {
                        print("❌ Failed to save \(customName): \(error?.localizedDescription ?? "unknown")")
                    }
                    completion(success, error)
                })
            } else {
                print("❌ Failed to finalize destination for \(customName)")
                completion(false, NSError(domain: "ImageFinalize", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize image destination"]))
            }
        } else {
            print("❌ No CGImage for \(customName)")
            completion(false, NSError(domain: "CGImage", code: 5, userInfo: [NSLocalizedDescriptionKey: "No CGImage available"]))
        }
    }
    
    // Convert lens position (0.0-1.0) to approximate focus distance in meters
    private func calculateFocusDistance(from lensPosition: Float) -> Double {
        if lensPosition <= 0.05 {
            return 999.0 // Infinity focus
        } else {
            let distance = Double(0.1 + (1.0 - lensPosition) * 10.0)
            return min(max(distance, 0.1), 999.0)
        }
    }
}

// MARK: - DateFormatter Extension
private extension DateFormatter {
    static let exifDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter
    }()
}
