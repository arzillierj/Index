import SwiftUI
import AVFoundation

// MARK: - Public SwiftUI wrapper
//
// Verbatim port of the v0 scanner from
//   /Users/yannis/Dashboard/Dashboard/Dashboard/Views/Nutrition/BarcodeScannerView.swift
// Same class hierarchy, same AVCaptureSession setup sequence, same
// delegate flow. The v2 reimplementation introduced rectOfInterest,
// focus/exposure tuning, a custom session preset, and a per-frame
// rectOfInterest re-application — all of which combined to break
// detection. v0 ships with none of that and scans first try on a
// real device.
//
// Only intentional v2 changes vs the v0 file:
//   - `onScan` callback renamed to `onDetect` to match the v2
//     NutritionMainView contract (everything else about the contract
//     is identical: barcode string in, void out).
//   - metadataObjectTypes extended from `[.ean8, .ean13, .upce]` to
//     also include `.itf14` and `.code128` per Phase 6 spec.
//     `.upca` is auto-delivered as `.ean13` with a leading zero — no
//     separate constant exists on AVMetadataObject.ObjectType.
//   - Theme.Colors references swapped for SwiftUI defaults
//     (`.tint` / `.accentColor`) since v2 has no Theme module.

struct BarcodeScannerView: View {
    let onDetect: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreviewRepresentable(onScan: onDetect)
                .ignoresSafeArea()

            ScannerOverlayView(onCancel: onCancel)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }
}

// MARK: - Camera preview (UIViewControllerRepresentable)

private struct CameraPreviewRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        ScannerViewController(onScan: onScan)
    }

    func updateUIViewController(_ vc: ScannerViewController, context: Context) {}
}

// MARK: - Scanner view controller

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let onScan: (String) -> Void
    nonisolated(unsafe) private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasScanned = false

    init(onScan: @escaping (String) -> Void) {
        self.onScan = onScan
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

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
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }

        // Atomic configuration: add input + output inside a single
        // begin/commit pair so the session reconfigures once. The v2
        // attempt skipped this wrapper, which can race with the
        // capture device's internal state during initial setup.
        session.beginConfiguration()
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()

        // Order matters: addOutput → setDelegate → metadataObjectTypes.
        // Setting types before addOutput silently drops them.
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.ean8, .ean13, .upce, .itf14, .code128]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.frame = view.bounds
        layer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

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
    @State private var lineOffset: CGFloat = -60

    private let frameW: CGFloat = 280
    private let frameH: CGFloat = 140

    var body: some View {
        ZStack {
            // Dark vignette with viewfinder cutout
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
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .frame(width: frameW, height: frameH)

            // Corner brackets
            ScanCorners(size: frameW, height: frameH)

            // Moving scan line
            RoundedRectangle(cornerRadius: 1)
                .fill(
                    LinearGradient(
                        colors: [.clear, .accentColor, .clear],
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

            // UI chrome
            VStack {
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

                Text("Scan a barcode")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 8)

                Text("EAN-8 · EAN-13 · UPC-A · UPC-E · ITF-14 · Code 128")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.bottom, 56)
            }
        }
    }
}

// MARK: - Corner bracket decoration

private struct ScanCorners: View {
    let size: CGFloat
    let height: CGFloat
    private let len: CGFloat = 20
    private let thick: CGFloat = 3

    var body: some View {
        ZStack {
            // Use enumerated indices for ID — the v0 file keyed by
            // `\.0`, but two of the four corners share the same x
            // multiplier (-1 or 1) so SwiftUI emitted "ID -1.0
            // occurs multiple times" at runtime.
            ForEach(Array(corners.enumerated()), id: \.offset) { _, corner in
                let xMul = corner.0
                let yMul = corner.1
                Path { path in
                    let x = xMul * (size / 2 - 6)
                    let y = yMul * (height / 2 - 6)
                    path.move(to: CGPoint(x: x, y: y - yMul * len))
                    path.addLine(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x - xMul * len, y: y))
                }
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: thick, lineCap: .round))
            }
        }
        .frame(width: size, height: height)
    }

    private var corners: [(CGFloat, CGFloat)] {
        [(-1, -1), (1, -1), (-1, 1), (1, 1)]
    }
}
