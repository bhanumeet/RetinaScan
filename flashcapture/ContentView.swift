//
//  ContentView.swift
//

import SwiftUI
import AVFoundation
import Photos
import CoreImage
import CoreMedia
import UIKit
import CoreML
import Vision

// MARK: – ContentView

struct ContentView: View {
    @StateObject private var cameraService = CameraService()
    @State private var showImagesView = false
    @State private var zoomLevel: Float = 1.0
    @State private var showFormatSheet = false

    var body: some View {
        ZStack {
            // Live preview
            PreviewView(session: cameraService.session,
                        cameraService: cameraService)
                .ignoresSafeArea()

            // Top controls: focus-lock, format, auto-zoom
            VStack {
                HStack {
                    // Focus-lock
                    Button(action: { cameraService.toggleFocusLock() }) {
                        Image(systemName: cameraService.isFocusLocked ? "lock.fill" : "lock.open")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }

                    // Format picker
                    Button(action: { showFormatSheet = true }) {
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .actionSheet(isPresented: $showFormatSheet) {
                        ActionSheet(
                            title: Text("Choose Format"),
                            buttons: cameraService.availableFormats.map { fmt in
                                .default(Text(fmt.description)) {
                                    cameraService.updateFormat(fmt)
                                }
                            } + [.cancel()]
                        )
                    }
                    .padding(.leading, 8)

                    // Auto-Zoom toggle
                    Button(action: { cameraService.toggleAutoZoom() }) {
                        Image(systemName: cameraService.isAutoZoomEnabled
                              ? "face.smiling.fill"
                              : "face.smiling")
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

            // Record button (bottom)
            VStack {
                Spacer()
                Button(action: { cameraService.startRecordingFrames() }) {
                    Image("camera")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .background(Circle().fill(Color.white.opacity(0.7)))
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            cameraService.configureSession()
            zoomLevel = cameraService.currentZoomFactor
            cameraService.fetchFormats()
        }
        .onReceive(NotificationCenter.default.publisher(for: CameraService.ZoomChangedNotification)) { notif in
            if let z = notif.object as? Float {
                zoomLevel = z
            }
        }
        .onChange(of: cameraService.capturedImages.count) { newCount in
            if newCount == CameraService.targetFrameCount {
                showImagesView = true
            }
        }
        .sheet(isPresented: $showImagesView) {
            ImagesView(images: cameraService.capturedImages) {
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

// MARK: – AVCaptureDevice.Format helper

private extension AVCaptureDevice.Format {
    open override var description: String {
        let dims = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let maxFps = videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        return "\(dims.width)x\(dims.height) @ \(Int(maxFps))fps"
    }
}

// MARK: – CameraService with Auto-Zoom toggle & slider sync

final class CameraService: NSObject, ObservableObject {
    static let targetFrameCount = 20

    static let ZoomChangedNotification = Notification.Name("CameraServiceZoomChanged")

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var frameCount = 0
    private var isRecording = false

    @Published var capturedImages: [UIImage] = []
    @Published var isFocusLocked = false
    @Published var availableFormats: [AVCaptureDevice.Format] = []
    @Published var isAutoZoomEnabled = false

    var minZoom: Float { 1.0 }
    var maxZoom: Float {
        Float(currentDevice?.activeFormat.videoMaxZoomFactor ?? 5.0)
    }
    var currentZoomFactor: Float {
        Float(currentDevice?.videoZoomFactor ?? 1.0)
    }

    private var currentDevice: AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera,
                                for: .video,
                                position: .back)
    }

    private let visionQueue = DispatchQueue(label: "visionQueue")
    private var detectionRequest: VNCoreMLRequest!

    override init() {
        super.init()
        configureVision()
    }

    private func configureVision() {
        guard let modelURL = Bundle.main.url(
                forResource: "yolov8s-face-lindevs",
                withExtension: "mlmodelc"
              ),
              let coreMLModel = try? MLModel(contentsOf: modelURL),
              let visionModel = try? VNCoreMLModel(for: coreMLModel)
        else {
            fatalError("Could not load CoreML model")
        }

        detectionRequest = VNCoreMLRequest(
            model: visionModel,
            completionHandler: handleDetections
        )
        detectionRequest.imageCropAndScaleOption = .scaleFill
    }

    private func handleDetections(request: VNRequest, error: Error?) {
        guard isAutoZoomEnabled else { return }

        if let _ = error {
            DispatchQueue.main.async {
                self.isAutoZoomEnabled = false
                print("No face detected")
            }
            return
        }
        guard let results = request.results as? [VNRecognizedObjectObservation] else {
            DispatchQueue.main.async {
                self.isAutoZoomEnabled = false
                print("No face detected")
            }
            return
        }
        let faces = results.filter { obs in
            obs.labels.first?.identifier == "face"
        }
        guard let best = faces.max(by: { $0.confidence < $1.confidence }) else {
            DispatchQueue.main.async {
                self.isAutoZoomEnabled = false
                print("No face detected")
            }
            return
        }
        DispatchQueue.main.async {
            self.performAutoZoom(boundingBox: best.boundingBox)
        }
    }

    func toggleAutoZoom() {
        DispatchQueue.main.async {
            self.isAutoZoomEnabled.toggle()
            print("Auto zoom \(self.isAutoZoomEnabled ? "enabled" : "disabled")")
        }
    }

    private func performAutoZoom(boundingBox rect: CGRect) {
        // Zoom until the face box touches edges, then pull back to 75%
        let zoom = min(
            max(Float(max(1/rect.width, 1/rect.height) * 0.50), minZoom),
            maxZoom
        )
        setZoomFactor(CGFloat(zoom))
        isAutoZoomEnabled = false
    }


    func setZoomFactor(_ factor: CGFloat) {
        guard let device = currentDevice else { return }
        do {
            try device.lockForConfiguration()
            let clamped = min(max(factor, 1.0),
                              device.activeFormat.videoMaxZoomFactor)
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
            // Notify slider to move
            NotificationCenter.default.post(
                name: CameraService.ZoomChangedNotification,
                object: clamped
            )
        } catch {
            print("Zoom error: \(error)")
        }
    }

    // MARK: – Format handling

    func fetchFormats() {
        guard let device = currentDevice else { return }
        let sorted = device.formats.sorted {
            let d1 = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            let d2 = CMVideoFormatDescriptionGetDimensions($1.formatDescription)
            if d1.width != d2.width { return d1.width > d2.width }
            let fps1 = $0.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            let fps2 = $1.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            return fps1 > fps2
        }
        var seen = Set<String>()
        availableFormats = sorted.filter {
            let desc = $0.description
            if seen.contains(desc) { return false }
            seen.insert(desc)
            return true
        }
    }

    func updateFormat(_ format: AVCaptureDevice.Format) {
        guard let device = currentDevice else { return }
        session.beginConfiguration()
        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            if let bestRange = format.videoSupportedFrameRateRanges.max(
                by: { $0.maxFrameRate < $1.maxFrameRate }
            ) {
                let fps = bestRange.maxFrameRate
                let d = CMTime(value: 1, timescale: CMTimeScale(fps))
                device.activeVideoMinFrameDuration = d
                device.activeVideoMaxFrameDuration = d
            }
            device.unlockForConfiguration()
        } catch {
            print("Format error: \(error)")
        }
        session.commitConfiguration()
    }

    // MARK: – Session setup

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

        if let fmt = select4K60Format(for: device) {
            do {
                try device.lockForConfiguration()
                device.activeFormat = fmt
                let t = CMTime(value: 1, timescale: 60)
                device.activeVideoMinFrameDuration = t
                device.activeVideoMaxFrameDuration = t
                device.unlockForConfiguration()
            } catch { }
        }

        if let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(videoOutput) {
            videoOutput.setSampleBufferDelegate(
                self,
                queue: DispatchQueue(label: "videoQueue")
            )
            session.addOutput(videoOutput)
        }

        session.commitConfiguration()
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
        }
    }

    private func select4K60Format(
        for device: AVCaptureDevice
    ) -> AVCaptureDevice.Format? {
        device.formats.first { f in
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            return d.width == 3840 && d.height == 2160
                && f.videoSupportedFrameRateRanges.contains {
                    $0.maxFrameRate >= 60
                }
        }
    }

    // MARK: – Frame recording

    func startRecordingFrames() {
        DispatchQueue.main.async {
            self.frameCount = 0
            self.capturedImages = []
            self.isRecording = true
            self.toggleTorch(on: false)
        }
    }

    // MARK: – Zoom, focus, torch, image conversion

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

    private func toggleTorch(on: Bool) {
        guard let device = currentDevice, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            print("Torch error: \(error)")
        }
    }

    private func imageFromSampleBuffer(
        _ sampleBuffer: CMSampleBuffer
    ) -> UIImage? {
        guard let pix = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        let ci = CIImage(cvPixelBuffer: pix)
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else {
            return nil
        }
        return UIImage(
            cgImage: cg,
            scale: UIScreen.main.scale,
            orientation: .right
        )
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Vision pass
        if let pix = CMSampleBufferGetImageBuffer(sampleBuffer) {
            visionQueue.async {
                _ = try? VNImageRequestHandler(
                    cvPixelBuffer: pix,
                    orientation: .right,
                    options: [:]
                ).perform([self.detectionRequest])
            }
        }

        // Frame-capture logic
        guard isRecording else { return }
        frameCount += 1
        if frameCount == CameraService.targetFrameCount {
            toggleTorch(on: false)
            isRecording = false
        } else if frameCount == 11 {
            toggleTorch(on: true)
        }

        if frameCount <= CameraService.targetFrameCount,
           let img = imageFromSampleBuffer(sampleBuffer) {
            DispatchQueue.main.async {
                self.capturedImages.append(img)
            }
        }
    }
}
