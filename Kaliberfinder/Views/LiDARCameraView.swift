import AVFoundation
import SwiftUI

/// The app's own camera screen on LiDAR devices (LIDAR-02): preview, guide and shutter.
struct LiDARCameraView: View {
    let onPick: (UIImage, DepthScale?) -> Void
    @StateObject private var camera = LiDARCamera()
    @Environment(\.dismiss) private var dismiss
    @State private var isCapturing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(camera: camera).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("Lege die Patrone flach auf einen hellen Untergrund und halte das Gerät parallel, 20–30 cm darüber.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                Spacer()
                Label(camera.guidance.title.loc, systemImage: camera.guidance == .ready ? "checkmark.circle.fill" : "ruler")
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(camera.guidance == .ready ? Color.green.opacity(0.85) : Color.black.opacity(0.6), in: Capsule())
                    .foregroundStyle(.white)
                HStack {
                    Button("Abbrechen") { dismiss() }
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        isCapturing = true
                        camera.capture { image, depth in
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
                    Text("Abbrechen").hidden()
                }
                .padding(.horizontal, 24)
            }
            .padding()
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
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
