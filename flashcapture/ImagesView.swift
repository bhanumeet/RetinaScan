import SwiftUI
import Photos
import UIKit
import ImageIO
import UniformTypeIdentifiers

// MARK: – UIImage orientation fix
extension UIImage {
    /// Returns a copy of the image with its orientation normalized to .up
    func fixedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return normalizedImage
    }
}

struct ImagesView: View {
    let images: [UIImage]
    let metadata: [CFDictionary]
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
                    // ─── Text Input for Filename Prefix ─────────────────────────
                    HStack {
                        TextField("Filename prefix", text: $prefix)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.horizontal)
                        Spacer()
                    }
                    .padding(.vertical, 8)

                    // ─── Grid of Thumbnails ────────────────────────────────────
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(images.indices, id: \.self) { idx in
                                let img = images[idx]
                                Image(uiImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 100)
                                    .clipped()
                                    .onTapGesture {
                                        saveToGallery(img, metadata: metadata[idx])
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
                            Text("Hold an image to enlarge")
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

            // ─── Enlarged Image Overlay ────────────────────────────────
            if let idx = pressedIndex {
                Color.black.opacity(0.8)
                    .ignoresSafeArea()
                Image(uiImage: images[idx])
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(20)
                    .onTapGesture {
                        pressedIndex = nil
                    }
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

            // ─── Normalize orientation ───────────────────────────────
            let normalizedImage = image.fixedOrientation()
            guard let cgImage = normalizedImage.cgImage else {
                DispatchQueue.main.async {
                    alertMessage = "Failed to get CGImage."
                    showAlert = true
                }
                return
            }

            // ─── Prepare metadata ────────────────────────────────────
            let mutableMetadata = NSMutableDictionary(dictionary: metadata)
            mutableMetadata[kCGImagePropertyOrientation as String] = 1

            // ─── Create JPEG data ────────────────────────────────────
            let destData = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                destData as CFMutableData,
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
            CGImageDestinationAddImage(
                destination,
                cgImage,
                mutableMetadata as CFDictionary
            )
            guard CGImageDestinationFinalize(destination) else {
                DispatchQueue.main.async {
                    alertMessage = "Failed to finalize image."
                    showAlert = true
                }
                return
            }

            // ─── Use prefix for filename ─────────────────────────────
            let timestamp = Int(Date().timeIntervalSince1970)
            let filename: String
            if prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                filename = "IMG_\(timestamp).jpg"
            } else {
                // sanitize prefix: remove spaces/newlines
                let safePrefix = prefix
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: " ", with: "_")
                filename = "\(safePrefix)_\(timestamp).jpg"
            }

            let creationOptions = PHAssetResourceCreationOptions()
            creationOptions.originalFilename = filename

            // ─── Save to Photo Library ───────────────────────────────
            PHPhotoLibrary.shared().performChanges({
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(
                    with: .photo,
                    data: destData as Data,
                    options: creationOptions
                )
            }) { success, error in
                DispatchQueue.main.async {
                    if let error = error {
                        alertMessage = "⚠️ Save error: \(error.localizedDescription)"
                    } else {
                        alertMessage = "✅ Saved “\(filename)” successfully."
                    }
                    showAlert = true
                }
            }
        }
    }
}
