# Index — code-derived architecture map

Objective reference for the current source. Plain prose, no history.

For known gaps and deferred work see `BACKLOG.md`. For the working agreement (build conventions, schema rules) see `CLAUDE.md`.

---

## 1. Overview

Index is a private iOS app that interprets body, fitness, and nutrition data on top of Apple's stack. iOS 26.4+ deployment target, SwiftUI + SwiftData + HealthKit, iPhone only (`TARGETED_DEVICE_FAMILY = 1`). Three modules sit under one `TabView`: **Body**, **Fitness**, **Nutrition**. The app reads HealthKit broadly and writes back only manual weight entries.

---

## 2. Build & project

- Bundle id: `com.yanni.Index`
- Marketing version: 1.0
- Xcode target name: `Index`
- Deployment target: iOS 26.4 (`IPHONEOS_DEPLOYMENT_TARGET = 26.4`)
- Application category: `public.app-category.healthcare-fitness`
- Info.plist privacy strings: `NSCameraUsageDescription`, `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`, `NSPhotoLibraryUsageDescription`
- File auto-discovery: `PBXFileSystemSynchronizedRootGroup` — new `.swift` files under `Index/Index/**/` are picked up without editing `project.pbxproj`.

Debug build command (matches `CLAUDE.md`):

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project /Users/yannis/Index/Index/Index.xcodeproj \
  -target Index \
  -sdk iphonesimulator26.5 \
  -configuration Debug build
```

Top-level repo layout:

```
Index/
├── README.md, CONTEXT.md, CLAUDE.md, PROGRESS.md, BACKLOG.md
└── Index/                                  Xcode project + sources
    ├── Index.xcodeproj/
    └── Index/
        ├── IndexApp.swift                  @main, ModelContainer
        ├── ContentView.swift               Root router + TabView
        ├── Index.entitlements              HealthKit + background delivery
        ├── Assets.xcassets/
        ├── Models/                         11 @Model classes + IndexSchema
        ├── Services/                       15 service files
        └── Views/
            ├── Body/
            ├── Fitness/
            ├── Nutrition/
            ├── Strength/
            ├── Settings/
            ├── Onboarding/
            └── Theme/
```

---

## 3. App lifecycle & persistence

### `IndexApp.swift`

`@main`. Holds a single static `sharedContainer: ModelContainer` initialized lazily on first access. The container is constructed from `Schema(IndexSchema.models)`.

Store selection at launch:

- If `DemoMode.isEnabled` is true AND `DemoMode.demoStoreURL()` resolves, the `ModelConfiguration` is built with that URL (`Index-demo.store` in Application Support).
- Otherwise the `ModelConfiguration` uses the default location (no URL passed): SwiftData places `default.store` in Application Support.

The two stores are physically separate files. Only one `ModelConfiguration` is constructed per launch, gated by the flag. Flipping the toggle in Settings calls `exit(0)`; the next launch reads the flag and opens the other store.

Container recovery:

- `try ModelContainer(for:configurations:)` is wrapped in a discriminated `do/catch`.
- `SwiftDataError.loadIssueModelContainer` → single wipe of the active store's `.store / .store-shm / .store-wal` files via `deleteStoreFiles()`, then one retry. The wipe respects which store is active (real vs demo); the other is untouched. Sets `storeResetFlagKey` so `ContentView` surfaces a one-time alert.
- Any other error → no wipe, sets `hardErrorFlagKey`, falls back to an in-memory container via `makeFallbackContainer(schema:)`. `ContentView` reads the flag and renders a hard-error screen.
- The post-wipe retry also falls back to in-memory on a second failure.

Services constructed at launch and injected into the SwiftUI environment:

- `ProfileService(identity: AppDependencies.identity)`
- `NotificationService.shared`
- `HealthKitService(modelContainer: sharedContainer, notificationService: .shared)`
- `ClaudeService()`

The `WindowGroup`'s root is `ContentView()` with `.modelContainer(modelContainer)` plus the four `.environment(...)` injections.

### `ContentView.swift`

Root router. `.task` runs once per cold start and:

1. Bails to a hard-error screen if `hardErrorFlagKey` is set.
2. Calls `profileService.refresh(in:)` to resolve the active `Profile` (or stage an orphan for migration).
3. Performs a one-shot `calorieAdjustmentKcal` sign migration (negates any positive legacy value), gated by `calorieAdjustmentSignMigratedKey`.
4. Surfaces the "Local data was reset" alert if `storeResetFlagKey` is set.
5. If `DemoMode.isEnabled` AND `!DemoDataService.isSeeded(in: modelContext)`, calls `DemoDataService.seedFreshDataset(in:)` and re-runs `profileService.refresh(in:)`.
6. If a profile exists AND `!DemoMode.isEnabled`, awaits `hkService.bootstrapIfAuthorized()`.

Routes based on state:

- Hard-error flag set → hard-error screen with a reset-all-data action.
- `profileService.orphanProfileForMigration != nil` → migration prompt (Import / Start fresh).
- Active profile with `onboardingCompleted == true` → `TabView` with three tabs, each wrapped in `IndexTabScaffold { ... }` which paints `IndexPalette.Surface.background` and ignores safe area. The `TabView`'s `.tint` switches with the active tab via `currentTabAccent`.
- Otherwise → `OnboardingView`.

Notification taps are observed via `NotificationService.tabRouteNotificationName` and routed to the matching `TabSlot`.

---

## 4. Data model

The schema list in `IndexSchema.models` contains 11 `@Model` types: `Profile`, `WeightEntry`, `DailyHealthMetrics`, `WorkoutSession`, `StrengthSession`, `ExercisePerformance`, `SetEntry`, `UserExercise`, `NutritionEntry`, `FoodProduct`, `AIUsageRecord`.

Every property has a default; every to-one relationship is optional; there are no `@Attribute(.unique)` declarations. SwiftData lightweight migration handles additive changes (new field with default, new model in the list).

### `Profile`

One per active `userId`. Stored properties: `userId`, `name`, `age`, `heightCm`, `sexRaw`, `activityLevelRaw`, `goalRaw`, `targetWeightKg`, `hasTargetWeight`, `unitsRaw`, `enabledModulesJSON`, `calorieAdjustmentKcal`, `proteinTargetG`, `eatBackWorkoutCalories`, `manualWeightLoggingEnabled`, `manualFitnessLoggingEnabled`, `notifyOnNewWorkout`, `notifyOnNewWeight`, `appleHealthAuthorized`, `onboardingCompleted`, `createdAt`. Computed accessors decode raw enum strings (`sex`, `activityLevel`, `goal`, `units`) and a JSON `Set<Module>` (`enabledModules`). Decode/encode failures of the module blob fall back to the full default set.

Enums declared in the same file: `Sex` (male/female), `ActivityLevel` (sedentary…extraActive, with Harris-Benedict multiplier), `Goal` (lose/maintain/gain), `Units` (metric/imperial), `Module` (body/fitness/nutrition).

### `WeightEntry`

One weigh-in. Stored: `date`, `weightKg`, `bodyFatPercent`, `hasBodyFat`, `leanMassKg`, `hasLeanMass`, `notes`, `sourceRaw`, `deletedFromIndex`, `hkSampleUUID: String?`. `WeightSource` enum: `manual`, `healthkit`, `renpho`.

### `WorkoutSession`

One workout. Stored: `date`, `typeRaw`, `durationMinutes`, `kcalBurned`, `hasKcal`, `avgHeartRate`, `hasHeartRate`, `maxHeartRate`, `hasMaxHeartRate`, `distanceKm`, `hasDistance`, `intensity`, `hasIntensity`, `sourceRaw`, `notes`, `deletedFromIndex`, `strengthSessionId`, `hkWorkoutUUID: String?`. `WorkoutType`: `cycling`, `running`, `swimming`, `strength`, `squash`, `other`. `WorkoutSourceKind`: `manual`, `healthkit`. `strengthSessionId` is a soft link by `String` to `StrengthSession.id`.

### `StrengthSession`

One gym session. Stored: `id: String` (UUID), `date`, `endDate`, `notes`, `inProgress`. Owns `[ExercisePerformance]?` via `@Relationship(deleteRule: .cascade, inverse: \ExercisePerformance.session)`. Helpers: `orderedPerformances`, `durationSeconds`, `durationMinutes`, `isInProgress`.

### `ExercisePerformance`

Stored: `session: StrengthSession?`, `userExerciseId: String`, `order`. Owns `[SetEntry]?` via `@Relationship(deleteRule: .cascade, inverse: \SetEntry.performance)`. Helpers: `orderedSets`, `topSetWeightKg`. `userExerciseId` is a soft link by `String` to `UserExercise.id`.

### `SetEntry`

Stored: `performance: ExercisePerformance?`, `order`, `weightKg`, `reps`, `completedAt`.

### `UserExercise`

Stored: `id: String`, `name`, `kindRaw`, `defaultRestSeconds`, `displayOrder`, `notes`, `hiddenFromLibrary`. The catalog `ExerciseCatalog.starter` is a static 10-item array (`bench-press`, `squat`, `deadlift`, `overhead-press`, `bent-over-row`, `pull-up`, `dip`, `lat-pulldown`, `leg-press`, `cable-row`). `UserExercise.fromCatalog(_:displayOrder:)` constructs a row keyed on the catalog id. `ExerciseKind`: `free`, `machine`, `bodyweight`, `assisted`.

### `DailyHealthMetrics`

Upserted once per calendar day. Stored: `date` (default `Date.distantPast`), `hrvMs`, `hasHRV`, `vo2Max`, `hasVO2Max`, `restingHeartRate`, `hasRestingHeartRate`.

### `NutritionEntry`

Stored: `date`, `label`, `kcal`, `protein`, `carbs`, `fat`, `mealTypeRaw`, `sourceRaw`, `photoEstimated`, `deletedFromIndex`. `MealType`: `breakfast`, `lunch`, `dinner`, `snack`. `NutritionSource`: `manual`, `barcode`, `photo`. `photoEstimated`, `NutritionSource.photo`, and `deletedFromIndex` on this model are marked deprecated in source but remain in the schema.

### `FoodProduct`

Barcode-keyed product cache. Stored: `barcode`, `name`, `brand`, `kcalPer100g`, `proteinPer100g`, `carbsPer100g`, `fatPer100g`, `lastUsed`, `useCount`, `unit` ("g" or "ml"). Helper `macros(forGrams:)` scales the per-100 values. A separate value type `ScannedFood` mirrors the same shape for the OFF fetch return.

### `AIUsageRecord`

Stored: `id: UUID`, `date`, `inputTokens`, `outputTokens`, `estimatedCostUSD`. One row per successful Anthropic API call.

---

## 5. Services

### `HealthKitService.swift`

`@Observable @MainActor final class`. Constructed in `IndexApp` with the shared `ModelContainer` plus `NotificationService`. Internal context comes from `modelContainer.mainContext`.

Observable state: `isAuthorized`, `isBackfilling`, `latestBodyFat`, `latestLeanMass`, `bodyFatHistory`, `leanMassHistory`.

UserDefaults keys it owns: `hk_import_workouts`, `hk_import_weight`, `hk_last_workout_sync`, `hk_workout_anchor`, `didHistoricalBackfill`. Toggles default to `true` when the key is absent.

Read types (15): `bodyMass`, `bodyFatPercentage`, `leanBodyMass`, `heartRateVariabilitySDNN`, `vo2Max`, `restingHeartRate`, `workoutType`, `heartRate`, `activeEnergyBurned`, `basalEnergyBurned`, `distanceCycling`, `distanceWalkingRunning`, `distanceSwimming`, `cyclingPower`, `sleepAnalysis`. Write type (1): `bodyMass`.

Key methods:

- `requestAuthorization() async` — requests the read+write sets; on grant calls `bootstrap()`.
- `bootstrapIfAuthorized() async` — gated bootstrap for launch.
- `fetchAll() async` — refreshes the observable composition snapshots.
- `startObservingBodyMass()` / `stopBodyMassObserver()` — `HKObserverQuery` + `enableBackgroundDelivery`. Retained so a Settings toggle-off can stop it without deleting prior rows.
- `importWorkouts()` — initial sweep since `lastWorkoutSyncKey`.
- `importHistoricalWorkouts(since:)` — one-shot backfill, gated by `didBackfillKey`.
- `startObservingWorkouts()` / `stopWorkoutObserver()` — `HKAnchoredObjectQuery`. The anchor is loaded from / saved to `workoutAnchorKey`; the anchor is **not** advanced while the workout-import toggle is off.
- `fetchDailyHealth() async` — pulls latest HRV / VO2 / resting-HR samples and upserts a `DailyHealthMetrics` row keyed on `startOfDay(today)`.
- `saveWeight(kg:date:) async throws` — writes a sample to HealthKit. Throws on rejection so the caller can surface a banner without rolling back the local row.
- `fetchSwimDetail(forWorkoutUUID:) async -> SwimDetailData?` — swim-specific enrichment: HR samples, per-lap stroke/SWOLF, per-set grouping, pool length.
- `fetchLastNightSleep() async -> TimeInterval?` — sleep `HKCategoryType(.sleepAnalysis)` between yesterday 18:00 and today 14:00. Sums only the asleep values (`asleepCore`, `asleepDeep`, `asleepREM`, `asleepUnspecified`); excludes `inBed`. Groups samples by `sourceRevision.source.bundleIdentifier` and returns the bundle with the largest summed asleep duration.
- `fetchHRSeries(forWorkoutUUID:) async -> [SwimHRSample]` — generic per-workout HR samples by UUID. Used by every workout type with HR data.

Support types in the same file: `SwimStroke`, `SwimHRSample`, `SwimLength`, `SwimSet`, `SwimDetailData`.

### `ClaudeService.swift`

`@Observable @MainActor final class`. Provides the optional AI meal-photo macro estimator.

Constants: `apiKeyAccount = "index.ai.anthropicAPIKey"` (Keychain account), `monthlyBudgetKey = "ai.monthlyBudgetUSD"` (UserDefaults key), `defaultMonthlyBudgetUSD = 2.0`, `visionModel = "claude-haiku-4-5-20251001"`, `messagesURL = https://api.anthropic.com/v1/messages`, `anthropicVersion = "2023-06-01"`. Pricing: `inputCostPerMTok = 1.00`, `outputCostPerMTok = 5.00`.

Observable state: `hasAPIKey` (mirrors Keychain).

Key methods:

- `setAPIKey(_:) throws` / `clearAPIKey()` / `apiKey() -> String?` — Keychain-backed key storage.
- `monthlyBudgetUSD: Double` — `UserDefaults`-backed read/write property; falls back to `defaultMonthlyBudgetUSD` on first read.
- `monthToDateSpendUSD(in:) -> Double` — sums `AIUsageRecord.estimatedCostUSD` for rows whose `date` falls in the current calendar month (`Calendar.dateInterval(of: .month, for: .now)`).
- `isWithinBudget(in:) -> Bool` — strict `<` comparison so a $0 budget always blocks.
- `recordUsage(inputTokens:outputTokens:in:) throws -> AIUsageRecord` — inserts an `AIUsageRecord`, calls `context.save()` and rethrows on failure.
- `cost(inputTokens:outputTokens:) -> Double` — pure-static cost computation.
- `estimateMacros(from:in:) async throws -> MacroEstimate` — pre-flight checks: throws `.demoModeActive` if `DemoMode.isEnabled`, then `.noAPIKey`, then `.budgetExceeded`. Downscales the image to ≤1024 px longest edge + JPEG (`q = 0.7`). POSTs to the Messages API with one image block + the `visionPrompt` text block. Decodes the envelope, then calls `recordUsage` BEFORE parsing the assistant content (so token cost is recorded even on parse failure). Strips optional ```json fences via `stripCodeFences`. Returns a `MacroEstimate` (`isFood`, `name`, `kcal`, `protein`, `carbs`, `fat`, `confidence`).

Error type: `ClaudeServiceError` (`LocalizedError`) cases: `noAPIKey`, `budgetExceeded`, `network(Error)`, `couldNotParse`, `notFood`, `demoModeActive`.

### `MetricsEngine.swift`

Pure-static `enum`. No state.

Body math: `bmi(weightKg:heightCm:)`, `bmiCategory(_:)`, `bmr(weightKg:heightCm:age:sex:)` (Mifflin-St Jeor), `tdee(bmr:activityLevel:)`, `leanBodyMass(weightKg:heightCm:sex:)` (Boer), `idealWeightRange(heightCm:sex:)` (Devine ±10%). Unit conversions: `kgToLbs`, `lbsToKg`, `cmToFtIn`.

`dailyTargets(profile:latestWeight:todaysWorkouts:last14DaysWeight:) -> DailyTargets` is the cross-module reconciliation. `caloriesBase = tdeeValue + profile.calorieAdjustmentKcal` (linear; no clamp). Workout kcal contribution uses Ainsworth 2011 MET values (cycling 7.0, running 9.0, swimming 8.0, squash 7.3, strength/other 5.0) capped at 1000/day, and is zeroed when `profile.eatBackWorkoutCalories` is false. The aggressive-loss buffer (`aggressiveLossBuffer(last14DaysWeight:)`) adds 200 kcal when the 14-day weekly weight-loss rate exceeds 1%/week. Protein bonuses follow per-type rules, capped at 0.6 g/kg workout bonus and 2.5 g/kg total. The return shape `DailyTargets` (`Sendable struct`) carries `calories`, `caloriesBase`, `calorieAdjustmentReason`, `protein`, `proteinBase`, `proteinAdjustmentReason`, `tdee`, `deficit`, `workoutCalories`, `trendCalories`, `workoutProteinAdded`.

### `BrainService.swift`

Pure-static `enum`. Each call returns `ModuleInsight?` (`id`, `module`, `message`). `bodyInsight(...)`, `fitnessInsight(...)`, `nutritionInsight(...)`. First-match-wins per module.

### `ProfileService.swift`

`@Observable @MainActor final class`. Holds the active `Profile` (`activeProfile`) and the staged orphan (`orphanProfileForMigration`). Methods receive a `ModelContext` per call (it does not retain one).

Lifecycle: `refresh(in:)`, `acceptMigration(in:)`, `declineMigration(in:)`, `createFreshProfile(in:)`.

Field updates (all `throws`): `updateName`, `updateAge`, `updateHeight`, `updateSex`, `updateGoal`, `updateCalorieAdjustment`, `setEatBackWorkoutCalories`, `setManualWeightLoggingEnabled`, `setManualFitnessLoggingEnabled`, `updateProteinTarget`, `updateTargetWeight`, `setModuleEnabled`. Notification toggles are async: `setNotifyOnNewWorkout`, `setNotifyOnNewWeight` request iOS permission before flipping ON.

Destructive: `resetAllData(in:) throws` wipes WeightEntry / WorkoutSession / StrengthSession (cascades) / NutritionEntry / DailyHealthMetrics / FoodProduct rows, preserving Profile + UserExercise. `deleteAccount(in:) async throws` wipes everything and signs out. `signOut() async` clears identity state.

### `NotificationService.swift`

`@MainActor @Observable final class : NSObject, UNUserNotificationCenterDelegate, Sendable`. Singleton (`static let shared`). Posts `tabRouteNotificationName` on tap so `ContentView` can swap tabs.

### `IdentityService.swift` / `DevIdentityService.swift` / `AppleSignInIdentityService.swift`

`IdentityService` protocol: `currentUserId: String?`, `isAuthenticated: Bool`, `signIn() async throws -> String`, `signOut() async`. `AppDependencies.identity` is the single seam: currently `DevIdentityService()`. `DevIdentityService` stores the UUID in Keychain (`kSecAttrAccessibleAfterFirstUnlock` + `kSecAttrSynchronizable`); a one-shot UserDefaults → Keychain migration runs at `init`. `AppleSignInIdentityService` is a non-trapping stub.

### `Keychain.swift`

Static helpers over `SecItem*`: `read(_:) -> String?`, `write(_:value:) -> Bool`, `delete(_:)`, `has(_:) -> Bool`. Service field is `Bundle.main.bundleIdentifier`; entries are `kSecClassGenericPassword` with `kSecAttrAccessibleAfterFirstUnlock` + `kSecAttrSynchronizable`.

### `SafeFormat.swift`

Static formatters that return `"—"` for non-finite or out-of-threshold values: `decimal(_:fractionDigits:threshold:)`, `int(_:threshold:)`, `percent(_:threshold:)`.

### `OpenFoodFactsService.swift`

`struct`. `fetch(barcode:) async throws -> ScannedFood`. Uses `JSONSerialization` with type-tolerant `(value as? Double) ?? (value as? Int).map(Double.init) ?? 0` parsing. Unit detection chooses "g" or "ml" from `product_quantity_unit` / `serving_quantity_unit` / `quantity_unit` with a `categories_tags` fallback. `OFFError`: `notFound`, `networkError`, `decodingFailed`.

### `DemoMode.swift`

`enum` namespace. `isEnabled: Bool` (UserDefaults key `demoModeEnabled`). `setEnabled(_:)`. `demoStoreFilename = "Index-demo.store"`. `demoStoreURL() -> URL?` resolves to Application Support. `deleteDemoStoreFiles()` removes the `.store`, `.store-shm`, and `.store-wal` companions.

### `DemoDataService.swift`

`@MainActor enum`. Three public surfaces:

- `lastNightSleepSeconds() -> TimeInterval` — day-seeded value in roughly 6h 20m – 8h 10m. Read by `BodyView` when in demo mode.
- `isSeeded(in:) -> Bool` — true when the context has at least one `Profile` row.
- `seedFreshDataset(in:) throws` — inserts one `Profile`, 10 `UserExercise` rows from `ExerciseCatalog.starter`, ~280 `WeightEntry`, ~150 `WorkoutSession` (HK-shaped: `source = .healthkit` + fake `hkWorkoutUUID`), ~25 `StrengthSession` (with `ExercisePerformance` + `SetEntry` cascade), ~1200 `NutritionEntry`, ~320 `DailyHealthMetrics`. Uses an xorshift64-style seeded RNG (`SeededRNG`) so re-runs produce the same dataset. Does **not** generate `AIUsageRecord`.

### `DemoHRSeriesGenerator.swift`

`enum`. `series(for: WorkoutSession) -> [SwimHRSample]`. Seeded by the session's `hkWorkoutUUID` (or by `date.timeIntervalSince1970` if no UUID). Returns one sample per ~20 seconds with a warmup → noisy plateau (peaks toward `maxHeartRate`) → cooldown shape. Returns `[]` if `hasHeartRate` is false. Called from `WorkoutDetailView` when `DemoMode.isEnabled`.

---

## 6. Views by module

### Shared scaffolding (`Views/Theme/`)

- `IndexPalette.swift` — `enum IndexPalette` with nested namespaces: `Brand`, `Surface` (`background`, `card`, `divider`), `Text` (`primary`, `secondary`, `tertiary`, `onAccent`), `Semantic` (`success`, `warning`, `error`), `Data` (`heartRate`, `distance`, `time`, `efficiency`, `energy`, `protein`, `carbs`, `fat`), `Module` (`body`, `fitness`, `nutrition`, `settings`), `Action` (`destructive`, `disabled`). A `Color.init(hex:)` extension also lives here.
- `IndexTypography.swift` — declares `enum IndexFont` with `hero`, `heroUnit`, `heroCaption`, `tileLabel`, `tileValue`, `tileUnit`, `sectionCap`, `rowTitle`, `rowValue`, `rowSecondary`. `hero` (56 pt), `heroUnit` (22 pt), and `tileValue` (24 pt) use fixed point sizes; the others use semantic `Font.system(.style, weight:)` so they scale with Dynamic Type. Numerical helpers carry `.monospacedDigit()`.
- `DemoBadge.swift` — small "DEMO" capsule rendered when `DemoMode.isEnabled`; collapses to nothing otherwise. Used inline next to each module's page title.
- `IndexTabScaffold` (declared inside `ContentView.swift`) — wraps each tab's root in a `NavigationStack` and paints `IndexPalette.Surface.background` with `.ignoresSafeArea()`.

### `Views/Body/`

- `BodyView.swift` — main screen. `@Query` for `WeightEntry` (filtered `!deletedFromIndex`, sorted by `date` descending) and `DailyHealthMetrics` (sorted by `date` descending). `@State lastNightSleepSeconds: TimeInterval?`. Sections in `body`:
  - `pageTitle` (with `DemoBadge`)
  - `insightSection` (Brain pill via `BrainService.bodyInsight`)
  - `heroWeight` (latest weight, gray delta vs. previous)
  - `trendChart` (30-day Swift Charts: `AreaMark` with explicit `yStart` at `weightDomain(_:).lowerBound`; chart `.clipped()`; auto-strided x-axis)
  - `metricsSection` — BMI, BMR, TDEE, Body fat, Lean mass, Time asleep. Body fat and Lean mass tiles carry `delta:` with `DeltaPlacement.inline`. Time asleep reads `lastNightSleepSeconds` (formatted as `Xh Ym`, "—" when nil).
  - `vitalsSection` — HRV, VO2 max, Resting HR, all with `deltaPlacement: .belowValue`.
  - `recentEntriesSection` — last 5 weights, tap → `WeightEntryDetailSheet`.

  Tile delta logic (declared at file scope at the bottom): `enum GoodDirection { case up, down }` and `struct TileDelta { signedAmount, formattedAbs, unit, goodDirection; arrowSystemName, isGood }`. Per-metric helpers (`bodyFatDelta`, `leanMassDelta`, `hrvDelta`, `vo2Delta`, `rhrDelta`) walk the newest two rows where the has-flag is true and return nil when the rounded change is below display precision. Direction-of-good: body fat `.down`, lean mass `.up`, HRV `.up`, VO2 max `.up`, resting HR `.down`.

  Sleep fetch lives in `loadLastNightSleep()` on `.task`: reads `DemoDataService.lastNightSleepSeconds()` when `DemoMode.isEnabled`, otherwise awaits `hkService.fetchLastNightSleep()`.

- `LogWeightSheet.swift`, `WeightHistoryView.swift`, `WeightEntryDetailSheet.swift` — manual entry sheet, full chronological history, single-entry edit/delete.

### `Views/Fitness/`

- `FitnessMainView.swift` — main screen. `@Query` for `WorkoutSession` (filtered `!deletedFromIndex`, sorted by `date` descending) and `StrengthSession`. Sections: `pageTitle` (with `DemoBadge`), `backfillBanner` (visible while `hkService.isBackfilling`), `thisWeekSection` (hero duration like `2h 53m` + sub-line `N sessions · K kcal burned`), `recentSection` (VStack of buttons over `sessions`). Routes feed taps via `.navigationDestination(item:)` to `WorkoutDetailView` or `StrengthSessionDetailView`. Log toolbar button is gated on `profile.manualFitnessLoggingEnabled`.
- `LogActivitySheet.swift`, `LogCyclingSheet.swift`, `LogOtherWorkoutSheet.swift` — manual logging entry points.
- `WorkoutDetailView.swift` — detail screen for non-strength sessions. Renders `heroSection` (date + source badge + duration hero), `heartRateSection`, `statsGrid` (SwiftUI `Grid` walked in pairs; odd trailing cell takes `gridCellColumns(2)`), optional `autoSetsRow` (swimming), `routePlaceholder` (cycling), `notesSection`, `deleteButton`. `@State hrSeries: [SwimHRSample]?` is the unified chart source. `loadSwimDetailIfNeeded()` populates `swimDetail` (which mirrors its `hrSamples` into `hrSeries`); `loadHRSeriesIfNeeded()` covers non-swim HK workouts. When `DemoMode.isEnabled` both paths short-circuit to `DemoHRSeriesGenerator.series(for:)`.
- `SwimAutoSetsSheet.swift` — per-set and per-length detail derived from `SwimDetailData`.

### `Views/Strength/`

- `ActiveStrengthSessionView.swift`, `RestTimerOverlay.swift`, `StrengthLibraryView.swift`, `AddExerciseSheet.swift`, `ExercisePickerSheet.swift`, `ExerciseDetailView.swift`, `StrengthSessionDetailView.swift` — live logging surface (timer + quick-adjust chips + "Complete set"), the user's exercise library (`!hiddenFromLibrary`), the catalog picker, per-exercise progress view, and past-session detail.

### `Views/Nutrition/`

- `NutritionMainView.swift` — main screen. `@Query` for all `NutritionEntry`, recent `WeightEntry` and `WorkoutSession`. `@Environment(ClaudeService.self)`. Composition: `pageTitle` (with `DemoBadge`), `heroRow` (Calories + Protein dual hero), `macroGrid` (Carbs + Fat tiles), `actionRow` (Camera + Enter manually), `frequentChipsSection` (top-N labels by last-30-day frequency), `todaysLogSection` (today's entries, with a "See all" `NavigationLink` to `FoodHistoryView`). `computedTargets` calls `MetricsEngine.dailyTargets(...)` once per body and threads the result through subsections. `ManualEntryPrefill` carries optional `label`, `kcal`, `protein`, `carbs`, `fat`, `mealType`, `aiConfidence` and drives the prefilled `LogMealManualSheet`. `handlePhotoCaptured` calls `claudeService.estimateMacros` and routes the result into the manual sheet or surfaces an `AIErrorAlert`.
- `BarcodeScannerView.swift` — live camera screen with two paths from one preview. AVFoundation `AVCaptureMetadataOutput` (EAN-8/13, UPC-A/E, ITF-14, Code 128, throttled at `reportThrottle = 0.15s`) feeds a SwiftUI-side stability tracker `(candidateCode, candidateFirstSeenAt, lastDetectionAt, lastFiredCode)`. When the same code has been continuously detected for `stabilityWindow = 0.6s` the `onDetect` callback fires automatically; a detection gap exceeding `gapResetWindow = 0.8s` resets the candidate. Each code fires at most once per presentation. `AVCapturePhotoOutput` + a `CameraCaptureProxy` deliver shutter captures to `onPhotoCaptured`. Overlay also offers a `PhotosUI.PhotosPicker`.
- `BarcodeResultSheet.swift` — OFF lookup with a `FoodProduct` cache (90-day freshness), quantity slider, macro display via `food.macros(forGrams:)`.
- `LogMealManualSheet.swift` — manual entry with `FieldValidation` (kcal 0–5000 required; macros 0–500 g optional). Accepts `editing: NutritionEntry?` plus optional `prefilledLabel`, `prefilledKcal`, `prefilledProtein`, `prefilledCarbs`, `prefilledFat`, `prefilledMealType`, `aiPrefillHint`.
- `FoodHistoryView.swift` — pushed from the Nutrition stack via the "See all" link. `@Query` all `NutritionEntry` sorted newest-first, grouped by `MealType` in declaration order (Breakfast → Lunch → Dinner → Snack; empty sections collapse). Tap calls `onRequestRelog(entry)` then `dismiss()`; the parent populates `manualEntryPrefill` so the new entry is dated today.
- `MealDetailView.swift` — read view for a single entry with an edit callback.

### `Views/Settings/`

- `SettingsView.swift` — sections: Profile, Goal (with eat-back toggle), Modules, Manual logging, Strength exercises (link to `StrengthLibraryView`), Apple Health (link to `HealthStatusSheet`), Notifications, AI estimation, Data (export stub + reset), Demo (toggle + reset demo data; calls `exit(0)` on confirm), Account (sign out + delete), About.
- Per-field edit sheets (10): `NameEditSheet`, `AgeEditSheet`, `HeightEditSheet`, `SexEditSheet`, `DirectionEditSheet`, `CalorieAdjustmentEditSheet` (slider bounded `[-1000, +1000]` in 50-kcal steps), `ProteinTargetEditSheet`, `TargetWeightEditSheet`, `AIAPIKeyEditSheet` (`SecureField`; never reads the stored key back), `AIBudgetEditSheet` (slider $0–$50 in $0.50 steps).
- `HealthStatusSheet` — Apple Health status + re-grant affordance. Not an edit sheet; lives in the same folder.

### `Views/Onboarding/`

- `OnboardingView.swift` — eight-step flow ending in `completeOnboarding(draft:)` (in `ContentView`) which inserts the `Profile` plus the chosen `UserExercise` rows and explicit-saves.

---

## 7. External integrations

### HealthKit

- Read types listed in section 5 (15 total, including `sleepAnalysis`).
- Write type: `bodyMass` only.
- Background delivery entitlement: `com.apple.developer.healthkit.background-delivery`.
- Usage strings: `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription` in the Info.plist.

### Anthropic API

- Endpoint: `https://api.anthropic.com/v1/messages`.
- Model id: `claude-haiku-4-5-20251001`.
- `anthropic-version` header: `2023-06-01`.
- Key location: iOS Keychain under account `index.ai.anthropicAPIKey`. Read internally by `ClaudeService.apiKey()`. The Settings UI uses `Keychain.has` to gate the "Set" vs "Configured" row and never reads the key value back.
- Cost tracking: one `AIUsageRecord` row per successful call; cost computed at insert time from token counts × per-million-token rates (`inputCostPerMTok = 1.00`, `outputCostPerMTok = 5.00`).
- Budget cap: `monthlyBudgetUSD` (UserDefaults key `ai.monthlyBudgetUSD`, default $2.00). `isWithinBudget(in:)` uses strict `<` so $0 always blocks. `estimateMacros` throws `.budgetExceeded` before the network call when month-to-date spend has reached the cap. When `DemoMode.isEnabled` it throws `.demoModeActive` before any check.

### Open Food Facts

- Endpoint: `https://world.openfoodfacts.org/api/v2/product/{barcode}.json`.
- Local cache: `FoodProduct` rows keyed on `barcode`; the result-sheet writes new rows on save with a 90-day freshness window.
