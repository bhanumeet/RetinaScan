// ContentView.swift

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
import MediaPlayer  // Added to handle volume button

// MARK: - Volume Button Handling

/// Observes volume button presses by KVO on AVAudioSession's outputVolume.
/// Triggers `onVolumeUp` when volume increases.
class VolumeObserver: NSObject {
    private var audioSession: AVAudioSession
    private var initialVolume: Float
    private let onVolumeUp: () -> Void

    init(onVolumeUp: @escaping () -> Void) {
        self.onVolumeUp = onVolumeUp
        self.audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(true)
        } catch {
            print("Failed to activate audio session: \(error)")
        }
        self.initialVolume = audioSession.outputVolume
        super.init()
        audioSession.addObserver(self, forKeyPath: "outputVolume", options: [.new], context: nil)
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey : Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard keyPath == "outputVolume",
              let newVol = (change?[.newKey] as? NSNumber)?.floatValue else {
            return
        }
        // If new volume is greater than previous, treat as volume-up press.
        if newVol > initialVolume {
            onVolumeUp()
        }
        initialVolume = newVol
    }

    deinit {
        audioSession.removeObserver(self, forKeyPath: "outputVolume")
    }
}

/// A hidden MPVolumeView so that the hardware volume HUD does not appear
/// when the user presses the volume buttons.
struct VolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.isHidden = true
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var cameraService = CameraService()
    @State private var showImagesView = false
    @State private var zoomLevel: Float = 1.0
    @State private var showSettings = false
    @State private var volumeObserver: VolumeObserver? = nil

    var body: some View {
        ZStack {
            // Live camera preview
            PreviewView(session: cameraService.session,
                        cameraService: cameraService)
                .ignoresSafeArea()

            // Top controls: focus, auto-zoom, settings
            VStack {
                HStack {
                    Button(action: cameraService.toggleFocusLock) {
                        Image(systemName: cameraService.isFocusLocked ? "lock.fill" : "lock.open")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding(.leading, 8)

                    Button(action: cameraService.toggleAutoZoom) {
                        Image(systemName: cameraService.isAutoZoomEnabled ? "face.smiling.fill" : "face.smiling")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding(.leading, 8)

                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
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

            // Zoom slider on the right
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

            // Capture / Live Photo button at the bottom
            VStack {
                Spacer()
                Button(action: {
                    cameraService.configureExposure()
                    cameraService.captureLivePhoto()
                }) {
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

            // Hidden volume view so system volume HUD stays hidden
            VolumeView()
        }
        .onAppear {
            cameraService.configureSession()
            zoomLevel = cameraService.currentZoomFactor

            // Initialize the volume observer to trigger camera capture on volume-up
            volumeObserver = VolumeObserver {
                cameraService.configureExposure()
                cameraService.captureLivePhoto()
            }
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
            ImagesView(
                images: cameraService.capturedImages,
                metadata: cameraService.capturedMetadata,
                userISO: cameraService.userISO,
                userExposureDuration: cameraService.userExposureDuration
            ) {
                showImagesView = false
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(cameraService: cameraService)
        }
        .onChange(of: showSettings) { shown in
            if !shown {
                cameraService.configureExposure()
            }
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject var cameraService: CameraService
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Exposure Duration (s)")) {
                    Slider(
                        value: $cameraService.userExposureDuration,
                        in: 0.05...0.30,
                        step: 0.05
                    ) {
                        Text("Duration")
                    }
                    Text(String(format: "%.4f s", cameraService.userExposureDuration))
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Section(header: Text("ISO")) {
                    Slider(
                        value: $cameraService.userISO,
                        in: cameraService.minISO...cameraService.maxISO,
                        step: 1
                    ) {
                        Text("ISO")
                    }
                    Text("\(Int(cameraService.userISO))")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .navigationBarTitle("Camera Settings", displayMode: .inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

// MARK: - ZoomControl

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

// MARK: - PreviewView

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
        init(cameraService: CameraService) { self.cameraService = cameraService }
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard !cameraService.isFocusLocked,
                  let view = gesture.view else { return }
            let pt = gesture.location(in: view)
            let size = view.bounds.size
            cameraService.focus(at: CGPoint(x: pt.x/size.width, y: pt.y/size.height))
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

// MARK: - CameraService

final class CameraService: NSObject, ObservableObject {
    static let ZoomChangedNotification = Notification.Name("CameraServiceZoomChanged")
    static let targetFrameCount = 20

    @Published var userExposureDuration: Double = 0.25
    @Published var userISO: Float = 160.0

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
    var maxZoom: Float { Float(currentDevice?.activeFormat.videoMaxZoomFactor ?? 5.0) }
    var currentZoomFactor: Float { Float(currentDevice?.videoZoomFactor ?? 1.0) }

    var minISO: Float { currentDevice?.activeFormat.minISO ?? 10.0 }
    var maxISO: Float { currentDevice?.activeFormat.maxISO ?? 6400.0 }

    private var currentDevice: AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        ).devices.first
    }

    override init() {
        super.init()
        configureVision()
    }

    private func configureVision() {
        guard let model = try? VNCoreMLModel(for: YOLOv8s_Face_Lindevs(configuration: .init()).model) else {
            print("Failed to load CoreML model")
            return
        }
        detectionRequest = VNCoreMLRequest(model: model, completionHandler: handleDetections)
        detectionRequest.imageCropAndScaleOption = .scaleFill
    }

    private func handleDetections(request: VNRequest, error: Error?) {
        guard isAutoZoomEnabled, error == nil,
              let results = request.results as? [VNRecognizedObjectObservation],
              let best = results.first(where: { $0.labels.first?.identifier == "face" }) else {
            DispatchQueue.main.async { self.isAutoZoomEnabled = false }
            return
        }
        DispatchQueue.main.async {
            let rect = best.boundingBox
            let target = min(max(Float(max(1/rect.width, 1/rect.height) * 0.75), self.minZoom), self.maxZoom)
            self.setZoomFactor(CGFloat(target))
            self.isAutoZoomEnabled = false
        }
    }

    func toggleAutoZoom() {
        DispatchQueue.main.async { self.isAutoZoomEnabled.toggle() }
    }

    func configureExposure() {
        guard let device = currentDevice else { return }
        let desiredDur = CMTimeMakeWithSeconds(userExposureDuration, preferredTimescale: 1_000_000)
        let desiredISO = userISO
        do {
            try device.lockForConfiguration()
            let minDur = device.activeFormat.minExposureDuration
            let maxDur = device.activeFormat.maxExposureDuration
            let clampedDur = min(max(desiredDur, minDur), maxDur)
            let minISO = device.activeFormat.minISO
            let maxISO = device.activeFormat.maxISO
            let clampedISO = max(minISO, min(desiredISO, maxISO))
            if device.isExposureModeSupported(.custom) {
                device.setExposureModeCustom(duration: clampedDur, iso: clampedISO) { _ in
                    print("🔧 Exposure: ISO \(clampedISO), \(clampedDur.seconds)s")
                }
            } else if device.isExposureModeSupported(.locked) {
                device.exposureMode = .locked
            } else {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            print("❌ Exposure config failed: \(error)")
        }
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
            print("Camera access denied")
        }
    }

    private func setupSession() {
        guard let device = currentDevice else { return }
        session.beginConfiguration()
        session.sessionPreset = .hd4K3840x2160

        if let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported
        }

        if session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: visionQueue)
            session.addOutput(videoOutput)
        }

        session.commitConfiguration()
        configureExposure()

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

    func captureLivePhoto() {
        guard photoOutput.isLivePhotoCaptureSupported else {
            startRecordingFrames()
            return
        }
        capturedImages.removeAll()
        capturedMetadata.removeAll()

        let settings: AVCapturePhotoSettings
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
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
        let image = UIImage(cgImage: cg, scale: 1.0, orientation: .right)
        return (image, metadata)
    }

    private func toggleTorch(on: Bool) {
        guard let device = currentDevice, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            print("Torch failed: \(error)")
        }
    }

    func focus(at point: CGPoint) {
        guard let device = currentDevice, device.isFocusPointOfInterestSupported else { return }
        do {
            try device.lockForConfiguration()
            device.focusPointOfInterest = point
            device.focusMode = .autoFocus
            device.unlockForConfiguration()
        } catch {
            print("Focus failed: \(error)")
        }
    }

    func toggleFocusLock() {
        guard let device = currentDevice else { return }
        do {
            try device.lockForConfiguration()
            if isFocusLocked {
                device.focusMode = .continuousAutoFocus
                device.exposureMode = .continuousAutoExposure
                isFocusLocked = false
            } else {
                device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                device.focusMode = .locked
                configureExposure()
                isFocusLocked = true
            }
            device.unlockForConfiguration()
        } catch {
            print("Focus/exposure lock failed: \(error)")
        }
    }

    func setZoomFactor(_ factor: CGFloat) {
        guard let device = currentDevice else { return }
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = min(max(factor, 1.0), device.activeFormat.videoMaxZoomFactor)
            device.unlockForConfiguration()
            NotificationCenter.default.post(
                name: CameraService.ZoomChangedNotification,
                object: Float(device.videoZoomFactor)
            )
        } catch {
            print("Zoom failed: \(error)")
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

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
        let opts: [String:Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        let assetOutput = AVAssetReaderTrackOutput(track: track, outputSettings: opts)
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

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

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

// MARK: - CoreML Model Loader

class YOLOv8s_Face_Lindevs {
    let model: MLModel

    init(configuration: MLModelConfiguration) throws {
        model = try MLModel(contentsOf: try Self.urlOfModelInThisBundle(), configuration: configuration)
    }

    static func urlOfModelInThisBundle() throws -> URL {
        guard let url = Bundle.main.url(forResource: "yolov8s-face-lindevs", withExtension: "mlmodelc") else {
            throw NSError(domain: "com.example", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model file not found"])
        }
        return url
    }
}
