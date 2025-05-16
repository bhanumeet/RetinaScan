import SwiftUI
import Photos
import UIKit

struct ImagesView: View {
    let images: [UIImage]
    let onDone: () -> Void

    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var pressedIndex: Int? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        ZStack {
            NavigationView {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(images.indices, id: \.self) { idx in
                            let img = images[idx]
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 100)
                                .clipped()
                                // tap to save
                                .onTapGesture {
                                    saveToGallery(img)
                                }
                                // long-press (1s) to enlarge; stays enlarged until release
                                .onLongPressGesture(
                                    minimumDuration: 1.0,
                                    maximumDistance: 50,
                                    pressing: { isPressing in
                                        if !isPressing && pressedIndex == idx {
                                            // finger lifted: reset
                                            pressedIndex = nil
                                        }
                                    },
                                    perform: {
                                        // after 1s hold: enlarge
                                        pressedIndex = idx
                                    }
                                )
                        }
                    }
                    .padding()
                }
                // Use inline nav bar with a subtitle
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

            // overlay enlarged image while pressing
            if let idx = pressedIndex {
                Color.black.opacity(0.8)
                    .ignoresSafeArea()
                Image(uiImage: images[idx])
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(20)
                    // consume touches
                    .onTapGesture { }
            }
        }
    }

    private func saveToGallery(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    alertMessage = "Photo library access denied."
                    showAlert = true
                }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if let err = error {
                        alertMessage = "⚠️ Save error: \(err.localizedDescription)"
                    } else if success {
                        alertMessage = "✅ Saved selected frame"
                    } else {
                        alertMessage = "⚠️ Unknown save error."
                    }
                    showAlert = true
                }
            }
        }
    }
}
