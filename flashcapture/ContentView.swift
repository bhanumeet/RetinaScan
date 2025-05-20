import SwiftUI
import AVFoundation
import Photos
import CoreImage
import CoreMedia
import UIKit
import CoreML
import Vision
import AVKit
import ImageIO

// MARK: – ContentView

struct ContentView: View {
    @StateObject private var cameraService = CameraService()
    @State private var showImagesView = false
    @State private var zoomLevel: Float = 1.0

    var body: some View {
        ZStack {
            // Live preview
            PreviewView(session: cameraService.session,
                        cameraService: cameraService)
                .ignoresSafeArea()

            // Top controls: focus-lock, auto-zoom
            VStack {
                HStack {
                    // Focus-lock
                    Button(action: cameraService.toggleFocusLock) {
                        Image(systemName: cameraService.isFocusLocked
                              ? "lock.fill" : "lock.open")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding(.leading, 8)

                    // Auto-Zoom toggle
                    Button(action: cameraService.toggleAutoZoom) {
                        Image(systemName: cameraService.isAutoZoomEnabled
                              ? "face.smiling.fill" : "face.smiling")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding(.leading, 8)

                    Spacer()
                }
                Spacer()
            }
            .padding(.top, 16)
            .padding(.horizontal, 16)

            // Zoom slider (right)
            HStack {
                Spacer()
                ZoomControl(zoomLevel: $zoomLevel,
                            minZoom: cameraService.minZoom,
                            maxZoom: cameraService.maxZoom) { newValue in
                    cameraService.setZoomFactor(CGFloat(newValue))
                }
                .frame(width: 44, height: 200)
                .padding(.trailing, 16)
            }

            // Capture Live Photo / Frame-capture button (bottom)
            VStack {
                Spacer()
                Button(action: cameraService.captureLivePhoto) {
                    Image("camera")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .background(Circle().fill(Color.white.opacity(0.7)))
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.bottom, 30)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            cameraService.startRecordingFrames()
                        }
                )
            }
        }
        .onAppear {
            cameraService.configureSession()
            zoomLevel = cameraService.currentZoomFactor
        }
        .onReceive(NotificationCenter.default.publisher(
                     for: CameraService.ZoomChangedNotification
                  )) { notif in
            if let z = notif.object as? Float {
                zoomLevel = z
            }
        }
        .onChange(of: cameraService.capturedImages.count) { newCount in
            if newCount > 0 {
                showImagesView = true
            }
        }
        .sheet(isPresented: $showImagesView) {
            ImagesView(images: cameraService.capturedImages,
                     metadata: cameraService.capturedMetadata) {
                showImagesView = false
            }
        }
    }
}

// MARK: – ZoomControl

struct ZoomControl: UIViewRepresentable {
    @Binding var zoomLevel: Float
    let minZoom: Float
    let maxZoom: Float
    var onZoomChanged: (Float) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        let bar = UIImageView(image: UIImage(named: "zoombar"))
        bar.contentMode = .scaleToFill
        bar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bar)

        let slider = UISlider()
        slider.minimumValue = minZoom
        slider.maximumValue = maxZoom
        slider.value = zoomLevel
        if let thumb = UIImage(named: "zoomslider") {
            slider.setThumbImage(thumb, for: .normal)
            slider.setThumbImage(thumb, for: .highlighted)
        }
        slider.minimumTrackTintColor = .clear
        slider.maximumTrackTintColor = .clear
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.addTarget(context.coordinator,
                         action: #selector(Coordinator.valueChanged(_:)),
                         for: .valueChanged)
        container.addSubview(slider)

        NSLayoutConstraint.activate([
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            bar.widthAnchor.constraint(equalToConstant: 44),
            bar.heightAnchor.constraint(equalToConstant: 200),

            slider.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            slider.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            slider.widthAnchor.constraint(equalTo: bar.heightAnchor),
            slider.heightAnchor.constraint(equalToConstant: 22),
        ])
        slider.transform = CGAffineTransform(rotationAngle: -CGFloat.pi / 2)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let slider = uiView.subviews.compactMap({ $0 as? UISlider }).first,
           slider.value != zoomLevel {
            slider.value = zoomLevel
        }
    }

    class Coordinator: NSObject {
        var parent: ZoomControl
        init(_ parent: ZoomControl) { self.parent = parent }
        @objc func valueChanged(_ sender: UISlider) {
            parent.zoomLevel = sender.value
            parent.onZoomChanged(sender.value)
        }
    }
}

// MARK: – PreviewView

struct PreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let cameraService: CameraService

    func makeCoordinator() -> PreviewCoordinator {
        PreviewCoordinator(cameraService: cameraService)
    }

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        let layer = view.videoPreviewLayer
        layer.session = session
        layer.videoGravity = .resizeAspectFill
        layer.connection?.videoOrientation = .portrait

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(PreviewCoordinator.handleTap(_:))
        )
        view.addGestureRecognizer(tap)
        view.isUserInteractionEnabled = true
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    class PreviewCoordinator: NSObject {
        let cameraService: CameraService
        init(cameraService: CameraService) {
            self.cameraService = cameraService
        }
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard !cameraService.isFocusLocked,
                  let view = gesture.view else { return }
            let pt = gesture.location(in: view)
            let size = view.bounds.size
            cameraService.focus(at: CGPoint(x: pt.x/size.width,
                                            y: pt.y/size.height))
        }
    }
}

class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer.frame = bounds
    }
}

// MARK: – CameraService

final class CameraService: NSObject, ObservableObject {
    static let ZoomChangedNotification = Notification.Name("CameraServiceZoomChanged")
    static let targetFrameCount = 20

    @Published var capturedImages: [UIImage] = []
    @Published var capturedMetadata: [CFDictionary] = []
    @Published var isFocusLocked = false
    @Published var isAutoZoomEnabled = false

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var detectionRequest: VNCoreMLRequest!
    private let visionQueue = DispatchQueue(label: "visionQueue")

    private var frameCount = 0
    private var isRecording = false

    var minZoom: Float { 1.0 }
    var maxZoom: Float {
        Float(currentDevice?.activeFormat.videoMaxZoomFactor ?? 5.0)
    }
    var currentZoomFactor: Float {
        Float(currentDevice?.videoZoomFactor ?? 1.0)
    }

    private var currentDevice: AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera, .builtInDualWideCamera,
            .builtInDualCamera, .builtInTelephotoCamera,
            .builtInUltraWideCamera, .builtInWideAngleCamera
        ]
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .back
        )
        return discovery.devices.max { a, b in
            CMVideoFormatDescriptionGetDimensions(a.activeFormat.formatDescription).width
                < CMVideoFormatDescriptionGetDimensions(b.activeFormat.formatDescription).width
        }
    }

    override init() {
        super.init()
        configureVision()
    }

    private func configureVision() {
        guard let url = Bundle.main.url(
                forResource: "yolov8s-face-lindevs",
                withExtension: "mlmodelc"
              ),
              let model = try? MLModel(contentsOf: url),
              let vmodel = try? VNCoreMLModel(for: model)
        else { return }
        detectionRequest = VNCoreMLRequest(model: vmodel,
                                           completionHandler: handleDetections)
        detectionRequest.imageCropAndScaleOption = .scaleFill
    }

    private func handleDetections(request: VNRequest, error: Error?) {
        guard isAutoZoomEnabled,
              error == nil,
              let results = request.results as? [VNRecognizedObjectObservation],
              let best = results.first(where: { $0.labels.first?.identifier == "face" })
        else { DispatchQueue.main.async { self.isAutoZoomEnabled = false }; return }

        DispatchQueue.main.async {
            let rect = best.boundingBox
            let target = min(
                max(Float(max(1/rect.width, 1/rect.height) * 0.5), self.minZoom),
                self.maxZoom
            )
            self.setZoomFactor(CGFloat(target))
            self.isAutoZoomEnabled = false
        }
    }

    func toggleAutoZoom() {
        DispatchQueue.main.async { self.isAutoZoomEnabled.toggle() }
    }

    func focus(at point: CGPoint) {
        guard let device = currentDevice,
              device.isFocusPointOfInterestSupported else { return }
        do {
            try device.lockForConfiguration()
            device.focusPointOfInterest = point
            device.focusMode = .autoFocus
            device.unlockForConfiguration()
        } catch { }
    }

    func toggleFocusLock() {
        guard let device = currentDevice else { return }
        do {
            try device.lockForConfiguration()
            if isFocusLocked {
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                isFocusLocked = false
            } else {
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                    device.focusMode = .locked
                }
                isFocusLocked = true
            }
            device.unlockForConfiguration()
        } catch { }
    }

    func setZoomFactor(_ factor: CGFloat) {
        guard let device = currentDevice else { return }
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = min(max(factor, 1.0),
                                         device.activeFormat.videoMaxZoomFactor)
            device.unlockForConfiguration()
            NotificationCenter.default.post(
                name: CameraService.ZoomChangedNotification,
                object: Float(device.videoZoomFactor)
            )
        } catch { }
    }

    func captureLivePhoto() {
        guard photoOutput.isLivePhotoCaptureSupported else {
            startRecordingFrames()
            return
        }
        capturedImages.removeAll()
        capturedMetadata.removeAll()

        let settings: AVCapturePhotoSettings
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(
                format: [AVVideoCodecKey: AVVideoCodecType.hevc]
            )
        } else {
            settings = AVCapturePhotoSettings()
        }
        settings.isHighResolutionPhotoEnabled = true
        settings.flashMode = .off
        let movieURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("live.mov")
        settings.livePhotoMovieFileURL = movieURL

        DispatchQueue.main.asyncAfter(deadline: .now()) { self.toggleTorch(on: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.toggleTorch(on: false) }

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

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
        PHPhotoLibrary.requestAuthorization { _ in }
    }

    private func setupSession() {
        guard let device = currentDevice else { return }
        session.beginConfiguration()

        // Use 4K video for ~8MP frames
        if session.canSetSessionPreset(.hd4K3840x2160) {
            session.sessionPreset = .hd4K3840x2160
        } else {
            session.sessionPreset = .high
        }

        // Photo output
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.isLivePhotoCaptureEnabled =
                photoOutput.isLivePhotoCaptureSupported
        }

        // Video output (for frame capture at 4K)
        if session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: visionQueue)
            session.addOutput(videoOutput)
            videoOutput.connection(with: .video)?
                .videoOrientation = .portrait
        }

        // Camera input
        if let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }

        session.commitConfiguration()
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
        }
    }

    func startRecordingFrames() {
        DispatchQueue.main.async {
            self.frameCount = 0
            self.capturedImages = []
            self.capturedMetadata = []
            self.isRecording = true
            self.toggleTorch(on: false)
        }
    }

    private func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> (UIImage, CFDictionary)? {
        guard let pix = CMSampleBufferGetImageBuffer(sampleBuffer),
              let metadata = CMCopyDictionaryOfAttachments(
                allocator: nil,
                target: sampleBuffer,
                attachmentMode: kCMAttachmentMode_ShouldPropagate
              ) else { return nil }
        
        let ci = CIImage(cvPixelBuffer: pix)
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return nil }
        
        // Create UIImage with proper orientation
        let image = UIImage(cgImage: cg, scale: 1.0, orientation: .right)
        
        return (image, metadata)
    }

    private func toggleTorch(on: Bool) {
        guard let device = currentDevice, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch { }
    }
}

// MARK: – AVCapturePhotoCaptureDelegate

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil else { return }
        
        if let metadata = photo.metadata as CFDictionary? {
            capturedMetadata.append(metadata)
        }
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL,
                     duration: CMTime,
                     photoDisplayTime: CMTime,
                     resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        defer { try? FileManager.default.removeItem(at: outputFileURL) }

        let asset = AVAsset(url: outputFileURL)
        guard let track = asset.tracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return }

        let opts: [String:Any] = [
            kCVPixelBufferPixelFormatTypeKey as String:
              kCVPixelFormatType_32BGRA
        ]
        let assetOutput = AVAssetReaderTrackOutput(
            track: track, outputSettings: opts
        )
        reader.add(assetOutput)
        reader.startReading()

        var imgs: [(UIImage, CFDictionary)] = []
        while let sample = assetOutput.copyNextSampleBuffer(),
              let result = imageFromSampleBuffer(sample) {
            imgs.append(result)
        }
        DispatchQueue.main.async {
            self.capturedImages = imgs.map { $0.0 }
            self.capturedMetadata = imgs.map { $0.1 }
        }
    }
}

// MARK: – AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if let pix = CMSampleBufferGetImageBuffer(sampleBuffer) {
            try? VNImageRequestHandler(
                cvPixelBuffer: pix,
                orientation: .right,
                options: [:]
            ).perform([detectionRequest])
        }

        guard isRecording else { return }
        frameCount += 1

        if frameCount == CameraService.targetFrameCount/2 {
            toggleTorch(on: true)
        } else if frameCount >= CameraService.targetFrameCount {
            toggleTorch(on: false)
            isRecording = false
        }

        if frameCount <= CameraService.targetFrameCount,
           let result = imageFromSampleBuffer(sampleBuffer) {
            DispatchQueue.main.async {
                self.capturedImages.append(result.0)
                self.capturedMetadata.append(result.1)
            }
        }
    }
}
