import AVFoundation
import CoreMotion
import UIKit

/// The back camera paired with the LiDAR scanner (Pro iPhones from the 12 Pro). Shows live guidance
/// (distance and tilt) and takes a photo together with the table distance and focal length.
/// Depth stays in memory and is dropped after the size is computed (LIDAR-07).
final class LiDARCamera: NSObject, ObservableObject {
    /// LIDAR-01: only phones with the scanner get the depth camera.
    static var isAvailable: Bool {
        AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) != nil
    }

    @Published private(set) var guidance: LiDARGuidance = .noDepth
    @Published private(set) var isRunning = false

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private let queue = DispatchQueue(label: "net.forestraven.kaliberfinder.lidar")
    private let motion = CMMotionManager()
    private(set) var tilt: Double?
    /// Gravity in device coordinates, for the training data (`TrainingCapture`).
    private(set) var gravity: [Double]?
    private var device: AVCaptureDevice?
    private var lastDepthUpdate = Date.distantPast
    private var onPhoto: ((UIImage, DepthScale?) -> Void)?
    private var onRawPhoto: ((AVCapturePhoto) -> Void)?

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [self] granted in
            guard granted else { return }
            queue.async { [self] in
                if session.inputs.isEmpty { configure() }
                session.startRunning()
                let running = session.isRunning
                DispatchQueue.main.async { self.isRunning = running }
            }
        }
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 0.1
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let g = data?.gravity else { return }
                self?.tilt = LiDARGuidance.tilt(gravityX: g.x, y: g.y, z: g.z)
                self?.gravity = [g.x, g.y, g.z]
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        queue.async { [self] in session.stopRunning() }
    }

    /// The camera's closest focus distance and lens position now, for the training data; nil before
    /// the camera is set up.
    var focus: CaptureShot.Focus? {
        device.map { CaptureShot.Focus(minimumDistance: $0.minimumFocusDistance >= 0 ? $0.minimumFocusDistance : nil,
                                       lensPosition: Double($0.lensPosition)) }
    }

    /// Takes a photo; `completion` gets the image and, when the depth was usable, its scale.
    func capture(_ completion: @escaping (UIImage, DepthScale?) -> Void) {
        queue.async { [self] in
            onPhoto = completion
            takePhoto()
        }
    }

    /// Takes a photo and hands it over as the camera delivered it, with depth and calibration
    /// (`TrainingRecorder`), on the main queue.
    func captureRaw(_ completion: @escaping (AVCapturePhoto) -> Void) {
        queue.async { [self] in
            onRawPhoto = completion
            takePhoto()
        }
    }

    private func takePhoto() {
        let settings = AVCapturePhotoSettings()
        settings.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliveryEnabled
        settings.isDepthDataFiltered = true
        // Portrait, like the preview (the app runs in portrait only).
        if let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(photoOutput), session.canAddOutput(depthOutput) else { return }
        self.device = device
        session.addInput(input)
        session.addOutput(photoOutput)
        session.addOutput(depthOutput)
        // A 4:3 format that delivers depth, with a float depth format.
        if let format = device.formats.last(where: { f in
            let d = f.formatDescription.dimensions
            return !f.supportedDepthDataFormats.isEmpty && d.width * 3 == d.height * 4
        }) {
            try? device.lockForConfiguration()
            device.activeFormat = format
            device.activeDepthDataFormat = format.supportedDepthDataFormats.last {
                let type = $0.formatDescription.mediaSubType.rawValue
                return type == kCVPixelFormatType_DepthFloat32 || type == kCVPixelFormatType_DepthFloat16
            }
            device.unlockForConfiguration()
        }
        photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
        depthOutput.isFilteringEnabled = true
        depthOutput.setDelegate(self, callbackQueue: queue)
    }

    /// Table distance in mm from a depth map: the valid samples in the central half of the frame.
    static func tableDistance(_ depthData: AVDepthData) -> Double? {
        depthValues(depthData).flatMap { SizeEstimator.tableDistance(depth: $0.values, width: $0.width, height: $0.height) }
    }

    /// The depth map's values in metres, row by row.
    static func depthValues(_ depthData: AVDepthData) -> (values: [Float], width: Int, height: Int)? {
        let depth = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32).depthDataMap
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(depth) else { return nil }
        let width = CVPixelBufferGetWidth(depth), height = CVPixelBufferGetHeight(depth)
        let rowBytes = CVPixelBufferGetBytesPerRow(depth)
        var values: [Float] = []
        values.reserveCapacity(width * height)
        for y in 0..<height {
            values.append(contentsOf: UnsafeBufferPointer(start: base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float.self), count: width))
        }
        return (values, width, height)
    }

    /// Distance and focal length for a photo, nil when the depth isn't absolute or is missing.
    static func depthScale(_ depthData: AVDepthData?) -> DepthScale? {
        guard let depthData, depthData.depthDataAccuracy == .absolute,
              let calibration = depthData.cameraCalibrationData,
              let distance = tableDistance(depthData) else { return nil }
        let reference = calibration.intrinsicMatrixReferenceDimensions
        return DepthScale(tableDistance: distance,
                          focalLength: Double(calibration.intrinsicMatrix.columns.0.x),
                          referenceLongSide: Double(max(reference.width, reference.height)))
    }
}

extension LiDARCamera: AVCaptureDepthDataOutputDelegate {
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData,
                         timestamp: CMTime, connection: AVCaptureConnection) {
        // A few updates a second are enough for the guide.
        guard Date().timeIntervalSince(lastDepthUpdate) > 0.2 else { return }
        lastDepthUpdate = Date()
        let distance = Self.tableDistance(depthData)
        DispatchQueue.main.async { [self] in
            guidance = LiDARGuidance.state(distance: distance, tilt: tilt)
        }
    }
}

extension LiDARCamera: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let raw = onRawPhoto {
            onRawPhoto = nil
            DispatchQueue.main.async { raw(photo) }
            return
        }
        let completion = onPhoto
        onPhoto = nil
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        let scale = Self.depthScale(photo.depthData)
        DispatchQueue.main.async { completion?(image, scale) }
    }
}
