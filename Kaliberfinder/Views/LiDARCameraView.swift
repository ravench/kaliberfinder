import AVFoundation
import SwiftUI

/// The app's own camera screen (LIDAR-02): preview, guide and shutter. With the LiDAR camera the guide
/// shows distance and tilt; on a phone without a scanner the telephoto, else the wide camera, takes the photo,
/// from its closest focus on, without depth (Raven, 2026-11-09).
struct LiDARCameraView: View {
    let onPick: (UIImage, DepthScale?) -> Void
    @StateObject private var camera: LiDARCamera
    @Environment(\.dismiss) private var dismiss
    @State private var isCapturing = false
    /// The last shutter press delivered no photo (review 2026-11-10): said under the hint, the shutter free again.
    @State private var failed = false

    init(choice: CameraChoice = .lidar, onPick: @escaping (UIImage, DepthScale?) -> Void) {
        self.onPick = onPick
        _camera = StateObject(wrappedValue: LiDARCamera(choice: choice))
    }

    private var hasDepth: Bool { camera.hasDepth }

    /// For a camera without depth: hold it just beyond its closest focus, rounded up to 10 cm; «so nah wie
    /// möglich» until the camera has said.
    static func distanceHint(minimumFocusDistance: Int?) -> String {
        guard let mm = minimumFocusDistance else {
            return "Lege die Patrone flach auf einen hellen Untergrund und halte das Gerät parallel, so nah wie es scharf stellt.".loc
        }
        let cm = Int((Double(mm) / 100).rounded(.up)) * 10
        return String(format: "Lege die Patrone flach auf einen hellen Untergrund und halte das Gerät parallel, gut %lld cm darüber.".loc, cm)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // Without depth the whole 4:3 frame, letterboxed: what is seen is what the photo holds (Raven, 2026-11-09).
            CameraPreview(camera: camera, gravity: hasDepth ? .resizeAspectFill : .resizeAspect).ignoresSafeArea()
            VStack(spacing: 12) {
                Group {
                    if camera.accessDenied {
                        CameraDeniedHint()
                    } else if hasDepth {
                        Text("Lege die Patrone flach auf einen hellen Untergrund und halte das Gerät parallel, 20–30 cm darüber.")
                    } else {
                        // The camera's own closest focus: a 2x telephoto focuses at half a metre, the 17 Pro's 4x at 1.16 m.
                        Text(Self.distanceHint(minimumFocusDistance: camera.minimumFocusDistance))
                    }
                }
                .font(.footnote)
                .multilineTextAlignment(.center)
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                if failed {
                    Text("Kein Foto erhalten, bitte noch einmal.").font(.footnote).foregroundStyle(.red)
                }
                Spacer()
                if hasDepth {
                    Label(camera.guidance.title.loc, systemImage: camera.guidance == .ready ? "checkmark.circle.fill" : "ruler")
                        .font(.headline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(camera.guidance == .ready ? Color.green.opacity(0.85) : Color.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(.white)
                }
                HStack {
                    Button { dismiss() } label: { Text("Abbrechen").cameraPill() }
                    Spacer()
                    Button {
                        isCapturing = true
                        camera.capture { image, depth in
                            isCapturing = false
                            failed = image == nil
                            guard let image else { return }
                            onPick(image, depth)
                            dismiss()
                        }
                    } label: {
                        Circle().strokeBorder(.white, lineWidth: 4).frame(width: 72, height: 72)
                            .overlay(Circle().fill(.white).padding(8))
                    }
                    .disabled(isCapturing || !camera.isRunning)
                    .accessibilityLabel("Foto aufnehmen")
                    Spacer()
                    // Balances the cancel button so the shutter stays centred.
                    Text("Abbrechen").cameraPill().hidden()
                }
                .padding(.horizontal, 24)
            }
            .padding()
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }
}

/// What both camera screens say when the user has not allowed the camera: where to allow it.
struct CameraDeniedHint: View {
    var body: some View {
        // One view, so the callers' padding and background wrap the text and the link together (review 2026-11-10).
        VStack(spacing: 4) {
            Text("Kein Zugriff auf die Kamera. Erlaube ihn in den Einstellungen.")
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: url) { Text("Einstellungen öffnen") }  // Text(…) so the key is extracted
            }
        }
    }
}

/// The live camera image (also the training capture camera), turned with the screen by `camera`.
struct CameraPreview: UIViewRepresentable {
    let camera: LiDARCamera
    /// The app fills the screen with the middle of the frame; the training capture shows the whole 4:3 frame,
    /// letterboxed, so the preview is what the photo will be (Raven, 2026-11-09).
    var gravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = gravity
        camera.attach(previewLayer: view.previewLayer)
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        // swiftlint:disable:next force_cast
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// The text buttons on the camera screens: a dark capsule the size of a finger, since a bare label
/// at the bottom of the viewfinder is hard to hit (Raven, TestFlight 1174).
extension View {
    func cameraPill() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.6), in: Capsule())
            .foregroundStyle(.white)
    }
}
