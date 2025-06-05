// ImagesView.swift

import SwiftUI
import Photos
import UIKit
import ImageIO
import UniformTypeIdentifiers

// MARK: – UIImage orientation fix
extension UIImage {
    /// Normalize orientation
    func fixedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return normalized
    }
}

struct ImagesView: View {
    let images: [UIImage]
    let metadata: [CFDictionary]
    let userISO: Float
    let userExposureDuration: Double
    let onDone: () -> Void

    @State private var prefix: String = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var pressedIndex: Int? = nil

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: 3
    )

    var body: some View {
        ZStack {
            NavigationView {
                VStack(spacing: 0) {
                    HStack {
                        TextField("Filename prefix", text: $prefix)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.horizontal)
                        Spacer()
                    }
                    .padding(.vertical, 8)

                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(images.indices, id: \.self) { idx in
                                Image(uiImage: images[idx])
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 100)
                                    .clipped()
                                    .onTapGesture {
                                        saveToGallery(images[idx], metadata: metadata[idx])
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
                        .padding(8)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack {
                            Text("Select Frames")
                                .font(.headline)
                            Text("Hold to enlarge")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { onDone() }
                    }
                }
                .alert(alertMessage, isPresented: $showAlert) {
                    Button("OK", role: .cancel) { }
                }
            }

            if let idx = pressedIndex {
                Color.black.opacity(0.8).ignoresSafeArea()
                Image(uiImage: images[idx])
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(20)
                    .onTapGesture { pressedIndex = nil }
            }
        }
    }

    private func saveToGallery(_ image: UIImage, metadata: CFDictionary) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    alertMessage = "Photo library access denied."
                    showAlert = true
                }
                return
            }

            let norm = image.fixedOrientation()
            guard let cgImage = norm.cgImage else {
                DispatchQueue.main.async {
                    alertMessage = "Failed to get CGImage."
                    showAlert = true
                }
                return
            }

            // Merge metadata & override Exif
            let mmd = NSMutableDictionary(dictionary: metadata)
            mmd[kCGImagePropertyOrientation as String] = 1

            let exifKey = kCGImagePropertyExifDictionary as String
            var exif = (mmd[exifKey] as? NSMutableDictionary) ?? NSMutableDictionary()
            exif[kCGImagePropertyExifExposureTime as String] = userExposureDuration
            exif[kCGImagePropertyExifISOSpeedRatings as String] = [Int(userISO)]
            mmd[exifKey] = exif

            let data = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(
                data as CFMutableData,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            ) else {
                DispatchQueue.main.async {
                    alertMessage = "Failed to create image destination."
                    showAlert = true
                }
                return
            }

            CGImageDestinationAddImage(dest, cgImage, mmd as CFDictionary)
            guard CGImageDestinationFinalize(dest) else {
                DispatchQueue.main.async {
                    alertMessage = "Failed to finalize image."
                    showAlert = true
                }
                return
            }

            let ts = Int(Date().timeIntervalSince1970)
            let name = prefix
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: " ", with: "_")
            let filename = name.isEmpty ? "IMG_\(ts).jpg" : "\(name)_\(ts).jpg"

            let opts = PHAssetResourceCreationOptions()
            opts.originalFilename = filename

            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, data: data as Data, options: opts)
            }) { success, error in
                DispatchQueue.main.async {
                    if let err = error {
                        alertMessage = "⚠️ Save error: \(err.localizedDescription)"
                    } else {
                        alertMessage = "✅ Saved “\(filename)”"
                    }
                    showAlert = true
                }
            }
        }
    }
}
