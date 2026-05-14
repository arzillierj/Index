import SwiftUI
import SwiftData

@main
struct IndexApp: App {
    let modelContainer: ModelContainer = {
        let schema = Schema(IndexSchemaV1.models)
        // Local SwiftData store. The CloudKit container is intentionally NOT
        // configured yet — pending paid Developer Program enrollment. When
        // enabled, the ModelConfiguration gets
        //   cloudKitDatabase: .private("iCloud.com.yanni.Index")
        // and IndexSchemaV1 ships unchanged (all properties default, all
        // relationships optional, no @Attribute(.unique)).
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: IndexMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
