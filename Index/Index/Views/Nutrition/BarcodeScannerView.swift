import SwiftUI
import AVFoundation
import UIKit

/// AVFoundation-backed scanner. SwiftUI owns the overlay chrome
/// (viewfinder cutout, controls, flash, timeout hint); a UIKit
/// preview controller owns the AVCaptureSession and metadata output.
///
/// Reports a detected barcode string to the caller exactly once via
/// `onDetect`. The session is frozen on detection so the same code
/// doesn't repeatedly fire while the result sheet animates in.
///
/// Cancel/permission-denied/decode paths all unwind through the parent
/// — this view never tries to dismiss itself.
struct BarcodeScannerView: View {
    let onDetect: (String) -> Void
    let onCancel: () -> Void

    @State private var detected = false
    @State private var torchOn = false
    @State private var flashOpacity: Double = 0
    @State private var showTimeoutHint = false
    @State private var permissionDenied = false

    private let viewfinderSize = CGSize(width: 280, height: 180)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                BarcodeScannerRepresentable(
                    interestRect: centeredRect(in: geo.size),
                    torchOn: torchOn,
                    freeze: detected,
                    onCode: handleDetect,
                    onPermissionDenied: { permissionDenied = true }
                )
                .ignoresSafeArea()

                viewfinderCutout
                viewfinderBorder
                flashLayer

                VStack {
                    controls
                    Spacer()
                    if showTimeoutHint && !detected {
                        hintBanner
                    }
                    Spacer().frame(height: 48)
                }
            }
            .overlay { if permissionDenied { permissionDeniedOverlay } }
        }
        .task {
            // 15-second hint: only fires if nothing has been detected.
            try? await Task.sleep(for: .seconds(15))
            if !detected { showTimeoutHint = true }
        }
    }

    // MARK: - Overlay layers

    private var viewfinderCutout: some View {
        ZStack {
            Color.black.opacity(0.5)
            Rectangle()
                .frame(width: viewfinderSize.width, height: viewfinderSize.height)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var viewfinderBorder: some View {
        Rectangle()
            .stroke(Color.white, lineWidth: 2)
            .frame(width: viewfinderSize.width, height: viewfinderSize.height)
            .allowsHitTesting(false)
    }

    private var flashLayer: some View {
        Color.white
            .opacity(flashOpacity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    private var controls: some View {
        HStack {
            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .foregroundStyle(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            Spacer()
            Button {
                torchOn.toggle()
            } label: {
                Image(systemName: torchOn ? "bolt.fill" : "bolt.slash")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    private var hintBanner: some View {
        Text("Try holding the phone closer or move to better light.")
            .multilineTextAlignment(.center)
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.6))
            .clipShape(.rect(cornerRadius: 10))
            .padding(.horizontal, 24)
    }

    private var permissionDeniedOverlay: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.7))
            Text("Camera access needed")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Enable camera access in Settings to scan barcodes.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Close") { onCancel() }
                .foregroundStyle(.white)
                .padding(.vertical, 10)
                .padding(.horizontal, 22)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.92).ignoresSafeArea())
    }

    // MARK: - Helpers

    private func centeredRect(in size: CGSize) -> CGRect {
        CGRect(
            x: (size.width - viewfinderSize.width) / 2,
            y: (size.height - viewfinderSize.height) / 2,
            width: viewfinderSize.width,
            height: viewfinderSize.height
        )
    }

    private func handleDetect(_ code: String) {
        guard !detected else { return }
        detected = true

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        withAnimation(.easeOut(duration: 0.15)) { flashOpacity = 0.55 }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeIn(duration: 0.2)) { flashOpacity = 0 }
            try? await Task.sleep(for: .milliseconds(300))
            onDetect(code)
        }
    }
}

// MARK: - UIKit preview

struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    let interestRect: CGRect
    let torchOn: Bool
    let freeze: Bool
    let onCode: (String) -> Void
    let onPermissionDenied: () -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerPreviewController {
        let vc = BarcodeScannerPreviewController()
        vc.onDetect = onCode
        vc.onPermissionDenied = onPermissionDenied
        return vc
    }

    func updateUIViewController(_ vc: BarcodeScannerPreviewController, context: Context) {
        vc.setInterestRect(interestRect)
        vc.setTorch(on: torchOn)
        if freeze { vc.freeze() }
    }
}

/// Owns the AVCaptureSession. Session start/stop runs on a dedicated
/// dispatch queue (AVFoundation hot path) while UI work stays on the
/// main actor.
///
/// UPC-A note: there is no `.upca` constant on AVMetadataObject.ObjectType.
/// UPC-A codes (12-digit) are auto-delivered as `.ean13` with a leading
/// "0" by AVFoundation, so enabling `.ean13` catches both. Open Food
/// Facts accepts the EAN-13 form for UPC-A products too.
final class BarcodeScannerPreviewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onDetect: ((String) -> Void)?
    var onPermissionDenied: (() -> Void)?

    nonisolated(unsafe) private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.yanni.Index.BarcodeScannerSessionQueue")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let metadataOutput = AVCaptureMetadataOutput()
    private var isFrozen = false
    private var pendingInterestRect: CGRect = .zero

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestAccess()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        applyInterestRect()
    }

    private func requestAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupSession()
                    } else {
                        self?.onPermissionDenied?()
                    }
                }
            }
        case .denied, .restricted:
            onPermissionDenied?()
        @unknown default:
            onPermissionDenied?()
        }
    }

    private func setupSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            // Simulator path (no camera) or a device with no rear camera —
            // fall through to a black preview and the timeout hint will
            // eventually fire.
            return
        }

        if device.isFocusModeSupported(.continuousAutoFocus) {
            try? device.lockForConfiguration()
            device.focusMode = .continuousAutoFocus
            device.unlockForConfiguration()
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            metadataOutput.metadataObjectTypes = [.ean13, .ean8, .upce, .itf14, .code128]
        }

        let pl = AVCaptureVideoPreviewLayer(session: session)
        pl.videoGravity = .resizeAspectFill
        pl.frame = view.bounds
        view.layer.addSublayer(pl)
        previewLayer = pl

        applyInterestRect()

        sessionQueue.async { [session] in
            session.startRunning()
        }
    }

    func setInterestRect(_ rect: CGRect) {
        pendingInterestRect = rect
        applyInterestRect()
    }

    /// Convert the SwiftUI viewfinder rect (view coordinates) into the
    /// normalized metadata-output coordinate space. The preview layer
    /// is the authority on the mapping (it knows the camera orientation
    /// + aspect-fill cropping).
    private func applyInterestRect() {
        guard let pl = previewLayer, pendingInterestRect != .zero else { return }
        let converted = pl.metadataOutputRectConverted(fromLayerRect: pendingInterestRect)
        metadataOutput.rectOfInterest = converted
    }

    func setTorch(on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    func freeze() {
        guard !isFrozen else { return }
        isFrozen = true
        sessionQueue.async { [session] in
            session.stopRunning()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !isFrozen,
              let first = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = first.stringValue,
              !code.isEmpty else { return }
        onDetect?(code)
    }
}
