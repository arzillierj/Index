import SwiftUI
import AVFoundation
import PhotosUI
import UIKit

// MARK: - Public SwiftUI wrapper
//
// Live camera screen. Meal-photo capture is the default posture;
// barcode lookup is a quiet background offer.
//
//   1. Free path — barcode tap-to-confirm. The metadata output
//      watches the full camera feed continuously (no aiming
//      rectangle — AVFoundation never needed one). When a code is
//      detected, a chip slides up above the bottom controls
//      ("Barcode detected — tap to look up"). The chip stays
//      visible while detections keep arriving and slides away
//      after a 2-second grace period without a fresh detection.
//      Tapping the chip routes through `onDetect` to the existing
//      OpenFoodFacts lookup. Auto-fire is deliberately removed —
//      a meal photographer sweeping across a table should not get
//      yanked into a barcode result they didn't ask for.
//
//   2. AI path — meal-photo macro estimate. Shutter button
//      captures a still via AVCapturePhotoOutput; the gallery
//      button opens the photo-library picker. Both feed the same
//      image-data closure (`onPhotoCaptured`) — the parent view
//      (NutritionMainView) routes the data through
//      ClaudeService.estimateMacros and shows the result sheet
//      on success.

struct BarcodeScannerView: View {
    /// Called when the user taps the barcode chip — semantics
    /// changed from the original auto-fire flow. Detection alone
    /// no longer triggers this; user confirmation does.
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

    /// The barcode currently "available" to the user — set when
    /// the metadata delegate sees a code, cleared 2s after the
    /// last fresh detection. nil = no chip visible.
    @State private var detectedBarcode: String? = nil

    /// Grace-period task. Cancelled and re-spawned on every fresh
    /// detection so a continuously-in-frame barcode keeps the
    /// chip alive; stale detections (barcode left frame) fall
    /// through the 2-second sleep and clear the state.
    @State private var graceTask: Task<Void, Never>? = nil

    /// 2-second grace period before a stale detection drops away.
    /// Long enough to span the gap between AVFoundation's last
    /// in-frame fire and the user noticing the chip; short enough
    /// that a fleeting drift across frame doesn't leave a stale
    /// invitation hanging.
    private static let chipGracePeriod: Duration = .seconds(2)

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
                    onBarcodeChipTapped: confirmDetectedBarcode,
                    pickedItem: $pickedItem,
                    isEstimating: isEstimating,
                    inlineMessage: inlineMessage,
                    detectedBarcode: detectedBarcode
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
        .onDisappear {
            graceTask?.cancel()
        }
    }

    /// Per-detection callback from the controller. Sets the chip
    /// state + restarts the grace-period clock. Ignored while
    /// the parent's AI estimate is in flight so the chip doesn't
    /// surface during the loading state (shutter is disabled
    /// then too — keep the screen single-tasked).
    private func receiveDetection(_ code: String) {
        guard !isEstimating else { return }
        detectedBarcode = code
        graceTask?.cancel()
        graceTask = Task { @MainActor in
            try? await Task.sleep(for: Self.chipGracePeriod)
            guard !Task.isCancelled else { return }
            detectedBarcode = nil
        }
    }

    /// Chip tap — user confirms the barcode lookup. Clears state
    /// + routes to the parent's existing `onDetect` callback
    /// (which kicks off the OpenFoodFacts lookup).
    private func confirmDetectedBarcode() {
        guard let code = detectedBarcode else { return }
        graceTask?.cancel()
        detectedBarcode = nil
        onDetect(code)
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
    /// a barcode sits in view; the chip's grace-period timer only
    /// needs a tick every second or so to stay alive.
    private var lastReportedCode: String?
    private var lastReportedAt: Date = .distantPast
    private static let reportThrottle: TimeInterval = 0.5

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
        // re-firing only ticks every reportThrottle seconds so the
        // SwiftUI parent doesn't redraw the chip 30× per second.
        // The grace-period timer in the SwiftUI side only needs a
        // tick every couple of seconds to stay alive.
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
// undimmed. The barcode capability is a tap-to-confirm chip that
// only appears when a code is actually in frame (parent-managed
// via `detectedBarcode`).

private struct ScannerOverlayView: View {
    let onCancel: () -> Void
    let onShutter: () -> Void
    let onBarcodeChipTapped: () -> Void
    @Binding var pickedItem: PhotosPickerItem?
    let isEstimating: Bool
    let inlineMessage: String?
    /// nil → no chip. Non-nil → chip slides up offering the
    /// lookup for this code. The parent owns the grace-period
    /// clock; this view only renders.
    let detectedBarcode: String?

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

            // Barcode chip — slides in from the bottom edge when
            // a code is in frame; slides out when the grace
            // period elapses. Disabled during an in-flight AI
            // estimate so the screen stays single-tasked.
            if detectedBarcode != nil {
                Button(action: onBarcodeChipTapped) {
                    HStack(spacing: 8) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Barcode detected — tap to look up")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.78), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isEstimating)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
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
        .animation(.easeOut(duration: 0.25), value: detectedBarcode)
    }
}
