//
//  VideoView.swift
//  flashcapture
//
//  Created by Luo Lab on 5/16/25.
//

import SwiftUI
import AVFoundation
import Photos
import CoreImage
import CoreMedia
import UIKit
import CoreML
import Vision
import ImageIO
import UniformTypeIdentifiers
import MobileCoreServices
import MediaPlayer

// MARK: - Captured Metadata Structure
struct CaptureMetadata {
    let focalLength: Float
    let aperture: Float
    let iso: Float
    let shutterSpeed: String
    let exposureDuration: CMTime
    let lensPosition: Float
    let zoomFactor: Float
    let timestamp: Date
    let frameNumber: Int
    
    init(focalLength: Float, aperture: Float, iso: Float, shutterSpeed: String, exposureDuration: CMTime, lensPosition: Float, zoomFactor: Float, frameNumber: Int) {
        self.focalLength = focalLength
        self.aperture = aperture
        self.iso = iso
        self.shutterSpeed = shutterSpeed
        self.exposureDuration = exposureDuration
        self.lensPosition = lensPosition
        self.zoomFactor = zoomFactor
        self.frameNumber = frameNumber
        self.timestamp = Date()
    }
}

struct VideoView: View {
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
                    
                    // Camera Info Display (top right)
                    CameraInfoOverlay(
                        focalLength: cameraService.currentFocalLength,
                        aperture: cameraService.currentAperture,
                        iso: cameraService.currentISO,
                        shutterSpeed: cameraService.currentShutterSpeed,
                        zoomFactor: cameraService.currentZoomFactor,
                        lensPosition: cameraService.currentLensPosition
                    )
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
            cameraService.setupVolumeButtons()
            zoomLevel = cameraService.currentZoomFactor
            cameraService.fetchFormats()
            cameraService.startCameraInfoUpdates()
        }
        .onDisappear {
            cameraService.removeVolumeButtons()
            cameraService.stopCameraInfoUpdates()
        }
        // Add app lifecycle monitoring
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            print("📱 VideoView: App going to background")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            print("📱 VideoView: App became active - resetting volume monitoring")
            // Always re-setup volume monitoring when app becomes active
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                zoomLevel = cameraService.currentZoomFactor
                // Force volume setup even if we think it's already active
                cameraService.setupVolumeButtons()
            }
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
            let displayImages = Array(cameraService.capturedImages.dropFirst(3).dropLast(1)) // frames 4-9 (indices 3-8)
            let displayMetadata = Array(cameraService.capturedMetadata.dropFirst(3).dropLast(1))
            
            ImagesView(
                images: displayImages,
                capturedMetadata: displayMetadata
            ) {
                showImagesView = false
            }
        }
    }
}

// MARK: - Camera Info Overlay
struct CameraInfoOverlay: View {
    let focalLength: Float
    let aperture: Float
    let iso: Float
    let shutterSpeed: String
    let zoomFactor: Float
    let lensPosition: Float
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("📷 Camera Info")
                .font(.caption.bold())
                .foregroundColor(.white)
            
            HStack {
                Text("FL:")
                    .font(.caption2)
                    .foregroundColor(.gray)
                Text("\(String(format: "%.1f", focalLength))mm")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white)
            }
            
            HStack {
                Text("f/")
                    .font(.caption2)
                    .foregroundColor(.gray)
                Text(String(format: "%.1f", aperture))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white)
            }
            
            HStack {
                Text("ISO:")
                    .font(.caption2)
                    .foregroundColor(.gray)
                Text(String(format: "%.0f", iso))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white)
            }
            
            HStack {
                Text("Speed:")
                    .font(.caption2)
                    .foregroundColor(.gray)
                Text(shutterSpeed)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white)
            }
            
            HStack {
                Text("Focus:")
                    .font(.caption2)
                    .foregroundColor(.gray)
                Text(formatLensPosition(lensPosition))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white)
            }
            
            HStack {
                Text("Zoom:")
                    .font(.caption2)
                    .foregroundColor(.gray)
                Text("\(String(format: "%.1f", zoomFactor))x")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.7))
        .cornerRadius(8)
    }
    
    private func formatLensPosition(_ position: Float) -> String {
        if position.isNaN || position.isInfinite {
            return "Auto"
        }
        
        // Show the REAL lens position value (0.0 - 1.0)
        return String(format: "%.3f", position)
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

// MARK: – CameraService with Fixed Metadata Capture and Volume Button Fix

final class CameraService: NSObject, ObservableObject {
    static let targetFrameCount = 10
    static let ZoomChangedNotification = Notification.Name("CameraServiceZoomChanged")

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var frameCount = 0
    private var isRecording = false

    @Published var capturedImages: [UIImage] = []
    @Published var isFocusLocked = false
    @Published var availableFormats: [AVCaptureDevice.Format] = []
    @Published var isAutoZoomEnabled = false
    
    // MARK: - Live Camera Info Properties (for display)
    @Published var currentFocalLength: Float = 26.0
    @Published var currentAperture: Float = 1.8
    @Published var currentISO: Float = 100.0
    @Published var currentShutterSpeed: String = "1/60"
    @Published var currentLensPosition: Float = 0.0
    
    // MARK: - Captured Metadata (frozen at capture moment)
    @Published var capturedMetadata: [CaptureMetadata] = []
    private var captureStartMetadata: CaptureMetadata?
    
    private var cameraInfoTimer: Timer?
    
    // MARK: - Simple Volume Button Properties
    private var volumeView: MPVolumeView?
    private var appWillResignActiveObserver: NSObjectProtocol?
    private var appDidBecomeActiveObserver: NSObjectProtocol?
    private var isVolumeObserverActive = false

    var minZoom: Float { 1.0 }
    var maxZoom: Float {
        // Limit to optical zoom only (varies by device)
        let deviceOpticalMax: Float = 3.0 // Adjust based on your target device
        return min(Float(currentDevice?.activeFormat.videoMaxZoomFactor ?? 5.0), deviceOpticalMax)
    }
    var currentZoomFactor: Float {
        guard let device = currentDevice else { return 1.0 }
        let zoom = Float(device.videoZoomFactor)
        if zoom.isNaN || zoom.isInfinite || zoom <= 0 {
            return 1.0
        }
        return zoom
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
        setupAppLifecycleObservers()
    }
    
    deinit {
        stopCameraInfoUpdates()
        removeVolumeButtons()
        removeAppLifecycleObservers()
    }
    
    // MARK: - App Lifecycle Observers
    
    private func setupAppLifecycleObservers() {
        // Monitor when app goes to background
        appWillResignActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            print("📱 App going to background - pausing volume monitoring")
            self.pauseVolumeMonitoring()
        }
        
        // Monitor when app comes back to foreground
        appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            print("📱 App became active - resuming volume monitoring")
            self.resumeVolumeMonitoring()
        }
    }
    
    private func removeAppLifecycleObservers() {
        if let observer = appWillResignActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            appWillResignActiveObserver = nil
        }
        if let observer = appDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            appDidBecomeActiveObserver = nil
        }
    }
    
    private func pauseVolumeMonitoring() {
        if isVolumeObserverActive {
            AVAudioSession.sharedInstance().removeObserver(self, forKeyPath: "outputVolume")
            isVolumeObserverActive = false
        }
    }
    
    private func resumeVolumeMonitoring() {
        // Always re-setup volume monitoring when app becomes active
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.setupVolumeButtons()
        }
    }
    
    // MARK: - Simple Volume Button Setup
    
    func setupVolumeButtons() {
        print("📱 Setting up volume button monitoring...")
        
        // Remove existing observer if active
        if isVolumeObserverActive {
            AVAudioSession.sharedInstance().removeObserver(self, forKeyPath: "outputVolume")
            isVolumeObserverActive = false
        }
        
        // Remove existing volume view
        volumeView?.removeFromSuperview()
        
        // Configure audio session
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("❌ Failed to configure audio session: \(error)")
            return
        }
        
        // Set volume to 50% so both up and down work
        DispatchQueue.main.async {
            let targetVolume: Float = 0.5
            let tempVolumeView = MPVolumeView()
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.addSubview(tempVolumeView)
                tempVolumeView.frame = CGRect(x: -1000, y: -1000, width: 1, height: 1)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let slider = tempVolumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
                        slider.value = targetVolume
                        print("📱 Volume set to 50%")
                    }
                    tempVolumeView.removeFromSuperview()
                    
                    // Now setup monitoring after volume is set
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.startVolumeObserver()
                    }
                }
            }
        }
    }
    
    private func startVolumeObserver() {
        // Create hidden volume view for monitoring
        volumeView = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
        volumeView?.showsVolumeSlider = false
        volumeView?.showsRouteButton = false
        volumeView?.alpha = 0.01
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.addSubview(volumeView!)
            window.sendSubviewToBack(volumeView!)
        }
        
        // Add volume observer
        AVAudioSession.sharedInstance().addObserver(
            self,
            forKeyPath: "outputVolume",
            options: [.new, .old],
            context: nil
        )
        isVolumeObserverActive = true
        print("📱 Volume observer active - ready for button presses")
    }
    
    func removeVolumeButtons() {
        print("📱 Removing volume button monitoring...")
        
        if isVolumeObserverActive {
            AVAudioSession.sharedInstance().removeObserver(self, forKeyPath: "outputVolume")
            isVolumeObserverActive = false
        }
        
        volumeView?.removeFromSuperview()
        volumeView = nil
        
        // Reset audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("❌ Failed to deactivate audio session: \(error)")
        }
        
        print("📱 Volume button monitoring removed")
    }
    
    // MARK: - Simple Volume Observer
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "outputVolume" {
            guard let change = change,
                  let newVolume = change[.newKey] as? Float,
                  let oldVolume = change[.oldKey] as? Float else { return }
            
            // Any volume change triggers camera (except tiny changes)
            let volumeDifference = abs(newVolume - oldVolume)
            guard volumeDifference > 0.01 else { return }
            
            print("📱 Volume button pressed! Taking picture...")
            
            // Only trigger if not already recording
            guard !isRecording else { return }
            
            // Take picture
            DispatchQueue.main.async {
                self.startRecordingFrames()
            }
        }
    }
    
    private func setSystemVolume(_ volume: Float) {
        guard let volumeView = volumeView else {
            print("❌ No volume view available")
            return
        }
        
        // Try multiple ways to find the volume slider
        var slider: UISlider?
        
        // Method 1: Direct search
        slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider
        
        // Method 2: Recursive search if direct search fails
        if slider == nil {
            func findSliderRecursively(in view: UIView) -> UISlider? {
                if let slider = view as? UISlider {
                    return slider
                }
                for subview in view.subviews {
                    if let found = findSliderRecursively(in: subview) {
                        return found
                    }
                }
                return nil
            }
            slider = findSliderRecursively(in: volumeView)
        }
        
        // Method 3: Create new volume view if slider not found
        if slider == nil {
            print("📱 Creating new volume view to reset volume")
            let newVolumeView = MPVolumeView()
            if let window = volumeView.superview as? UIWindow {
                window.addSubview(newVolumeView)
                newVolumeView.frame = CGRect(x: -1000, y: -1000, width: 1, height: 1)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    slider = newVolumeView.subviews.first(where: { $0 is UISlider }) as? UISlider
                    slider?.value = volume
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        newVolumeView.removeFromSuperview()
                    }
                }
                return
            }
        }
        
        // Set the volume if we found a slider
        if let slider = slider {
            print("📱 Resetting volume to: \(String(format: "%.3f", volume))")
            DispatchQueue.main.async {
                slider.value = volume
            }
        } else {
            print("❌ Could not find volume slider to reset")
        }
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
            NotificationCenter.default.post(
                name: CameraService.ZoomChangedNotification,
                object: Float(clamped)
            )
        } catch {
            print("Zoom error: \(error)")
        }
    }
    
    // MARK: - Camera Info Updates (for live display)
    
    func startCameraInfoUpdates() {
        cameraInfoTimer?.invalidate()
        cameraInfoTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            guard self.session.isRunning else { return }
            self.updateCameraInfo()
        }
    }
    
    func stopCameraInfoUpdates() {
        cameraInfoTimer?.invalidate()
        cameraInfoTimer = nil
    }
    
    private func updateCameraInfo() {
        guard let device = currentDevice else { return }
        
        DispatchQueue.main.async {
            // Calculate focal length based on zoom
            let baseFocalLength = self.getBaseFocalLength(for: device)
            let zoomFactor = Float(device.videoZoomFactor)
            
            // Check for valid zoom factor
            if zoomFactor.isNaN || zoomFactor.isInfinite || zoomFactor <= 0 {
                self.currentFocalLength = baseFocalLength
            } else {
                self.currentFocalLength = baseFocalLength * zoomFactor
            }
            
            // Get aperture (usually fixed on iPhone)
            self.currentAperture = self.getAperture(for: device)
            
            // Get current ISO with safety check
            let iso = Float(device.iso)
            if iso.isNaN || iso.isInfinite || iso < 0 {
                self.currentISO = 100.0
            } else {
                self.currentISO = iso
            }
            
            // Get exposure duration (shutter speed)
            let exposureDuration = device.exposureDuration
            self.currentShutterSpeed = self.formatExposureDuration(exposureDuration)
            
            // Get REAL lens position
            self.currentLensPosition = device.lensPosition
        }
    }
    
    // MARK: - Metadata Capture (freeze at capture moment)
    
    private func captureCurrentMetadata(for frameNumber: Int) -> CaptureMetadata {
        guard let device = currentDevice else {
            return CaptureMetadata(
                focalLength: 26.0,
                aperture: 1.8,
                iso: 100.0,
                shutterSpeed: "1/60",
                exposureDuration: CMTime(value: 1, timescale: 60),
                lensPosition: 0.0,
                zoomFactor: 1.0,
                frameNumber: frameNumber
            )
        }
        
        // Capture the EXACT metadata at this moment
        let baseFocalLength = getBaseFocalLength(for: device)
        let zoomFactor = Float(device.videoZoomFactor)
        let validZoomFactor = (zoomFactor.isNaN || zoomFactor.isInfinite || zoomFactor <= 0) ? 1.0 : zoomFactor
        
        let iso = Float(device.iso)
        let validISO = (iso.isNaN || iso.isInfinite || iso < 0) ? 100.0 : iso
        
        let exposureDuration = device.exposureDuration
        let shutterSpeed = formatExposureDuration(exposureDuration)
        
        return CaptureMetadata(
            focalLength: baseFocalLength * validZoomFactor,
            aperture: getAperture(for: device),
            iso: validISO,
            shutterSpeed: shutterSpeed,
            exposureDuration: exposureDuration,
            lensPosition: device.lensPosition,
            zoomFactor: validZoomFactor,
            frameNumber: frameNumber
        )
    }
    
    private func getBaseFocalLength(for device: AVCaptureDevice) -> Float {
        switch device.deviceType {
        case .builtInWideAngleCamera:
            return 26.0 // iPhone main camera ~26mm equivalent
        case .builtInUltraWideCamera:
            return 13.0 // iPhone ultra-wide ~13mm equivalent
        case .builtInTelephotoCamera:
            return 77.0 // iPhone telephoto ~77mm equivalent
        default:
            return 26.0
        }
    }
    
    private func getAperture(for device: AVCaptureDevice) -> Float {
        switch device.deviceType {
        case .builtInWideAngleCamera:
            return 1.8 // iPhone main camera typically f/1.8
        case .builtInUltraWideCamera:
            return 2.4 // iPhone ultra-wide typically f/2.4
        case .builtInTelephotoCamera:
            return 2.8 // iPhone telephoto typically f/2.8
        default:
            return 1.8
        }
    }
    
    private func formatExposureDuration(_ duration: CMTime) -> String {
        let seconds = CMTimeGetSeconds(duration)
        
        if seconds.isNaN || seconds.isInfinite || seconds <= 0 {
            return "1/60"
        }
        
        if seconds >= 1.0 {
            return String(format: "%.1fs", seconds)
        } else {
            let fraction = 1.0 / seconds
            if fraction.isNaN || fraction.isInfinite {
                return "1/60"
            }
            let denominator = Int(fraction.rounded())
            return "1/\(max(denominator, 1))"
        }
    }

    // MARK: – Frame recording with metadata capture

    func startRecordingFrames() {
        DispatchQueue.main.async {
            self.frameCount = 0
            self.capturedImages = []
            self.capturedMetadata = [] // Reset captured metadata
            self.isRecording = true
            self.toggleTorch(on: false)
            
            // Capture the metadata at the EXACT moment of pressing the button
            self.captureStartMetadata = self.captureCurrentMetadata(for: 0)
            print("🎯 CAPTURE STARTED - Metadata frozen at: Focus=\(String(format: "%.3f", self.captureStartMetadata?.lensPosition ?? 0.0)), FL=\(self.captureStartMetadata?.focalLength ?? 0.0)mm")
        }
    }

    // MARK: – Enhanced EXIF Save with captured metadata
    
    func saveFramesWithEXIF() {
        print("🔥 Starting to save \(capturedImages.count) frames with frozen metadata")
        
        for (index, image) in capturedImages.enumerated() {
            if index < capturedMetadata.count {
                saveImageWithEXIF(image: image, metadata: capturedMetadata[index])
            } else {
                print("❌ No metadata for frame \(index + 1)")
            }
        }
    }
    
    private func saveImageWithEXIF(image: UIImage, metadata: CaptureMetadata) {
        print("🔥 Processing frame \(metadata.frameNumber) - Frozen Focus: \(String(format: "%.3f", metadata.lensPosition))")
        
        // Convert image to JPEG data first
        guard let jpegData = image.jpegData(compressionQuality: 0.95) else {
            print("❌ Failed to convert image to JPEG")
            return
        }
        
        // Create image source from JPEG data
        guard let imageSource = CGImageSourceCreateWithData(jpegData as CFData, nil) else {
            print("❌ Failed to create image source")
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
        exifDict[kCGImagePropertyExifUserComment as String] = "FlashCapture F\(metadata.frameNumber) | Focus: \(String(format: "%.3f", metadata.lensPosition)) | Distance: \(String(format: "%.2f", focusDistance))m | FL: \(String(format: "%.1f", metadata.focalLength))mm | f/\(String(format: "%.1f", metadata.aperture)) | ISO\(Int(metadata.iso)) | \(metadata.shutterSpeed)"
        
        // Additional focus-related fields
        exifDict[kCGImagePropertyExifSubjectArea as String] = [Int(image.size.width/2), Int(image.size.height/2), 100, 100]
        
        // Timestamps
        exifDict[kCGImagePropertyExifDateTimeOriginal as String] = exifDateString
        exifDict[kCGImagePropertyExifDateTimeDigitized as String] = exifDateString
        
        // Lens info
        exifDict[kCGImagePropertyExifLensModel as String] = "iPhone Wide"
        exifDict[kCGImagePropertyExifLensMake as String] = "Apple"
        
        mutableMetadata[kCGImagePropertyExifDictionary as String] = exifDict
        
        // Enhanced TIFF metadata
        var tiffDict = mutableMetadata[kCGImagePropertyTIFFDictionary as String] as? NSMutableDictionary ?? NSMutableDictionary()
        tiffDict[kCGImagePropertyTIFFMake as String] = "Apple"
        tiffDict[kCGImagePropertyTIFFModel as String] = UIDevice.current.model
        tiffDict[kCGImagePropertyTIFFSoftware as String] = "FlashCapture-Pro"
        tiffDict[kCGImagePropertyTIFFDateTime as String] = exifDateString
        
        // COMPREHENSIVE metadata in TIFF description
        tiffDict[kCGImagePropertyTIFFImageDescription as String] = "Frame \(metadata.frameNumber)/\(CameraService.targetFrameCount) | Focus: \(String(format: "%.3f", metadata.lensPosition)) | Distance: \(String(format: "%.2f", focusDistance))m | \(String(format: "%.1f", metadata.focalLength))mm f/\(String(format: "%.1f", metadata.aperture)) ISO\(Int(metadata.iso)) \(metadata.shutterSpeed)"
        
        mutableMetadata[kCGImagePropertyTIFFDictionary as String] = tiffDict
        
        // GPS metadata (empty but structured)
        var gpsDict = mutableMetadata[kCGImagePropertyGPSDictionary as String] as? NSMutableDictionary ?? NSMutableDictionary()
        gpsDict[kCGImagePropertyGPSProcessingMethod as String] = "FlashCapture Focus Stack"
        mutableMetadata[kCGImagePropertyGPSDictionary as String] = gpsDict
        
        print("🎯 Complete metadata added: Frame=\(metadata.frameNumber), Focus=\(String(format: "%.3f", metadata.lensPosition)), FL=\(String(format: "%.1f", metadata.focalLength))mm, f/\(String(format: "%.1f", metadata.aperture)), ISO=\(Int(metadata.iso)), Speed=\(metadata.shutterSpeed)")
        
        // Create output data
        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(outputData as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            print("❌ Failed to create destination")
            return
        }
        
        // Add image with comprehensive metadata
        if let cgImage = image.cgImage {
            CGImageDestinationAddImage(destination, cgImage, mutableMetadata as CFDictionary)
            
            if CGImageDestinationFinalize(destination) {
                print("✅ Frame \(metadata.frameNumber) processed with complete metadata")
                
                // Save to Photos (async)
                PHPhotoLibrary.shared().performChanges({
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, data: outputData as Data, options: nil)
                }, completionHandler: { success, error in
                    DispatchQueue.main.async {
                        if success {
                            print("✅ Frame \(metadata.frameNumber) saved with complete frozen metadata")
                        } else {
                            print("❌ Failed to save frame \(metadata.frameNumber): \(error?.localizedDescription ?? "unknown")")
                        }
                    }
                })
            } else {
                print("❌ Failed to finalize destination for frame \(metadata.frameNumber)")
            }
        } else {
            print("❌ No CGImage for frame \(metadata.frameNumber)")
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

    // MARK: – Focus, torch, image conversion

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

// MARK: - MPVolumeView Extension for Volume Control
extension MPVolumeView {
    static func setVolume(_ volume: Float) {
        let volumeView = MPVolumeView()
        let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            slider?.value = volume
        }
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

        // Frame-capture logic with metadata freezing
        guard isRecording else { return }
        frameCount += 1
        
        if frameCount == CameraService.targetFrameCount {
            toggleTorch(on: false)
            isRecording = false
        } else if frameCount == 2 {
            toggleTorch(on: true)
        }

        if frameCount <= CameraService.targetFrameCount,
           let img = imageFromSampleBuffer(sampleBuffer) {
            
            // CRITICAL: Capture metadata for THIS specific frame
            let frameMetadata = captureCurrentMetadata(for: frameCount)
            
            DispatchQueue.main.async {
                self.capturedImages.append(img)
                self.capturedMetadata.append(frameMetadata) // Store metadata for this frame
                print("📸 Frame \(self.frameCount) captured with frozen metadata: Focus=\(String(format: "%.3f", frameMetadata.lensPosition))")
            }
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
