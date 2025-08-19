//
//  PhotoView.swift
//  flashcapture
//
//  Created by Luo Lab on 5/16/25.
//

import SwiftUI
import AVFoundation
import UIKit

// MARK: – PhotoView

struct PhotoView: View {
    @StateObject private var photoService = PhotoService()
    @State private var showGallery = false

    var body: some View {
        ZStack {
            // Live preview using our new PhotoPreviewView
            PhotoPreviewView(session: photoService.session)
                .ignoresSafeArea()

            // Capture button
            VStack {
                Spacer()
                Button(action: { photoService.startBurstCapture() }) {
                    Image(systemName: "camera.circle.fill")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.white)
                }
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            photoService.configureSession()
        }
        .onChange(of: photoService.capturedImages.count) { count in
            if count == PhotoService.targetPhotoCount {
                showGallery = true
            }
        }
        .sheet(isPresented: $showGallery) {
            // Create dummy metadata for photos since PhotoService doesn't capture real metadata
            ImagesView(
                images: photoService.capturedImages,
                capturedMetadata: createDummyMetadata(for: photoService.capturedImages)
            ) {
                showGallery = false
            }
        }
    }
    
    // Create basic metadata for photo burst
    private func createDummyMetadata(for images: [UIImage]) -> [CaptureMetadata] {
        return images.enumerated().map { index, _ in
            CaptureMetadata(
                focalLength: 26.0, // iPhone wide camera
                aperture: 1.8,     // iPhone wide camera
                iso: 100.0,        // Default
                shutterSpeed: "1/4", // Quarter second as set in PhotoService
                exposureDuration: CMTime(value: 1, timescale: 4), // Quarter second
                lensPosition: 0.5, // Auto focus
                zoomFactor: 1.0,   // No zoom
                frameNumber: index + 1
            )
        }
    }
}

// MARK: – PhotoPreviewView

/// A simple UIViewRepresentable that shows its AVCaptureSession
struct PhotoPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PhotoPreviewUIView {
        let view = PhotoPreviewUIView()
        let layer = view.videoPreviewLayer
        layer.session = session
        layer.videoGravity = .resizeAspectFill
        layer.connection?.videoOrientation = .portrait
        return view
    }

    func updateUIView(_ uiView: PhotoPreviewUIView, context: Context) {
        // nothing
    }
}

/// Backing UIView for PhotoPreviewView
class PhotoPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer.frame = bounds
    }
}

// MARK: – PhotoService

final class PhotoService: NSObject, ObservableObject {
    static let targetPhotoCount = 20

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var captureIndex = 0

    @Published var capturedImages: [UIImage] = []

    func configureSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { self.setupSession() }
            }
        case .authorized:
            setupSession()
        default:
            break
        }
    }

    private func setupSession() {
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                 for: .video,
                                                 position: .back),
            let input = try? AVCaptureDeviceInput(device: device)
        else { return }

        session.beginConfiguration()
        if session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
        }
        session.commitConfiguration()

        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
        }
    }

    func startBurstCapture() {
        capturedImages = []
        captureIndex = 0
        toggleTorch(on: false)      // ensure torch off for first half
        captureNext()
    }

    private func captureNext() {
        guard captureIndex < Self.targetPhotoCount else {
            toggleTorch(on: false)  // turn off torch at end
            return
        }

        // when we hit half-way, turn torch on for next shots
        if captureIndex == Self.targetPhotoCount / 2 {
            toggleTorch(on: true)
        }

        let settings = AVCapturePhotoSettings()
        settings.isHighResolutionPhotoEnabled = true
        settings.flashMode = .off   // we'll use torch instead

        // custom 1/4 second exposure
        if let device = currentDevice(),
           device.isExposureModeSupported(.custom) {
            do {
                try device.lockForConfiguration()
                let quarterSec = CMTime(value: 1, timescale: 4)
                let iso = device.iso
                device.setExposureModeCustom(
                    duration: quarterSec,
                    iso: iso,
                    completionHandler: nil
                )
                device.unlockForConfiguration()
            } catch {
                print("Exposure config failed: \(error)")
            }
        }

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func currentDevice() -> AVCaptureDevice? {
        session.inputs
            .compactMap { ($0 as? AVCaptureDeviceInput)?.device }
            .first
    }

    private func toggleTorch(on: Bool) {
        guard let device = currentDevice(), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            print("Torch error: \(error)")
        }
    }
}

// MARK: – AVCapturePhotoCaptureDelegate

extension PhotoService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let data = photo.fileDataRepresentation(),
           let image = UIImage(data: data) {
            DispatchQueue.main.async {
                self.capturedImages.append(image)
            }
        }
        captureIndex += 1
        captureNext()
    }
}
