import SwiftUI
import UIKit
import AVFoundation
import Vision
import CoreML

// MARK: - SwiftUI App Entry


// MARK: - UIViewControllerRepresentable Bridge
struct TestViewControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = TestViewController()
        let nav = UINavigationController(rootViewController: vc)
        nav.navigationBar.prefersLargeTitles = true
        vc.navigationItem.title = "Real-Time Face Detection"
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        // no dynamic updates needed
    }
}

// MARK: - TestViewController for Real-Time Face Detection
class TestViewController: UIViewController {
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let overlayLayer = CAShapeLayer()
    
    // Camera orientation and dimensions
    private var videoOrientation: AVCaptureVideoOrientation = .portrait
    private var videoDeviceInput: AVCaptureDeviceInput?

    // Core ML model wrapped for Vision
    private lazy var visionModel: VNCoreMLModel? = {
        do {
            let coreMLModel = try yolov8s_face_lindevs(configuration: MLModelConfiguration()).model
            return try VNCoreMLModel(for: coreMLModel)
        } catch {
            print("Failed to load Core ML model: \(error)")
            return nil
        }
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupOverlay()
        captureSession.startRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        overlayLayer.frame = view.bounds
    }

    // MARK: - Camera Setup
    private func setupCamera() {
        captureSession.sessionPreset = .high
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            print("Failed to create camera input")
            return
        }
        videoDeviceInput = input
        captureSession.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        captureSession.addOutput(output)

        // Ensure output uses correct orientation
        if let videoConn = output.connection(with: .video),
           videoConn.isVideoOrientationSupported {
            videoConn.videoOrientation = .portrait
            videoOrientation = .portrait
        }

        // Preview layer
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill

        // Align preview orientation
        if let conn = previewLayer.connection,
           conn.isVideoOrientationSupported {
            conn.videoOrientation = .portrait
        }

        view.layer.addSublayer(previewLayer)
    }

    // MARK: - Overlay Setup
    private func setupOverlay() {
        overlayLayer.strokeColor = UIColor.red.cgColor
        overlayLayer.lineWidth = 2
        overlayLayer.fillColor = UIColor.clear.cgColor
        view.layer.addSublayer(overlayLayer)
    }

    // MARK: - Draw Bounding Boxes
    private func drawBoxes(_ observations: [VNRecognizedObjectObservation]) {
        // Remove previous boxes
        overlayLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

        for obs in observations {
            // Convert normalized rect to layer coordinates with adjusted coordinate system
            let boundingBox = obs.boundingBox
            
            // Vision's coordinate system has (0,0) at the bottom left while UIKit uses top left
            // We need to flip the y coordinate
            let flipTransform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -1)
            let transformedBoundingBox = boundingBox.applying(flipTransform)
            
            // Now convert to the layer coordinates
            var convertedRect = previewLayer.layerRectConverted(fromMetadataOutputRect: transformedBoundingBox)
            
            // Check if we need additional adjustment based on videoGravity
            if previewLayer.videoGravity == .resizeAspectFill {
                // Apply aspect fill adjustment if needed
                convertedRect = adjustRectForAspectFill(convertedRect)
            }
            
            // Create box shape
            let path = UIBezierPath(rect: convertedRect)
            let boxLayer = CAShapeLayer()
            boxLayer.path = path.cgPath
            boxLayer.strokeColor = UIColor.red.cgColor
            boxLayer.lineWidth = 2
            boxLayer.fillColor = UIColor.clear.cgColor
            
            // Add confidence label
            let confidenceLabel = createConfidenceLabel(
                frame: convertedRect,
                confidence: obs.confidence,
                label: obs.labels.first?.identifier ?? "Face"
            )
            overlayLayer.addSublayer(confidenceLabel)
            
            overlayLayer.addSublayer(boxLayer)
        }
    }
    
    // Create a confidence label for each detection
    private func createConfidenceLabel(frame: CGRect, confidence: Float, label: String) -> CATextLayer {
        let textLayer = CATextLayer()
        textLayer.string = "\(label): \(Int(confidence * 100))%"
        textLayer.fontSize = 12
        textLayer.foregroundColor = UIColor.white.cgColor
        textLayer.backgroundColor = UIColor.red.withAlphaComponent(0.7).cgColor
        textLayer.alignmentMode = .center
        textLayer.frame = CGRect(
            x: frame.origin.x,
            y: frame.origin.y - 20,
            width: frame.width,
            height: 20
        )
        textLayer.contentsScale = UIScreen.main.scale
        return textLayer
    }
    
    // Adjust rect for aspect fill if needed
    private func adjustRectForAspectFill(_ rect: CGRect) -> CGRect {
        guard let connection = previewLayer.connection else { return rect }
        
        let previewLayerSize = previewLayer.bounds.size
        let cameraAspectRatio = getVideoDimensions()
        
        // Calculate scaling to account for aspect fill
        let scaleX = previewLayerSize.width / cameraAspectRatio.width
        let scaleY = previewLayerSize.height / cameraAspectRatio.height
        let scale = max(scaleX, scaleY)
        
        // Center the scaled video in the preview layer
        let scaledWidth = cameraAspectRatio.width * scale
        let scaledHeight = cameraAspectRatio.height * scale
        let xOffset = (previewLayerSize.width - scaledWidth) / 2
        let yOffset = (previewLayerSize.height - scaledHeight) / 2
        
        // Apply scale and offset
        var adjustedRect = rect
        adjustedRect.origin.x = adjustedRect.origin.x * scale + xOffset
        adjustedRect.origin.y = adjustedRect.origin.y * scale + yOffset
        adjustedRect.size.width *= scale
        adjustedRect.size.height *= scale
        
        return adjustedRect
    }
    
    // Get camera dimensions
    private func getVideoDimensions() -> CGSize {
        guard let input = videoDeviceInput else {
            return CGSize(width: 1080, height: 1920) // Default for portrait
        }
        
        // Get actual dimensions from the device format
        let dimensions = CMVideoFormatDescriptionGetDimensions(
            input.device.activeFormat.formatDescription
        )
        
        // Return dimensions based on orientation
        return (videoOrientation == .portrait || videoOrientation == .portraitUpsideDown) ?
            CGSize(width: CGFloat(dimensions.height), height: CGFloat(dimensions.width)) :
            CGSize(width: CGFloat(dimensions.width), height: CGFloat(dimensions.height))
    }

    // Helper to get orientation for Vision
    private func exifOrientationForCurrentDevice() -> CGImagePropertyOrientation {
        switch UIDevice.current.orientation {
        case .portrait: return .right
        case .portraitUpsideDown: return .left
        case .landscapeLeft: return .up  // Home button on the right
        case .landscapeRight: return .down // Home button on the left
        default: return .right
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension TestViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard
            let visionModel = visionModel,
            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        // Vision request
        let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
            guard
                let self = self,
                let results = request.results as? [VNRecognizedObjectObservation],
                !results.isEmpty
            else { return }
            
            // Only process results with reasonable confidence
            let filteredResults = results.filter { $0.confidence > 0.5 }
            
            DispatchQueue.main.async {
                self.drawBoxes(filteredResults)
            }
        }
        request.imageCropAndScaleOption = .scaleFill

        // Determine orientation dynamically
        let orientation = exifOrientationForCurrentDevice()

        // Perform request on pixel buffer
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        )
        do {
            try handler.perform([request])
        } catch {
            print("Vision request failed: \(error)")
        }
    }
}
