import AVFoundation
import CoreMotion
import UIKit

/// The back camera paired with the LiDAR scanner (Pro iPhones from the 12 Pro, iPad Pro). Shows live
/// guidance (distance and tilt) and takes a photo together with the table distance and focal length.
/// Depth stays in memory and is dropped after the size is computed (LIDAR-07).
/// The training capture may pick another back camera (`deviceType`): a telephoto or the ultra wide
/// one, which deliver no depth (Raven, 2026-11-08: to see what a telephoto does for the photos).
final class LiDARCamera: NSObject, ObservableObject {
    /// LIDAR-01: only devices with the scanner get the depth camera.
    static var isAvailable: Bool { isAvailable(.builtInLiDARDepthCamera) }

    static func isAvailable(_ type: AVCaptureDevice.DeviceType) -> Bool {
        AVCaptureDevice.default(type, for: .video, position: .back) != nil
    }

    /// The back cameras the training capture may choose from, the LiDAR camera first; only the ones this device has.
    static var choices: [AVCaptureDevice.DeviceType] {
        [.builtInLiDARDepthCamera, .builtInTelephotoCamera, .builtInUltraWideCamera].filter(isAvailable)
    }

    let deviceType: AVCaptureDevice.DeviceType

    init(deviceType: AVCaptureDevice.DeviceType = .builtInLiDARDepthCamera) {
        self.deviceType = deviceType
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
    private var onRawPhoto: ((AVCapturePhoto, CaptureMoment) -> Void)?
    /// How the phone and the camera stood when the raw photo was taken, read just before it.
    private var rawMoment = CaptureMoment()
    /// The preview on screen, so the preview and the photo turn with the screen (an iPad turns).
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    /// Degrees the camera image is turned for the screen: 90 is portrait, as phones always are.
    @Published private(set) var rotationAngle: CGFloat = 90

    /// Shows the preview on `layer` and turns it, and the photos, with the screen.
    func attach(previewLayer layer: AVCaptureVideoPreviewLayer) {
        // A new layer (the screen was shown again) gets a coordinator of its own.
        if previewLayer !== layer { rotation = nil; rotationObservation = nil }
        previewLayer = layer
        layer.session = session
        coordinateRotation()
    }

    /// Follows the screen's orientation once the device and the preview are both known.
    private func coordinateRotation() {
        guard rotation == nil, let device, let previewLayer else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotation = coordinator
        // Delivered on the main queue. The photo gets the preview's angle rather than the one for
        // horizon-level capture: held flat over the table, gravity says nothing about the horizon,
        // and the photo should show what the screen showed.
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] c, _ in
            let angle = c.videoRotationAngleForHorizonLevelPreview
            self?.rotationAngle = angle
            if let connection = self?.previewLayer?.connection, connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }

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

    /// Takes a photo; `completion` gets the image and, when the depth was usable, its scale.
    func capture(_ completion: @escaping (UIImage, DepthScale?) -> Void) {
        let angle = rotationAngle
        queue.async { [self] in
            onPhoto = completion
            takePhoto(angle: angle)
        }
    }

    /// Takes a photo and hands it over as the camera delivered it, with depth and calibration
    /// (`TrainingRecorder`), on the main queue.
    func captureRaw(_ completion: @escaping (AVCapturePhoto, CaptureMoment) -> Void) {
        // Gravity and tilt as Core Motion last delivered them (on the main queue), the focus on the
        // camera's queue: the lens keeps focusing, so its position as the photo is taken, not once it
        // is delivered.
        let pose = CaptureMoment(gravity: gravity, tilt: tilt)
        let angle = rotationAngle
        queue.async { [self] in
            onRawPhoto = completion
            rawMoment = pose
            rawMoment.focus = device.map { CaptureShot.Focus(minimumFocusDistance: $0.minimumFocusDistance, lensPosition: $0.lensPosition) }
            rawMoment.camera = CameraInfo.shortName(deviceType.rawValue)
            takePhoto(angle: angle)
        }
    }

    /// `angle`: the preview's rotation, so the photo is turned like the screen.
    private func takePhoto(angle: CGFloat) {
        let settings = AVCapturePhotoSettings()
        settings.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliveryEnabled
        settings.isDepthDataFiltered = true
        // The sensor's full resolution (48 MP on the Pro phones since the 14 Pro): the second look cuts the
        // cartridge out of the full-size photo, so every pixel counts there.
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        if let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(deviceType, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        let hasDepth = device.formats.contains { !$0.supportedDepthDataFormats.isEmpty }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(photoOutput), !hasDepth || session.canAddOutput(depthOutput) else { return }
        self.device = device
        session.addInput(input)
        session.addOutput(photoOutput)
        if hasDepth { session.addOutput(depthOutput) }
        DispatchQueue.main.async { self.coordinateRotation() }
        // A 4:3 format that delivers depth, with a float depth format (without depth, any 4:3 format); of
        // those, the one whose photos can be largest.
        let candidates = device.formats.filter { f in
            let d = f.formatDescription.dimensions
            return (!hasDepth || !f.supportedDepthDataFormats.isEmpty) && d.width * 3 == d.height * 4
        }
        if let format = candidates.max(by: { Self.largest($0.supportedMaxPhotoDimensions).width < Self.largest($1.supportedMaxPhotoDimensions).width }) {
            try? device.lockForConfiguration()
            device.activeFormat = format
            // Only where there is one: setting nil on a camera without depth throws (TestFlight 1113 crashed so).
            if let depthFormat = format.supportedDepthDataFormats.last(where: {
                let type = $0.formatDescription.mediaSubType.rawValue
                return type == kCVPixelFormatType_DepthFloat32 || type == kCVPixelFormatType_DepthFloat16
            }) {
                device.activeDepthDataFormat = depthFormat
            }
            device.unlockForConfiguration()
            photoOutput.maxPhotoDimensions = Self.largest(format.supportedMaxPhotoDimensions)
        }
        photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
        guard hasDepth else { return }
        depthOutput.isFilteringEnabled = true
        depthOutput.setDelegate(self, callbackQueue: queue)
    }

    /// The largest of a format's photo sizes (by width); zero when it names none.
    static func largest(_ dimensions: [CMVideoDimensions]) -> CMVideoDimensions {
        dimensions.max { $0.width < $1.width } ?? CMVideoDimensions(width: 0, height: 0)
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
        if error != nil, let format = device?.activeFormat,
           photoOutput.maxPhotoDimensions.width > format.formatDescription.dimensions.width {
            // The full resolution did not go with depth delivery on this phone: once more at the format's own size.
            photoOutput.maxPhotoDimensions = format.formatDescription.dimensions
            queue.async { [self] in takePhoto(angle: photoOutput.connection(with: .video)?.videoRotationAngle ?? 90) }
            return
        }
        if let raw = onRawPhoto {
            onRawPhoto = nil
            let moment = rawMoment
            DispatchQueue.main.async { raw(photo, moment) }
            return
        }
        let completion = onPhoto
        onPhoto = nil
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        let scale = Self.depthScale(photo.depthData)
        DispatchQueue.main.async { completion?(image, scale) }
    }
}
