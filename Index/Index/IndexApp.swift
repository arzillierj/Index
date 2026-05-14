import SwiftUI
import SwiftData

@main
struct IndexApp: App {
    /// Key set in ApplicationSupport-wipe recovery so ContentView can
    /// surface a one-time "your data was reset" alert on next render.
    static let storeResetFlagKey = "storeResetDueToMigrationFailure"

    let modelContainer: ModelContainer = {
        let schema = Schema(IndexSchema.models)
        // Local SwiftData store. CloudKit is intentionally NOT configured
        // yet — pending paid Developer Program enrollment. When enabled,
        // ModelConfiguration adds `cloudKitDatabase: .private(...)` and
        // the model list ships unchanged.
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // SCHEMA MIGRATION FAILED — the on-disk store can't be
            // reconciled with the current model definitions. Wipe the
            // store files and retry. Profile / UserExercise / weight /
            // workout rows all go with it, but the app remains
            // launchable; HK data re-syncs from Apple Health on next
            // bootstrap.
            print("SCHEMA MIGRATION FAILED: \(error)")
            Self.deleteStoreFiles()
            UserDefaults.standard.set(true, forKey: storeResetFlagKey)
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Fresh ModelContainer init also failed after store wipe: \(error)")
            }
        }
    }()

    @State private var profileService = ProfileService(identity: AppDependencies.identity)
    @State private var hkService = HealthKitService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(profileService)
                .environment(hkService)
        }
        .modelContainer(modelContainer)
    }

    /// Removes the SwiftData store files from Application Support so the
    /// next ModelContainer init starts from scratch. Used by the
    /// migration-failure recovery path above.
    ///
    /// The default file names are `default.store`, `default.store-shm`,
    /// and `default.store-wal` (SQLite WAL companions).
    private static func deleteStoreFiles() {
        let fm = FileManager.default
        guard let supportURL = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }

        for suffix in ["", "-shm", "-wal"] {
            let url = supportURL.appendingPathComponent("default.store\(suffix)")
            try? fm.removeItem(at: url)
        }
    }
}
