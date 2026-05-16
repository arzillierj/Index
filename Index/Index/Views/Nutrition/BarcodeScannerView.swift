import SwiftUI
import AVFoundation
import PhotosUI
import UIKit

// MARK: - Public SwiftUI wrapper
//
// Live camera screen. Two paths off the same preview:
//
//   1. Free path — barcode auto-detect. The AVCaptureMetadataOutput
//      continuously watches the preview; on the first valid code,
//      the session stops and `onDetect(code)` fires. Existing
//      OpenFoodFacts lookup downstream is unchanged. No AI call,
//      no cost.
//
//   2. AI path — meal-photo macro estimate. Shutter button
//      captures a still via AVCapturePhotoOutput; the gallery
//      button opens the photo-library picker. Both feed the
//      same image-data closure (`onPhotoCaptured`) — the parent
//      view (NutritionMainView) routes the data through
//      ClaudeService.estimateMacros and shows the result sheet
//      on success.
//
// File evolves the verbatim v0 BarcodeScannerView with the
// minimum surface needed for AI capture. The barcode delegate
// path is unchanged.

struct BarcodeScannerView: View {
    let onDetect: (String) -> Void
    /// Fires with the captured / picked image data. Parent runs
    /// the AI estimate + handles dismissal on success.
    let onPhotoCaptured: (Data) -> Void
    let onCancel: () -> Void

    /// Overlay state while the parent's AI estimate is running.
    /// Bound from above so the parent can keep this screen open
    /// during the call and dismiss only on success.
    @Binding var isEstimating: Bool
    /// Non-blocking inline message — e.g. "That doesn't look
    /// like food. Try another photo." Stays on the camera so the
    /// user can retry without re-opening.
    @Binding var inlineMessage: String?

    /// Surfaces a setup failure (camera busy, device-input init
    /// failed, addInput/addOutput refused) so the user sees an
    /// explanation instead of a black screen + xmark button. Audit H22.
    @State private var setupFailureReason: String? = nil

    /// Proxy lets the SwiftUI overlay trigger
    /// `ScannerViewController.capturePhoto()` without holding the
    /// controller directly.
    @State private var captureProxy = CameraCaptureProxy()

    /// Photo-library picker selection (PhotosUI). When non-nil,
    /// the picker loaded an image; we forward its data to
    /// `onPhotoCaptured` and reset.
    @State private var pickedItem: PhotosPickerItem? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if setupFailureReason == nil {
                CameraPreviewRepresentable(
                    onScan: onDetect,
                    onSetupFailed: { reason in
                        setupFailureReason = reason
                    },
                    onPhotoCaptured: onPhotoCaptured,
                    captureProxy: captureProxy
                )
                .ignoresSafeArea()
            }

            if let reason = setupFailureReason {
                setupFailureView(reason: reason)
            } else {
                ScannerOverlayView(
                    onCancel: onCancel,
                    onShutter: { captureProxy.capture?() },
                    pickedItem: $pickedItem,
                    isEstimating: isEstimating,
                    inlineMessage: inlineMessage
                )
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onChange(of: pickedItem) { _, newItem in
            guard let item = newItem else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    onPhotoCaptured(data)
                }
                pickedItem = nil
            }
        }
    }

    private func setupFailureView(reason: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "video.slash.fill")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.7))
            Text("Camera unavailable")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text(reason)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button("Close") { onCancel() }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Capture proxy
//
// SwiftUI doesn't make it easy to reach into a
// UIViewControllerRepresentable's child controller to invoke a
// method. The proxy is a plain class with a single optional
// closure that the controller sets at viewDidLoad time and the
// overlay calls at shutter-tap time. Reference semantics are
// required so updateUIViewController sees the proxy and not a
// stale copy.

@MainActor
final class CameraCaptureProxy {
    var capture: (() -> Void)?
}

// MARK: - Camera preview (UIViewControllerRepresentable)

private struct CameraPreviewRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    /// Bridges AVFoundation setup failures back to the SwiftUI parent
    /// so it can render an error surface instead of a silent black
    /// screen (audit H22).
    let onSetupFailed: (String) -> Void
    let onPhotoCaptured: (Data) -> Void
    let captureProxy: CameraCaptureProxy

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController(
            onScan: onScan,
            onSetupFailed: onSetupFailed,
            onPhotoCaptured: onPhotoCaptured
        )
        captureProxy.capture = { [weak vc] in vc?.capturePhoto() }
        return vc
    }

    func updateUIViewController(_ vc: ScannerViewController, context: Context) {
        // Re-bind on every SwiftUI re-eval — cheap, and survives
        // proxy identity changes if the parent rebuilds.
        captureProxy.capture = { [weak vc] in vc?.capturePhoto() }
    }
}

// MARK: - Scanner view controller
//
// Owns the AVCaptureSession. Two outputs attached:
//   - `AVCaptureMetadataOutput` for the barcode path (unchanged
//     from v0).
//   - `AVCapturePhotoOutput` for the AI path. capturePhoto()
//     triggers a still capture; the delegate's
//     photoOutput(_:didFinishProcessingPhoto:error:) routes the
//     JPEG data back to SwiftUI via `onPhotoCaptured`.

final class ScannerViewController: UIViewController,
    AVCaptureMetadataOutputObjectsDelegate,
    AVCapturePhotoCaptureDelegate {

    private let onScan: (String) -> Void
    private let onSetupFailed: (String) -> Void
    private let onPhotoCaptured: (Data) -> Void
    nonisolated(unsafe) private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasScanned = false
    private let photoOutput = AVCapturePhotoOutput()

    init(
        onScan: @escaping (String) -> Void,
        onSetupFailed: @escaping (String) -> Void,
        onPhotoCaptured: @escaping (Data) -> Void
    ) {
        self.onScan = onScan
        self.onSetupFailed = onSetupFailed
        self.onPhotoCaptured = onPhotoCaptured
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported — BarcodeScannerView is SwiftUI-presented only")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestCameraAccess()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    private func requestCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { DispatchQueue.main.async { self?.setupSession() } }
            }
        default:
            showPermissionDenied()
        }
    }

    private func setupSession() {
        guard let device = AVCaptureDevice.default(for: .video) else {
            onSetupFailed("No camera was found on this device.")
            return
        }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            onSetupFailed("Couldn't open the camera. It may be in use by another app. (\(error.localizedDescription))")
            return
        }
        guard session.canAddInput(input) else {
            onSetupFailed("Couldn't attach the camera input. Try again.")
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else {
            onSetupFailed("Couldn't attach the barcode reader. Try again.")
            return
        }

        guard session.canAddOutput(photoOutput) else {
            onSetupFailed("Couldn't attach the photo output. Try again.")
            return
        }

        // Atomic configuration: add input + outputs inside a single
        // begin/commit pair so the session reconfigures once. The v2
        // attempt skipped this wrapper, which can race with the
        // capture device's internal state during initial setup.
        session.beginConfiguration()
        session.addInput(input)
        session.addOutput(metadataOutput)
        session.addOutput(photoOutput)
        session.commitConfiguration()

        // Order matters: addOutput → setDelegate → metadataObjectTypes.
        // Setting types before addOutput silently drops them.
        metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
        metadataOutput.metadataObjectTypes = [.ean8, .ean13, .upce, .itf14, .code128]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.frame = view.bounds
        layer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    // MARK: - Barcode delegate

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput objects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasScanned,
              let obj = objects.first as? AVMetadataMachineReadableCodeObject,
              let code = obj.stringValue
        else { return }
        hasScanned = true
        session.stopRunning()
        onScan(code)
    }

    // MARK: - Photo capture

    /// Triggers a still capture via `AVCapturePhotoOutput`. The
    /// JPEG data is delivered through the photo delegate below.
    /// Idempotent — multiple rapid taps just queue captures.
    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            // Don't surface — the SwiftUI parent's "Couldn't
            // estimate" path handles network/parse failures
            // generically, and a capture failure feels the same
            // to the user. Log for diagnostic.
            print("[ScannerViewController] photo capture failed: \(String(describing: error))")
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.onPhotoCaptured(data)
        }
    }

    private func showPermissionDenied() {
        DispatchQueue.main.async {
            let label = UILabel()
            label.text = "Camera access denied.\nEnable it in Settings."
            label.textColor = .secondaryLabel
            label.numberOfLines = 0
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
                label.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 32),
                label.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -32),
            ])
        }
    }
}

// MARK: - SwiftUI overlay

private struct ScannerOverlayView: View {
    let onCancel: () -> Void
    let onShutter: () -> Void
    @Binding var pickedItem: PhotosPickerItem?
    let isEstimating: Bool
    let inlineMessage: String?

    @State private var lineOffset: CGFloat = -60

    private let frameW: CGFloat = 280
    private let frameH: CGFloat = 140

    var body: some View {
        ZStack {
            // Dark vignette with viewfinder cutout.
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .mask(
                    Rectangle()
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .frame(width: frameW, height: frameH)
                                .blendMode(.destinationOut)
                        )
                        .compositingGroup()
                )

            // Scan frame
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(IndexPalette.Module.nutrition, lineWidth: 2)
                .frame(width: frameW, height: frameH)

            // Moving scan line
            RoundedRectangle(cornerRadius: 1)
                .fill(
                    LinearGradient(
                        colors: [.clear, IndexPalette.Module.nutrition, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: frameW - 16, height: 2)
                .offset(y: lineOffset)
                .animation(
                    .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                    value: lineOffset
                )
                .onAppear { lineOffset = 60 }

            VStack {
                // Top chrome — close button.
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(20)
                    Spacer()
                }

                Spacer()

                // Inline state messages (loading or non-fatal
                // error like not-food). Render above the bottom
                // controls so the shutter is always reachable.
                if isEstimating {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                        Text("Estimating…")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.bottom, 8)
                } else if let inlineMessage {
                    Text(inlineMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(IndexPalette.Semantic.warning.opacity(0.85), in: Capsule())
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                }

                // Caption above the shutter row.
                Text("Snap a meal for an AI estimate, or point at a barcode.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 12)

                // Bottom controls — gallery on the left, shutter
                // center, balance spacer on the right. Disabled
                // while an estimate is in-flight to prevent
                // double-fire.
                HStack(alignment: .center) {
                    PhotosPicker(selection: $pickedItem, matching: .images) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 26))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .disabled(isEstimating)
                    .opacity(isEstimating ? 0.4 : 1)

                    Spacer()

                    Button(action: onShutter) {
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                                .frame(width: 72, height: 72)
                            Circle()
                                .fill(Color.white)
                                .frame(width: 58, height: 58)
                        }
                    }
                    .disabled(isEstimating)
                    .opacity(isEstimating ? 0.5 : 1)

                    Spacer()

                    // Right-side balance for the gallery icon. Empty
                    // 44pt slot keeps the shutter centered.
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)

                Text("EAN-8 · EAN-13 · UPC-A · UPC-E · ITF-14 · Code 128")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.bottom, 36)
            }
        }
    }
}
