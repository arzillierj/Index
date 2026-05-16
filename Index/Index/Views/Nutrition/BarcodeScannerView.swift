import SwiftUI
import AVFoundation
import PhotosUI
import UIKit

// MARK: - Public SwiftUI wrapper
//
// Live camera screen. Two paths share one preview:
//
//   1. Free path — barcode auto-fire. The metadata output
//      watches the full camera feed continuously (no aiming
//      rectangle — AVFoundation doesn't need one). When the
//      same barcode value has been detected continuously for
//      ~0.6s the OpenFoodFacts lookup fires automatically via
//      `onDetect`. The stability window prevents a barcode that
//      sweeps past the edge of frame for a single detection
//      from hijacking a meal-photo capture. Within one camera
//      presentation, each barcode value fires at most once —
//      reopening the camera after dismissing the result resets
//      the fired state.
//
//   2. AI path — meal-photo macro estimate. Shutter button
//      captures a still via AVCapturePhotoOutput; the gallery
//      button opens the photo-library picker. Both feed the same
//      image-data closure (`onPhotoCaptured`) — the parent view
//      (NutritionMainView) routes the data through
//      ClaudeService.estimateMacros and shows the result sheet
//      on success.

struct BarcodeScannerView: View {
    /// Fires when a stable barcode detection clears the
    /// stability window. Parent runs the OpenFoodFacts lookup
    /// and routes to the result sheet.
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

    /// Stability tracking. `candidateCode` is the barcode value
    /// we're currently watching; `candidateFirstSeenAt` is when
    /// it first appeared in this run of continuous detections.
    /// Once `now - candidateFirstSeenAt >= stabilityWindow` and
    /// the code hasn't already fired in this presentation, the
    /// lookup auto-fires. `lastDetectionAt` is used to detect
    /// long gaps (>gapResetWindow) — a gap resets the candidate
    /// so a stale code doesn't carry over after the barcode left
    /// frame. `lastFiredCode` blocks re-firing for the same code
    /// during a single presentation of this view.
    @State private var candidateCode: String? = nil
    @State private var candidateFirstSeenAt: Date = .distantPast
    @State private var lastDetectionAt: Date = .distantPast
    @State private var lastFiredCode: String? = nil

    /// How long the SAME barcode must be visible continuously
    /// before auto-fire. Chosen at 0.6s — long enough that a
    /// barcode sweeping past the edge of frame during a meal-
    /// photo framing pass won't cross the threshold; short
    /// enough that a deliberate point-at-the-barcode feels
    /// instant.
    private static let stabilityWindow: TimeInterval = 0.6

    /// If the gap between two detections of the same code
    /// exceeds this, the candidate is reset and the stability
    /// window starts over. Prevents a code seen 5 seconds ago
    /// (then absent, then re-seen) from auto-firing on the
    /// strength of stale time accumulated earlier.
    private static let gapResetWindow: TimeInterval = 0.8

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if setupFailureReason == nil {
                CameraPreviewRepresentable(
                    onScan: receiveDetection,
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

    /// Per-detection callback from the controller. Maintains the
    /// stability window and auto-fires `onDetect` when the same
    /// code has been continuously visible for ≥ `stabilityWindow`.
    /// Ignored while the parent's AI estimate is in flight so
    /// detections during the loading overlay don't queue up.
    ///
    /// The controller reports detections at roughly the
    /// `reportThrottle` cadence (0.15s) per code, so the window
    /// accumulates several samples before firing — a single-
    /// frame sweep through frame never crosses the threshold.
    private func receiveDetection(_ code: String) {
        guard !isEstimating else { return }
        let now = Date.now

        // Already fired for this code during this presentation.
        // Note the detection time (so a long absence still
        // resets the gap detector for OTHER codes), but skip
        // the rest.
        if code == lastFiredCode {
            lastDetectionAt = now
            return
        }

        let gap = now.timeIntervalSince(lastDetectionAt)
        lastDetectionAt = now

        // New code, or a too-long gap since the previous
        // detection — start the stability window over.
        if candidateCode != code || gap > Self.gapResetWindow {
            candidateCode = code
            candidateFirstSeenAt = now
            return
        }

        // Same code, continuous. Fire if we've cleared the window.
        let elapsed = now.timeIntervalSince(candidateFirstSeenAt)
        if elapsed >= Self.stabilityWindow {
            lastFiredCode = code
            candidateCode = nil
            onDetect(code)
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
        // proxy identity changes if the parent rebuilds. The
        // controller-side onScan stays bound to the closure we
        // passed in makeUIViewController; if SwiftUI re-evals
        // change it, we lose the new identity here. Acceptable
        // because the closure body just calls the same parent
        // method (receiveDetection); no captured state drifts.
        captureProxy.capture = { [weak vc] in vc?.capturePhoto() }
    }
}

// MARK: - Scanner view controller
//
// Owns the AVCaptureSession. Two outputs attached:
//   - `AVCaptureMetadataOutput` for the barcode path. Calls back
//     on every detection (throttled to ≥0.5s between fires of
//     the same code so we don't flood the SwiftUI parent's
//     re-render loop). Does NOT stop the session — the camera
//     keeps running so the user can also shutter a meal photo.
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
    private let photoOutput = AVCapturePhotoOutput()

    /// Last code we surfaced + when, for throttling. AVFoundation
    /// can fire metadata at the camera's frame rate (~30 Hz) when
    /// a barcode sits in view. We throttle to ~6.5 Hz so the
    /// SwiftUI parent's stability-window math gets several
    /// samples per second without re-rendering 30× per second.
    /// The throttle is tighter than the chip-era 0.5s value
    /// because the parent now needs enough samples within a
    /// 0.6s stability window to confirm continuous detection.
    private var lastReportedCode: String?
    private var lastReportedAt: Date = .distantPast
    private static let reportThrottle: TimeInterval = 0.15

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
        guard let obj = objects.first as? AVMetadataMachineReadableCodeObject,
              let code = obj.stringValue else { return }
        // Throttle: a new code fires immediately; the same code
        // re-firing only ticks every reportThrottle (0.15s) so
        // the SwiftUI parent's stability window has a steady ~6
        // Hz stream of samples without redrawing 30× per second.
        let now = Date.now
        if code == lastReportedCode,
           now.timeIntervalSince(lastReportedAt) < Self.reportThrottle {
            return
        }
        lastReportedCode = code
        lastReportedAt = now
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
//
// Meal-capture-first overlay. No framing rectangle, no scan
// line, no vignette — the camera feed shows full-frame and
// undimmed. The barcode path is silent in the UI: detection +
// stability-window auto-fire happens in the SwiftUI parent;
// there's no chip, no confirmation step. The overlay just
// frames the camera + the meal-photo controls.

private struct ScannerOverlayView: View {
    let onCancel: () -> Void
    let onShutter: () -> Void
    @Binding var pickedItem: PhotosPickerItem?
    let isEstimating: Bool
    let inlineMessage: String?

    var body: some View {
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

            // Inline state messages (loading or non-fatal error
            // like not-food). Render above the bottom controls
            // so the shutter is always reachable.
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
            Text("Snap a meal for an AI estimate")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 12)

            // Bottom controls — gallery on the left, shutter
            // center, balance spacer on the right. Disabled while
            // an estimate is in-flight to prevent double-fire.
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
            .padding(.bottom, 36)
        }
    }
}
