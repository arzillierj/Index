import SwiftUI
import SwiftData

@main
struct IndexApp: App {
    /// Set in ApplicationSupport-wipe recovery so ContentView can surface
    /// a one-time "your data was reset" alert on next render.
    static let storeResetFlagKey = "storeResetDueToMigrationFailure"

    /// Set when the ModelContainer init couldn't recover and we fell
    /// back to an in-memory store. ContentView reads this and renders a
    /// hard-error screen with a "Reset all data" button instead of
    /// letting the user log into a phantom in-memory store unaware.
    /// (Audit DQ5: single-shot wipe; no three-strikes retry budget.)
    static let hardErrorFlagKey = "indexHardErrorOnLaunch"

    /// Static shared instance so both the `modelContainer` property
    /// (passed to `.modelContainer(...)` for SwiftData wiring) and the
    /// HealthKitService construction (audit H10) reference the same
    /// container. The closure runs once on first access.
    ///
    /// Demo mode: when `DemoMode.isEnabled` is true at launch, the
    /// container is built against a physically separate SQLite store
    /// (`Index-demo.store` in Application Support) instead of the
    /// real store (`default.store`). The two stores are never both
    /// open in the same process — only one ModelConfiguration is
    /// constructed per launch, gated by the flag. Flipping the
    /// toggle in Settings writes the new flag value and calls
    /// `exit(0)`; the next launch opens the other store. This is
    /// the entire mechanism that keeps demo data isolated from real
    /// data: distinct files on disk, never co-resident.
    private static let sharedContainer: ModelContainer = {
        let schema = Schema(IndexSchema.models)
        // Local SwiftData store. CloudKit is intentionally NOT configured
        // yet — pending paid Developer Program enrollment. When enabled,
        // ModelConfiguration adds `cloudKitDatabase: .private(...)` and
        // the model list ships unchanged.
        let config: ModelConfiguration = {
            if DemoMode.isEnabled, let demoURL = DemoMode.demoStoreURL() {
                return ModelConfiguration(schema: schema, url: demoURL)
            }
            return ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }()

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // H9: discriminate the catch. SwiftData's
            // `loadIssueModelContainer` covers schema-mismatch +
            // store-corruption — both unrecoverable without a wipe.
            // Anything else (disk full, file-permission denial, unknown
            // future error types) is preserved: we DON'T wipe the
            // user's data on a transient I/O issue.
            let isLoadIssue = (error as? SwiftDataError) == .loadIssueModelContainer
            guard isLoadIssue else {
                print("[IndexApp] persistence failed (not load-issue, NOT wiping): \(error)")
                UserDefaults.standard.set(true, forKey: Self.hardErrorFlagKey)
                return Self.makeFallbackContainer(schema: schema)
            }

            // Schema-load failure — single-shot wipe + retry. Profile /
            // UserExercise / weight / workout rows all go with the
            // wipe, but HK data re-syncs from Apple Health on next
            // bootstrap and the app remains launchable. The reset
            // alert in ContentView tells the user this happened.
            print("[IndexApp] schema load failed; wiping store: \(error)")
            Self.deleteStoreFiles()
            UserDefaults.standard.set(true, forKey: storeResetFlagKey)

            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                // H8: no fatalError. Fall back to an in-memory store
                // so the app launches and ContentView can render the
                // hard-error screen with a path forward (delete +
                // reinstall, or contact support). DQ5: don't loop —
                // single-shot wipe was already attempted above.
                print("[IndexApp] post-wipe init also failed: \(error)")
                UserDefaults.standard.set(true, forKey: Self.hardErrorFlagKey)
                return Self.makeFallbackContainer(schema: schema)
            }
        }
    }()

    let modelContainer: ModelContainer = sharedContainer

    @State private var profileService = ProfileService(identity: AppDependencies.identity)
    @State private var notificationService = NotificationService.shared
    @State private var hkService = HealthKitService(
        modelContainer: sharedContainer,
        notificationService: NotificationService.shared
    )
    @State private var claudeService = ClaudeService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(profileService)
                .environment(hkService)
                .environment(notificationService)
                .environment(claudeService)
        }
        .modelContainer(modelContainer)
    }

    /// Removes the SwiftData store files for the **currently active**
    /// store (real or demo) from Application Support so the next
    /// ModelContainer init starts from scratch. Used by the
    /// migration-failure recovery path above. The other store is
    /// untouched — that's the whole point of physical isolation.
    ///
    /// File names are `<base>.store`, `<base>.store-shm`, and
    /// `<base>.store-wal` (SQLite WAL companions). Base is
    /// `default` for real mode and `Index-demo` for demo mode.
    private static func deleteStoreFiles() {
        let fm = FileManager.default
        guard let supportURL = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }

        let base = DemoMode.isEnabled
            ? DemoMode.demoStoreFilename.replacingOccurrences(of: ".store", with: "")
            : "default"

        for suffix in ["", "-shm", "-wal"] {
            let url = supportURL.appendingPathComponent("\(base).store\(suffix)")
            try? fm.removeItem(at: url)
        }
    }

    /// Last-resort in-memory ModelContainer used when the persistent
    /// store is unrecoverable. Lets the app launch so ContentView can
    /// render the hard-error screen instead of the process trapping at
    /// startup. The in-memory store is wiped on every launch — but at
    /// this point the user has already lost local data anyway, and
    /// the goal is just "show the user a path forward."
    ///
    /// The fatalError below is reachable only if the in-memory init
    /// itself fails — which requires a fundamentally broken Schema
    /// (compile-time correct, runtime catastrophic). At that point
    /// there's nothing useful to fall back to.
    private static func makeFallbackContainer(schema: Schema) -> ModelContainer {
        let memConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [memConfig])
        } catch {
            fatalError("In-memory ModelContainer init failed — schema is fundamentally broken: \(error)")
        }
    }
}
