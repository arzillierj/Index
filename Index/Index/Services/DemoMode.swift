import Foundation

/// Central seam for the demo-data feature. The flag lives in
/// UserDefaults; the model container in `IndexApp` reads it at
/// launch to decide which physical SwiftData store to open. Demo
/// mode and real mode are **never** the same store on disk — the
/// isolation is structural, not via predicates or a flag column
/// on the models. CloudKit-shape rules (no @Attribute(.unique),
/// every property defaulted) hold across both stores because both
/// are built from the same `IndexSchema`.
///
/// Switching the flag requires an app restart — see
/// `SettingsView.toggleDemoMode`. iOS apps can't truly self-
/// relaunch, so the toggle calls `exit(0)` after writing the new
/// flag and the user reopens the app.
///
/// The demo store file persists between sessions (cheap to keep,
/// expensive to regenerate). `deleteDemoStoreFiles()` exists as
/// an escape hatch for the "Reset demo data" action.
enum DemoMode {
    /// UserDefaults key. Only this file reads/writes it.
    private static let flagKey = "demoModeEnabled"

    /// Demo SQLite store filename in Application Support, parallel
    /// to the real store (`default.store`). The two files cannot
    /// collide because their names differ; the only way one ever
    /// touches the other is if a developer mis-wires the
    /// ModelConfiguration URL, which is exactly why the URL is
    /// resolved through this single helper.
    static let demoStoreFilename = "Index-demo.store"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: flagKey)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: flagKey)
    }

    /// Absolute URL of the demo store. Returns nil only when the
    /// sandboxed Application Support directory itself can't be
    /// resolved — in that case the caller falls through to the
    /// real-store config so the app still launches.
    static func demoStoreURL() -> URL? {
        let fm = FileManager.default
        guard let supportURL = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return supportURL.appendingPathComponent(demoStoreFilename)
    }

    /// Remove the demo store and its SQLite WAL companions so the
    /// next entry into demo mode regenerates a fresh year. Safe to
    /// call when the demo store doesn't exist — `removeItem` is
    /// errored-and-ignored per file.
    static func deleteDemoStoreFiles() {
        let fm = FileManager.default
        guard let base = demoStoreURL() else { return }
        let dir = base.deletingLastPathComponent()
        for suffix in ["", "-shm", "-wal"] {
            let url = dir.appendingPathComponent(demoStoreFilename + suffix)
            try? fm.removeItem(at: url)
        }
    }
}
