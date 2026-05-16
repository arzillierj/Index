# Index v2 — Architecture

Comprehensive map of the codebase. Every module, every service, every model, every view, the patterns binding them together, and the non-obvious decisions that won't survive a `git blame` skim. New contributor reference; current-state truth.

For build commands and the working agreement, see `CLAUDE.md`. For the phase log + deferred-question answers + post-v1 backlog, see `PROGRESS.md`.

---

## What Index is

An iOS app for someone with serious gear — Apple Watch, smart scale (RENPHO), Apple Health — who wants their data **interpreted**, not just displayed. Three modules — **Body**, **Fitness**, **Nutrition** — sit on top of Apple's stack:

- **HealthKit** is the data source (read 14 types, write `bodyMass` only).
- **CloudKit private database** is the eventual sync layer, pending paid Developer Program enrollment. Models are CloudKit-shaped today; flipping the capability is a one-line `ModelConfiguration` change.
- **Sign in with Apple** is the eventual identity provider, also pending enrollment. Identity sits behind a protocol so the swap is one line.

Each module shows raw data plus templated insight sentences from a pure-function **Brain** that reads cross-module signals.

This is the v2 rebuild. The v0 app lives at `/Users/yannis/Dashboard` and is reference-only — patterns and formulas carry over, code does not.

---

## Current state (post-Phase-7)

The app has shipped:

- All three module main screens (Body / Fitness / Nutrition), each with a colored page-level hero title, per-module accent tinting, brain insights (kept in the engine but the visible Fitness + Nutrition pills were removed in a later refactor), and a single consolidated `Settings` panel reachable from each tab.
- Onboarding (8 steps), sign-in stub, profile creation, optional exercise picker (≥1 required when Fitness enabled), Apple Health auth request.
- HealthKit auto-import: workouts via anchored observer (gated on import toggle), body mass via observer query, RENPHO body-composition grouping (same-source-bundle-id matching), one-time historical workout backfill from Jan 1 of the current year, daily-health vitals (HRV / VO2 / RHR) upserted on launch.
- Strength training: freestyle (no templates), 10-item starter catalog, soft-hide library entry, active session with rest timer + quick-adjust chips, per-set timestamp, post-session WorkoutSession mirror so the feed picks it up.
- Nutrition: barcode scanner (EAN-8 / EAN-13 / UPC-A / UPC-E / ITF-14 / Code 128), Open Food Facts lookup with 90-day local cache, manual entry sheet with macro validation, frequent-foods chip row (behavior-based, last 30 days, top 5).
- Phase 7 Settings: profile editing, goal direction, calorie adjustment (signed, deficit/surplus slider), protein target, target weight, module toggles, manual-logging toggles (hide Log button when off), eat-back-workout-calories toggle, Apple Health connection panel, notifications (workout + weight, async permission gating), data export stub, reset all data, sign out, delete account.
- Local notifications when HK observer inserts a genuinely-new workout or weigh-in (gated on profile flag + iOS permission). Tap routes to the matching tab unless the app was already active.
- Centralized color system (`IndexPalette`) and type system (`IndexFont`). SF Pro with `.monospacedDigit()` for tabular alignment (Geist Mono was tried then reverted — full-width `.` rendered "87 . 3").
- Optional AI macro estimator (foundation). `ClaudeService` exposes a Keychain-stored Anthropic API key + a hard monthly USD budget cap (UserDefaults default $2.00) + `AIUsageRecord` rows tracking spend. Settings ships the entry UI. The actual vision API call is a follow-up commit — the budget gate is built first so no code path can ship that spends without a cap.
- Audit Phase 5 hardening: 24 H-tier fixes + DQ-derived schema bumps across 5 rounds. See `PROGRESS.md` for the per-fix commit table.

What's **not** shipped yet:

- CloudKit sync (model shape is ready; flipping `cloudKitDatabase:` is the single edit when enrollment lands).
- Real Sign in with Apple (`AppleSignInIdentityService` exists as non-trapping stubs).
- Imperial units (`MetricsEngine.kgToLbs/lbsToKg/cmToFtIn` exist but no view branches on `Profile.units`).
- HR-series persistence (currently fetched lazily on swim detail view; v2 long-term plan is to persist on import).
- Custom launch screen + icon.

---

## Top-level architecture

```
┌─────────────────────────────────────────────┐
│                   BRAIN                     │
│   (MetricsEngine, BrainService — pure)      │
│   Reads all modules. Computes targets.      │
│   Returns insight sentences per module.     │
└─────┬─────────────┬─────────────┬───────────┘
      │             │             │
      ▼             ▼             ▼
┌──────────┐  ┌──────────┐  ┌──────────┐
│   BODY   │  │ FITNESS  │  │NUTRITION │
└──────────┘  └──────────┘  └──────────┘
      │             │             │
      └─────────────┴─────────────┘
                    │
                    ▼
            ┌──────────────┐
            │  HEALTHKIT   │
            │   BRIDGE     │
            └──────────────┘
```

**Direction of dependency:** Views → Models, Views → Services, Services → Models. Models never import Views or Services. The HealthKit bridge is the only boundary that touches Apple's HK types — those types do not leak past `HealthKitService.swift`.

---

## App lifecycle

### `IndexApp.swift` — entry point

`@main` struct that owns the `ModelContainer` lifecycle, constructs the long-lived services, and injects them into the view tree via `.environment`.

- `sharedContainer` — `static let` lazy `ModelContainer`. Initialized once on first access. Two-tier recovery:
  - Discriminated `do/catch` on `SwiftDataError.loadIssueModelContainer` (schema mismatch / store corruption) triggers a single-shot wipe + retry. Audit H9.
  - Any other error (disk full, file-permission, unknown future type) routes to an in-memory fallback. The `hardErrorFlagKey` UD flag tells `ContentView` to render the hard-error screen instead of letting writes silently disappear. Audit H8.
  - Single-shot wipe — no three-strikes loop. Audit DQ5.
- `@State profileService = ProfileService(identity: AppDependencies.identity)` — the identity protocol is the swap seam for Sign in with Apple.
- `@State notificationService = NotificationService.shared` — singleton because HealthKitService also needs the same instance (registered as `UNUserNotificationCenterDelegate`).
- `@State hkService = HealthKitService(modelContainer: sharedContainer, notificationService: .shared)` — constructor injection. No more side-channel mutation from a view's `.task` (audit H10).
- All three services injected as `.environment(...)` so `@Environment(ProfileService.self)` works in any view.

### `ContentView.swift` — root router

Decides which screen to show based on identity + profile state:

1. **Hard-error screen** if `hardErrorFlagKey` is set — rendered with a "Reset all data and restart" button that wipes ApplicationSupport store files and exits, forcing a clean ModelContainer init on next launch.
2. **Migration prompt** if `ProfileService.orphanProfileForMigration` is non-nil — when exactly one Profile exists on device but its `userId` doesn't match the current `IdentityService.currentUserId`. Most likely cause: Personal Team SIWA `userIdentifier` changed to the paid-team one. User picks "Import previous data" (re-key the orphan via `acceptMigration`) or "Start fresh" (delete + create new via `declineMigration`).
3. **Tab view** if a profile exists and `onboardingCompleted == true`. Three tabs, each gated on `Profile.enabledModules`. The active tab's accent color drives the `.tint(...)` on `TabView`.
4. **OnboardingView** otherwise.

Three other responsibilities live here:

- **HK bootstrap gate** — `hkService.bootstrapIfAuthorized()` only fires when `profileService.activeProfile != nil`. Audit H11 prevents HK observers from mirroring into a profile-less store.
- **One-time `calorieAdjustmentKcal` sign migration** — for installs from before the sign-fix commit. If the UD flag is unset AND the value is positive, negate it (legacy `+500` deficit becomes `-500` under the new convention). Flag is set unconditionally afterwards so fresh installs (no profile yet) also mark migration done.
- **Notification-tap routing** — listens to `NotificationService.tabRouteNotificationName` via `.onReceive(NotificationCenter.default.publisher(...))` and swaps `selectedTab` to `body` / `fitness` / `nutrition`.

`completeOnboarding(draft:)` is the only place new `Profile` rows are written. Pulls every field off `OnboardingDraft`, inserts the Profile + the picked `UserExercise` rows, then explicit `try modelContext.save()` (audit H12 — SwiftData autosave is "next runloop tick when dirty"; an app kill in that window would lose the entire onboarding result).

---

## Models — 10 SwiftData classes (`Models/`)

All `@Model` classes follow the CloudKit-shape rules: every property has a default, every to-one relationship is optional, no `@Attribute(.unique)`. Lightweight migration only — additive changes (new fields / new types) backfill defaults automatically; renames / deletes / type changes require a redesign rather than a migration.

### `IndexSchema.swift`
Single source of truth for the model list. `IndexSchema.models` is a static `[any PersistentModel.Type]` passed to `Schema(models)` in `IndexApp`. The original V1/V2/V3 + `IndexMigrationPlan` design generated "Duplicate version checksums detected" because each `VersionedSchema` snapshot returned the same compile-time Swift class types; replaced with a single flat list relying on SwiftData lightweight migration.

### `Profile.swift`
One per active `userId`. Holds all personalization + every toggle the user controls. Properties are mostly plain — `enabledModules` is the interesting one: stored as a JSON-encoded `[String]` blob in `enabledModulesJSON` and exposed as a computed `Set<Module>` via get/set. Decode failures fall back to the full default set (`["body","fitness","nutrition"]`) so a malformed blob doesn't strand the user with zero tabs; encode failures fall back to the same literal so the round-trip stays byte-stable (audit H19).

Enums declared in this file: `Sex`, `ActivityLevel` (with Harris-Benedict multiplier table), `Goal` (lose/maintain/gain), `Units` (metric/imperial), `Module` (body/fitness/nutrition).

Additive schema bumps shipped through Phase 7:

- `hasTargetWeight: Bool = false` + `targetWeightKg: Double = 0` — gating pattern so an unset target doesn't pollute MetricsEngine math.
- `calorieAdjustmentKcal: Double = 0` — **signed** post-fix. Negative = deficit (cutting), positive = surplus (bulking), 0 = maintenance. Always added to TDEE: `target = TDEE + workouts + adjustment`. The one-time `ContentView.task` migration negates legacy positive values.
- `eatBackWorkoutCalories: Bool = false` — when off, `MetricsEngine.dailyTargets` zeros the workout-kcal contribution. Default false because cutters (the most common careful tracker) should NOT eat back. SCHEMA: additive.
- `manualWeightLoggingEnabled: Bool = false` + `manualFitnessLoggingEnabled: Bool = false` — gate the "Log" toolbar button in BodyView / FitnessMainView. Default off (automated sources are the primary write path). SCHEMA: additive.
- `notifyOnNewWorkout: Bool = false` + `notifyOnNewWeight: Bool = false` — local notifications fire when HK observer inserts a genuinely-new row. iOS permission requested when the user first flips the toggle ON. SCHEMA: additive.

### `WeightEntry.swift`
One weight log. Has-Foo companions on `bodyFatPercent` (via `hasBodyFat`) and `leanMassKg` (via `hasLeanMass`). `source: WeightSource` is `manual / healthkit / renpho`. RENPHO is detected from the HK sample's `sourceRevision.source.bundleIdentifier` (`com.renpho.RenphoHealth`, `com.qnniu.renpho`) and source name, case-insensitive.

`hkSampleUUID: String?` (audit H5) is the primary dedup key for HK auto-imports. ±5-min date window is the secondary fallback for manual rows and pre-UUID-field legacy rows.

`deletedFromIndex: Bool = false` is the swipe-as-tombstone flag. `@Query` filters on `!deletedFromIndex` to hide it from the UI; HK dedup predicates do **not** filter on this flag, so a swipe-deleted row prevents re-import resurrection of the same Apple Health sample.

### `WorkoutSession.swift`
One workout, manual or HK-imported. Six `WorkoutType` cases: `cycling`, `running`, `swimming`, `strength`, `squash`, `other`.

`hkWorkoutUUID: String?` is the primary dedup key; ±2-min date window is the secondary. Audit baseline.

`strengthSessionId: String?` is a **soft link** to `StrengthSession.id` when `type == .strength`. Soft because the parallel StrengthSession may be hard-deleted independently (cascades into its performances + sets), while the WorkoutSession is only soft-deleted via `deletedFromIndex`. Read sites guard for the dangling case ("Strength session deleted").

Has-Foo flags gate every optional numeric: `hasKcal`, `hasHeartRate`, `hasMaxHeartRate`, `hasDistance`, `hasIntensity`.

`source: WorkoutSourceKind` is `manual / healthkit`. Manual logs from `LogCyclingSheet` / `LogOtherWorkoutSheet` insert with `source = .manual`; HK observer inserts with `source = .healthkit`.

### `StrengthSession.swift`
One gym session. Stable string `id` (UUID) so the `WorkoutSession.strengthSessionId` soft-link survives.

Cascade-deletes `[ExercisePerformance]?` via `@Relationship(deleteRule: .cascade, inverse: \.session)`. The performances in turn cascade to `[SetEntry]?`. Hard-deleting a StrengthSession therefore wipes its performances + sets in one operation.

`inProgress: Bool = true` (audit H16) replaces the previous `endDate <= date` heuristic that lied about state on a fast CPU (a session created and immediately ended in the same tick returned `true` for `inProgress`). The flag is set explicitly by `ActiveStrengthSessionView.endSession`.

Computed helpers: `orderedPerformances`, `durationMinutes`, `durationSeconds`, `isInProgress`.

### `ExercisePerformance.swift`
One (session, userExercise) pair. `userExerciseId: String` is a soft link to `UserExercise.id` — removing a UserExercise from the library doesn't cascade through old session history; the read site renders "Unknown exercise" when dangling.

Cascade-deletes `[SetEntry]?`.

Computed helpers: `orderedSets`, `topSetWeightKg`.

### `SetEntry.swift`
One completed set. `weightKg: Double`, `reps: Int`, `completedAt: Date`. `weightKg` can be negative for assisted exercises (subtracts from bodyweight).

### `UserExercise.swift`
User's personal exercise library. `id` is the catalog id verbatim ("bench-press", "squat", "deadlift", ...). 10-item starter catalog defined in `ExerciseCatalog.starter`: 5 free-weight, 3 machine, 2 bodyweight.

`hiddenFromLibrary: Bool = false` is the soft-hide flag (audit DQ4). Library + picker `@Query` filter on `!hiddenFromLibrary`. Swiping a library row sets it to true. `AddExerciseSheet` un-hides if the user re-adds the same catalog id instead of inserting a duplicate (catalog ids are deterministic; duplicate inserts would break soft-link resolution in old session history).

Enums in this file: `ExerciseKind` (free / machine / bodyweight / assisted), `ExerciseDefinition` (catalog entry shape), `ExerciseCatalog` (static `starter` array + `byId(_:)` lookup).

`notes: String = ""` is `// DEPRECATED:` — no path reads or writes it.

### `DailyHealthMetrics.swift`
One row per calendar day. HRV (SDNN) in ms, VO2 max, resting HR. Upserted from `HealthKitService.fetchDailyHealth()` keyed on `startOfDay(local)`.

Has-Foo companions on each numeric field: `hasHRV`, `hasVO2Max`, `hasRestingHeartRate`.

`date` property default is `Date.distantPast` deliberately (audit H20) — a sentinel value so any latent migration is visible instead of collapsing every back-filled row to a single timestamp on the upsert key. Real inserts always pass `init(date: startOfDay)`.

### `NutritionEntry.swift`
One meal/food log. `mealType: MealType` (breakfast / lunch / dinner / snack), `source: NutritionSource` (manual / barcode / photo-deprecated).

`photoEstimated: Bool` and `NutritionSource.photo` are `// DEPRECATED:` (audit H3) — the photo-to-macros feature was cut from v1 (`Services/ClaudeService.swift` + `Models/PhotoEstimateLog.swift` deleted in audit H1 + H2). Fields stay per the schema rules ("never delete a field"); the enum case stays as a decoder fallback if any persisted row from a pre-deletion build is ever encountered.

`deletedFromIndex` is also `// DEPRECATED:` here — Nutrition entries never mirror to HealthKit (Index doesn't write food back), so there's no dedup contract a tombstone could protect. The swipe path uses `context.delete(entry)` for hard delete.

### `FoodProduct.swift`
Barcode-keyed product cache. Per-100g (or per-100ml) macros. `useCount + lastUsed` track frequency — but those metrics are not currently consumed by the Frequent chips on Nutrition main (those derive directly from `NutritionEntry` label frequency over the last 30 days; FoodProduct metrics are a future hook).

`unit: String` records solid vs liquid ("g" or "ml") so cached scans default the quantity input correctly. Detection happens in `OpenFoodFactsService` — checks `product_quantity_unit` / `serving_quantity_unit` / `quantity_unit` for ml-like keywords, falls back to `categories_tags` matching a liquid set (beverages, drinks, sodas, syrups, etc.).

`ScannedFood` is a separate `Sendable` value type returned by the OFF fetch (`OpenFoodFactsService.fetch(barcode:)`) — its `macros(forGrams:)` scales the per-100 values to a user-picked quantity.

---

## Services (`Services/`)

### `IdentityService.swift` — protocol + types

Identity is behind a protocol so the dev stub and the real Sign in with Apple implementation are swap-equivalent.

```swift
protocol IdentityService: AnyObject, Sendable {
    var currentUserId: String? { get }
    var isAuthenticated: Bool { get }
    func signIn() async throws -> String
    func signOut() async
}
```

`IdentityError` exposes `signInFailed`, `notImplemented`, `cancelled`. `AppDependencies.identity` is the single line that changes when the swap happens — `static let identity: any IdentityService = DevIdentityService()` flips to `AppleSignInIdentityService()`.

### `DevIdentityService.swift`

UUID-based stand-in. Stores the UUID in **Keychain** with `kSecAttrAccessibleAfterFirstUnlock` + `kSecAttrSynchronizable` (audit H21) — identity survives uninstall + reinstall when iCloud Keychain is on, matching the eventual `AppleSignInIdentityService` survivor semantics.

One-shot UserDefaults → Keychain migration on init (copies legacy UD value, deletes UD entry) for installs from before the H21 fix.

`signIn()` mints a UUID on first call and persists it to Keychain. `signOut()` clears the Keychain entry.

### `AppleSignInIdentityService.swift`

Stubbed implementation awaiting paid Developer Program enrollment. Audit H7 — **non-trapping** stubs (no `fatalError`). `currentUserId` reads Keychain; `isAuthenticated` returns false; `signIn()` throws `IdentityError.notImplemented`; `signOut()` is a no-op.

`FUTURE:` comments at every stub describe the post-enrollment shape: `ASAuthorizationAppleIDRequest`, `ASAuthorizationController`, persist `userIdentifier` to Keychain with iCloud sync, revocation detection via `provider.getCredentialState(forUserID:)`.

### `ProfileService.swift`

Source of truth for the active Profile. Does **not** hold a `ModelContext` — every method takes one. This way a single instance survives container rebuilds (e.g., erase-all-data flows).

Lifecycle:

- `refresh(in:)` — looks up the Profile whose `userId == identity.currentUserId`. If no exact match but exactly one orphan exists, stages it for migration in `orphanProfileForMigration` (most likely cause: Personal Team SIWA `userIdentifier` changed to the paid-team one).
- `acceptMigration(in:)` — re-keys the orphan's `userId` to the current identity. Audit H6: explicit `try context.save()` so a kill window doesn't lose the re-key.
- `declineMigration(in:)` — deletes the orphan, creates a fresh Profile. Same transactional save.
- `createFreshProfile(in:)` — onboarding-completion path. Inserts a new Profile keyed to the current identity. Caller is responsible for the explicit save (audit H12, done in `ContentView.completeOnboarding`).

Phase 7 update methods, all `throws ProfileUpdateError`:

- `updateName`, `updateAge`, `updateHeight`, `updateSex`, `updateGoal`, `updateCalorieAdjustment`, `updateProteinTarget`, `updateTargetWeight` — single-field updates with explicit save.
- `setModuleEnabled(_:enabled:in:)` — adds/removes from `Profile.enabledModules`.
- `setEatBackWorkoutCalories`, `setManualWeightLoggingEnabled`, `setManualFitnessLoggingEnabled` — Bool toggles.
- `setNotifyOnNewWorkout`, `setNotifyOnNewWeight` — `async throws`. On flip-ON they request iOS permission first via `NotificationService.requestPermission()`; on denial they throw `PermissionError.denied` so the caller (Settings) can surface the one-time "enable in iOS Settings" alert and leave the toggle off.

Destructive paths:

- `resetAllData(in:) throws` — wipes WeightEntry, WorkoutSession, StrengthSession (+ cascade ExercisePerformance + SetEntry), NutritionEntry, DailyHealthMetrics, FoodProduct. **Preserves** Profile and UserExercise library. HK previously-imported rows return on next observer fire if HK auth is still granted (UUID dedup keeps re-imports from duplicating).
- `deleteAccount(in:) async throws` — wipes everything including Profile + UserExercise, signs out of identity, clears `activeProfile`.
- `signOut() async` — clears identity state, sets `activeProfile = nil`. Profile rows remain on disk (become orphan-eligible on the next sign-in if a different userId comes back). ContentView observes the nil profile and routes to OnboardingView.

### `HealthKitService.swift`

The HK boundary. `@MainActor @Observable`. Takes a `ModelContainer` at construction (audit H10) plus a `NotificationService` for post-insert notifications.

**Read types** (14): bodyMass, bodyFatPercentage, leanBodyMass, heartRateVariabilitySDNN, vo2Max, restingHeartRate, workoutType, heartRate, activeEnergyBurned, basalEnergyBurned, distanceCycling, distanceWalkingRunning, distanceSwimming, cyclingPower.

**Write types** (1): bodyMass only — manual weight mirrors back to Apple Health.

Published state via `@Observable`:
- `isAuthorized: Bool` — `.sharingAuthorized` status for bodyMass write (the most reliable single-type probe; HK doesn't expose per-read-type auth).
- `isBackfilling: Bool` — true during the one-time historical workout import (`importHistoricalWorkouts(since:)`). Drives the FitnessMainView banner.
- `latestBodyFat / latestLeanMass: (value, date)?` — most recent samples from any source, surfaced on BodyView body composition tiles.
- `bodyFatHistory / leanMassHistory: [(date, value)]` — 90-day history (chart-ready).

Auth flow:
- `requestAuthorization()` — onboarding step 8 path. Sets `isAuthorized` and runs `bootstrap()` on grant.
- `bootstrapIfAuthorized()` — app-launch path. Verifies prior authorization and runs `bootstrap()` if so.
- `bootstrap()` private — runs `fetchAll()`, `fetchDailyHealth()`, the one-time historical workout backfill (if the `didBackfillKey` UD flag is unset), the initial `importWorkouts()` sweep, then arms the body-mass and workout observers (each gated on its own toggle).

Body mass observer:
- `startObservingBodyMass()` — arms `HKObserverQuery` + `store.enableBackgroundDelivery`. Idempotent (early-returns if already armed).
- `stopBodyMassObserver()` — Settings toggle-off (audit DQ10 — stops new delivery, does NOT delete already-imported rows).
- `handleNewBodyMass()` private — the observer fire handler. Fetches the latest bodyMass sample, groups same-source-bundle-id body-fat and lean-mass samples within ±5 min, computes the `WeightSource` (RENPHO detection via bundle id / source name case-insensitive), runs two-tier dedup (UUID primary, ±5-min secondary), inserts the `WeightEntry`, then calls `maybeNotifyNewWeight` (gated on `Profile.notifyOnNewWeight` + iOS auth).

Workout import (three entry points, all routing through `processHKWorkout(_:context:notifyOnInsert:)`):
- `importHistoricalWorkouts(since:)` — one-time backfill since Jan 1 of the current year. Calls `processHKWorkout(..., notifyOnInsert: false)` so a 50+ workout backfill doesn't surface as 50 banners. Sets `isBackfilling = true` for the duration.
- `importWorkouts()` — initial bootstrap sweep since `lastWorkoutSyncKey` (defaults 7 days back on first run). Calls with `notifyOnInsert: true` — the user expects to see anything that arrived while the app was closed.
- `startObservingWorkouts()` — anchored observer. Same handler for both `resultsHandler` and `updateHandler`. Gated on the workout import toggle; if the toggle is off the anchor is **not** advanced (audit baseline: prevents samples arriving in the off-window from being permanently skipped). Calls with `notifyOnInsert: true`.

`processHKWorkout(_:context:notifyOnInsert:)` private — two-tier dedup (`hkWorkoutUUID` primary, ±2-min date-window secondary, neither filtering on `deletedFromIndex`), HR / kcal / distance enrichment via `workout.statistics(for:)`, max-HR fetch via `fetchMaxHeartRate(start:end:)`, type mapping via `mapWorkoutType(_:)`. Inserts a `WorkoutSession`, then calls `maybeNotifyNewWorkout` if requested.

Apple Watch workout-type mapping:

| HKWorkoutActivityType | Index `WorkoutType` |
|---|---|
| `.cycling` | `.cycling` |
| `.running`, `.walking` | `.running` |
| `.swimming`, `.swimBikeRun` | `.swimming` |
| `.squash` | `.squash` |
| `.traditionalStrengthTraining`, `.functionalStrengthTraining`, `.crossTraining`, `.highIntensityIntervalTraining`, `.coreTraining` | `.strength` |
| anything else | `.other` |

Hiking, yoga, pilates, tennis, badminton, racquetball, table tennis, rowing, elliptical, stair-stepping all map to `.other` deliberately — none drive the protein-add bonus the way strength training does.

Notification fires:
- `maybeNotifyNewWeight(weightKg:previousKg:)` private — fetches the active profile, checks `notifyOnNewWeight`, checks `notificationService.isAuthorized()`, schedules a "New weigh-in" notification with optional `(±delta from previous)` suffix.
- `maybeNotifyNewWorkout(type:durationMinutes:kcal:avgHR:)` private — same gate pattern. Schedules a "New workout" notification with `{type}, {duration}m · {kcal} kcal · {avgHR} avg BPM` body. Missing fields drop their segment.
- `fetchActiveProfile()` private — `FetchDescriptor<Profile>` returns the first row with `onboardingCompleted == true`. Couples HK to Profile only via this read; ProfileService isn't injected (the read is small and per-notification).

Daily health vitals:
- `fetchDailyHealth()` — runs on every cold launch (cheap). Reads latest HRV / VO2 / resting HR. Upserts `DailyHealthMetrics` keyed on `startOfDay(today)`.

Write path:
- `saveWeight(kg:date:) async throws` (audit H4) — mirrors a manual weight write to Apple Health. Returns normally on success. Throws on HK rejection (auth not granted, sample format invalid). Caller (`LogWeightSheet`) keeps the local entry regardless and surfaces a non-blocking banner — Apple Health is a peer, not master (DQ3).

Swim detail enrichment (lazy, for WorkoutDetailView swim flow):
- `fetchSwimDetail(forWorkoutUUID:) async -> SwimDetailData?` — fetches the original HKWorkout by UUID via `HKSampleQuery`, then walks the workout's `events: [HKWorkoutEvent]` and `metadata` to build lap (`SwimLength`) and set (`SwimSet`) data. Stroke detection from per-lap metadata, SWOLF aggregation per set, average HR sampling, pace per 100m, pool length detection (workout metadata first, per-lap fallback). Returns nil on missing UUID or auth-state failure.

Persistent state in UserDefaults:
- `importWorkoutsKey` ("hk_import_workouts") — workout import toggle. Default ON.
- `importWeightKey` ("hk_import_weight") — weight import toggle. Default ON.
- `lastWorkoutSyncKey` ("hk_last_workout_sync") — cutoff for the initial sweep.
- `workoutAnchorKey` ("hk_workout_anchor") — anchored-query anchor blob. Loaded on observer arm; saved on every fire.
- `didBackfillKey` ("didHistoricalBackfill") — one-shot historical-backfill flag.

### `MetricsEngine.swift`

Pure-static math. No state, no fetching — callers pass `@Query` data in.

Body math (ported verbatim from v0 with citations preserved):
- `bmi(weightKg:heightCm:)` → `kg / m²`. WHO 1995 categories via `bmiCategory(_:)`.
- `bmr(weightKg:heightCm:age:sex:)` → Mifflin-St Jeor 1990. `Male: 10W + 6.25H − 5A + 5`, `Female: 10W + 6.25H − 5A − 161`.
- `tdee(bmr:activityLevel:)` → `bmr × activityMultiplier` (Harris-Benedict, table in `ActivityLevel`).
- `leanBodyMass(weightKg:heightCm:sex:)` → Boer 1984. Used as a fallback when HK doesn't provide lean mass.
- `idealWeightRange(heightCm:sex:)` → Devine 1974 ±10%.

Unit conversions: `kgToLbs`, `lbsToKg`, `cmToFtIn` — present for the imperial-units feature flag, not currently called by any view (no `Profile.units` branching yet).

Cross-module target reconciliation:
- `dailyTargets(profile:latestWeight:todaysWorkouts:last14DaysWeight:) -> DailyTargets`
  - Base TDEE from latest weight (falls back to target weight or 75 kg sentinel).
  - **Signed adjustment**: `caloriesBase = max(safeFloor, tdeeValue + adjustment)`. The 2026 sign-fix migration runs once in `ContentView.task` to flip legacy positive values to negative.
  - Workout calories via MET × bodyweight × hours (cycling 7.0, running 9.0, swimming 8.0, squash 7.3, strength/other 5.0; capped at 1000 kcal/day). **Gated on `profile.eatBackWorkoutCalories`** — when off, workout contribution is 0.
  - Aggressive-loss buffer (`+200 kcal` when 14-day weekly weight loss > 1%) — guards against under-fueling on fast cuts.
  - Workout protein bonus: strength `+0.4 g/kg`, endurance ≥60min `+0.3 g/kg`, endurance <60min `+0.2 g/kg`, squash time-based, other `+0.2 g/kg`. Capped at `+0.6 g/kg` workout-bonus, `2.5 g/kg` total.

`DailyTargets` is the return shape: `calories`, `caloriesBase`, `calorieAdjustmentReason`, `protein`, `proteinBase`, `proteinAdjustmentReason`, `tdee`, `deficit` (signed adjustment under the new convention; name kept for backwards compat — no external consumer reads it), `workoutCalories`, `trendCalories`, `workoutProteinAdded`.

### `BrainService.swift`

Pure-static rules engine producing one `ModuleInsight?` per module. First-match-wins priority. Strict templates — no LLM, no free-form generation.

`ModuleInsight`: stable per-rule `id` (for a future dismiss-state layer), `module: Module`, `message: String`.

Body rules (first match wins):
1. `body.target_eta` — has a target weight + 14-day trend points to it. ETA in days computed from daily rate. Caps at 365 days.
2. `body.hrv_down` — latest HRV is >10% below the 7-day baseline. Suggests lighter training.
3. `body.hrv_up` — latest HRV is >10% above the 7-day baseline.
4. `body.stable` — 14-day weight range under 0.5 kg.

Fitness rules:
1. `fitness.hrv_recovery` — HRV down + ≥3 workouts this week. Suggests a recovery day.
2. `fitness.strong_week` — ≥4 workouts this week.
3. `fitness.quiet_week` — <2 this week vs ≥3 last week.
4. `fitness.on_pace` — 2–3 sessions this week.

Nutrition rules:
1. `nutrition.workout_adjustment` — `targets.workoutCalories > 0`. Auto-hides when `eatBackWorkoutCalories` is off (MetricsEngine zeros the value).
2. `nutrition.fast_loss` — aggressive-loss buffer added (+200 kcal).
3. `nutrition.low_protein` — `calorieAdjustmentKcal < 0` (cutting) + 3+ days under 80% of protein target in the last 3. Flipped to `< 0` after the sign-convention fix.
4. `nutrition.meal_gap` — 4+ hours since last meal during waking window (08:00–20:00 local).

Note: Brain insight pills are no longer rendered on FitnessMainView or NutritionMainView (removed in a later refactor). The engine still produces them — a future surface can consume.

### `NotificationService.swift`

iOS local-notification gateway. `@MainActor @Observable` with a `static let shared` singleton because both `IndexApp`'s `@State` injection AND `HealthKitService`'s construction-time dependency need the same registered `UNUserNotificationCenterDelegate`.

`init()` sets `UNUserNotificationCenter.current().delegate = self` (must be done before any tap can occur). Otherwise stateless.

Permission flow:
- `requestPermission() async throws` — checks current authorization, returns early if already authorized, throws `PermissionError.denied` if previously denied (so the caller can surface the one-time "enable in iOS Settings" alert without re-prompting). If `.notDetermined`, calls `UNUserNotificationCenter.requestAuthorization(options: [.alert, .sound, .badge])`.
- `isAuthorized() async -> Bool` — read-only check used by HK observer paths before scheduling. Falls through to false on `.denied` / `.notDetermined`.

Scheduling:
- `scheduleNewWorkout(typeLabel:durationMinutes:kcal:avgHR:)` — schedules a "New workout" notification with body `{type}, {Nm} · {kcal} kcal · {avgHR} avg BPM`. Missing fields drop their segment (kcal/avgHR absent for some manual swim logs). Tap routes to fitness.
- `scheduleNewWeight(weightKg:deltaKg:)` — "New weigh-in", body `{kg} kg (+/-{delta} from previous)`. Delta omitted on the first weigh-in ever (no prior entry to compare). Tap routes to body.
- `schedule(content:idPrefix:)` private — wraps `UNUserNotificationCenter.add(_:)` with a 1-second trigger.

Tap routing:
- `tabRouteNotificationName: Notification.Name` — posted on tap with `destinationTab` in userInfo.
- `userNotificationCenter(_:willPresent:withCompletionHandler:)` — foreground presentation returns `[.banner, .sound]` so the user sees the alert even when the app is active.
- `userNotificationCenter(_:didReceive:withCompletionHandler:)` — tap handler. Reads `applicationState`; if `.active` (already foreground), skips the route post to avoid yanking the user across tabs. Otherwise posts the broadcast that `ContentView.onReceive` picks up.

### `SafeFormat.swift`

Defensive formatters for any `Int(Double)` display path. Returns `"—"` for non-finite (NaN, Infinity) or out-of-threshold values. Floor against the 2026-05-14 incident where a `WeightEntry.weightKg` of ~5×10³⁸ trapped `Int(kg)` in BodyView's formatter and broke the launch path.

- `decimal(_:fractionDigits:threshold:)` — formats `Double` to a decimal string (default threshold `1e9`, 1 fraction digit).
- `int(_:threshold:)` — formats `Double` as integer (default threshold `1e9`).
- `percent(_:threshold:)` — formats as percent without the `%` (default threshold `1e6`).

### `OpenFoodFactsService.swift`

OFF API client. Verbatim v0 port — `JSONSerialization` + type-tolerant `(value as? Double) ?? (value as? Int).map(Double.init) ?? 0` parsing. A v2 strict-Codable rewrite was tried and returned zeros for half the products; reverted.

- `fetch(barcode:) async throws -> ScannedFood` — GET `https://world.openfoodfacts.org/api/v2/product/{barcode}.json`. Parses `product.nutriments.{energy-kcal_100g, proteins_100g, carbohydrates_100g, fat_100g}` plus name + brand. Throws `OFFError.notFound` for `status == 0`, `.networkError` for non-200, `.decodingFailed` for malformed JSON.
- `detectUnit(...)` — checks `product_quantity_unit` / `serving_quantity_unit` / `quantity_unit` for ml-like (`ml`, `cl`, `l`) or g-like (`g`, `kg`, `mg`), falls back to `categories_tags` matching a liquid set. Returns "g" or "ml" string for the `FoodProduct.unit` cache.

`OFFError` enum: `notFound`, `networkError`, `decodingFailed`.

---

## Theme (`Views/Theme/`)

### `IndexPalette.swift`

Single source of truth for every color. Hex strings live nowhere else.

Namespaces (each is a nested `enum` with `static let` colors):
- `Brand` — `primary` (#1E3A8A French Blue), `secondary` (#FCB07E Sandy Coral).
- `Surface` — `background` (#FAF8F5 alabaster page), `card` (#EBE9E9 warm gray), `divider` (#D6D3CE).
- `Text` — `primary` (#1A1A1A), `secondary` (#6E6E73), `tertiary` (#AEAEB2), `onAccent` (#FFFFFF).
- `Semantic` — `success` (#34C759), `warning` (#FF9500), `error` (#FF3B30).
- `Data` — stable per-metric colors that do NOT change per module: `heartRate` (red), `distance` (blue), `time` (orange), `efficiency` (teal — SWOLF), `energy` (orange), `protein` (purple), `carbs` (yellow), `fat` (green).
- `Module` — per-tab accents: `body` (French Blue), `fitness` (Sandy Coral), `nutrition` (Teal), `settings` (French Blue, same as Body).
- `Action` — `destructive` (red), `disabled` (gray).

`Color(hex:)` extension lives in this file too.

Tab tint switching is driven by `ContentView.currentTabAccent` (computed from `selectedTab`) and applied via `.tint(currentTabAccent)` on `TabView`. Settings overrides X-dismiss buttons explicitly to `Text.secondary` so they don't inherit the tinted Button label color.

### `IndexTypography.swift`

Centralized type system. SF Pro across the board with `.monospacedDigit()` on every numerical helper for tabular alignment. Geist Mono was tried then reverted (its full-width `.` rendered "87 . 3" with floaty gaps; reverting to SF Pro + monospacedDigit kept tabular figures without the decimal artifact).

Token set (point sizes are the contract — no raw `.font(.system(size:))` allowed on numerical sites):

- `hero` — 56pt bold, monospacedDigit. Module hero numerals ("87.3", "2h 53m", "2215", "173").
- `heroUnit` — 22pt regular. "kg" / "kcal" / "g" after a hero.
- `heroCaption` — 15pt regular, monospacedDigit. "3 days ago", "/ 2137 kcal", "4 sessions · 1865 kcal burned".
- `tileLabel` — 13pt medium. "BMI", "Carbs", "HRV", "Calories".
- `tileValue` — 24pt semibold, monospacedDigit. Tile numbers.
- `tileUnit` — 13pt regular. Unit suffix next to a tile value.
- `sectionCap` — 12pt semibold. Section captions (callers add `.kerning(0.8)` and pass uppercase literals — no `.textCase` modifier so SwiftUI doesn't double-uppercase).
- `rowTitle` — 17pt regular. List-row titles.
- `rowValue` — 17pt regular, monospacedDigit. List-row values.
- `rowSecondary` — 13pt regular, monospacedDigit. Row sub-line / time labels.

---

## Views (`Views/`)

### Module main views

#### `Views/Body/BodyView.swift`
Body module main screen. Composition:
- `pageTitle` — colored "Body" heading at the top (French Blue).
- `insightSection` — Brain pill ("HRV down 12% — consider lighter training", etc.) when one fires.
- `heroWeight` — latest weight in 56pt blue + "kg" suffix + relative date + delta-from-previous.
- `trendChart` — 30-day weight trend (`Swift Charts`) with body-blue line + 25%-opacity area gradient. Auto-strides x-axis ticks to ~4 across the visible range.
- `metricsSection` — BMI / BMR / TDEE / Body fat / Lean mass / Ideal range grid.
- `vitalsSection` — HRV / VO2 max / Resting HR grid (3-up).
- `recentEntriesSection` — last 5 weights as a VStack-based card. Tap opens `WeightEntryDetailSheet`. Long-press → context-menu delete. Audit DQ4 swap: VStack replaces the previous `List` because List reserves a trailing scrollbar gutter that made the card end short on the right.

State: `@Query weights`, `@Query dailyMetrics`. Computes `bmiText`, `bodyFatText`, `leanMassText` once per body (audit H18). Log button (top-right toolbar) is gated on `Profile.manualWeightLoggingEnabled` (hidden by default for users with a RENPHO scale).

#### `Views/Fitness/FitnessMainView.swift`
Fitness module main screen. Composition:
- `pageTitle` — colored "Fitness" heading (Sandy Coral).
- `backfillBanner` — visible while `hkService.isBackfilling`.
- `thisWeekSection` — hero `2h 53m` total active time + sub-line `4 sessions · 1865 kcal burned`. Empty-state collapses to `0m` + "No sessions yet this week."
- `recentSection` — chronological feed of all non-deleted `WorkoutSession`. VStack of `Button` rows (not NavigationLink — avoids the disclosure-indicator trailing gutter). Tap routes via state-driven `.navigationDestination(item: $selectedSession)`. Long-press → context-menu delete.

State: `@Query sessions`, `@Query strengthSessions`. Log button (top-right) is gated on `Profile.manualFitnessLoggingEnabled` (default off — Apple Watch users get automatic imports).

`handleActivityChoice(_:)` routes a `LogDestination` enum from the activity picker sheet to the appropriate destination (LogCyclingSheet, LogOtherWorkoutSheet variants, or fullScreenCover for `ActiveStrengthSessionView`).

`detailDestination(for:)` routes feed taps: strength sessions go to `StrengthSessionDetailView`, every other type to `WorkoutDetailView`.

#### `Views/Nutrition/NutritionMainView.swift`
Nutrition module main screen. Composition:
- `pageTitle` — colored "Nutrition" heading (Teal).
- `heroRow` — Calories + Protein side-by-side (each 56pt teal numeral + `/ target unit` sub-line). Calories cell includes an optional `+kcal from workouts` caption when the eat-back toggle is on AND workouts > 0.
- `macroGrid` — Carbs / Fat tiles.
- `actionRow` — "Scan barcode" + "Enter manually" buttons. Icons are explicit teal so they don't lose saturation through the tint cascade.
- `frequentChipsSection` — behavior-based chips, top 5 labels logged in the last 30 days. Hidden when fewer than 3 distinct items qualify. Chip tap pre-fills `LogMealManualSheet` with the most-recent macros for that label.
- `todaysLogSection` — today's `NutritionEntry` rows. VStack-based, tap opens `MealDetailView`, long-press deletes (hard delete via `context.delete`).

State: `@Query allEntries`, `@Query weights`, `@Query workouts`. `computedTargets` computed once per body via `let targets = ...` and threaded through subsections (audit H18 — saves 4× MetricsEngine walks per render). Sheet sequencing uses pending-intent + `DispatchQueue.main.asyncAfter(deadline: .now() + 0.4)` because iOS won't present a sheet while the prior is dismissing.

### Body sub-views

- **`LogWeightSheet.swift`** — manual weight entry with `FieldValidation` (weight 20–300 kg required + in range; body fat 0–60% optional; lean mass 20–200 kg optional). Save inserts locally and explicit-saves first (audit H4), then mirrors to HK async — on HK failure keeps the local entry and surfaces a non-blocking banner. The 2026-05-14 corruption incident motivated the bounded ranges.
- **`WeightHistoryView.swift`** — full chronological list of `WeightEntry`. Tap → `WeightEntryDetailSheet`. Swipe-to-delete via `.swipeActions`. Renders source badge (RENPHO / HEALTH / MANUAL) + optional BF% / LM kg per row.
- **`WeightEntryDetailSheet.swift`** — edit/delete a single weight entry. Same validation as LogWeightSheet. Draft state in `@State` so Cancel rolls back (SwiftData `@Bindable` would auto-commit). Delete is soft (`deletedFromIndex = true`) — HK is a peer; never delete from HK.

### Fitness sub-views

- **`LogActivitySheet.swift`** — picker fanout. 6 rows: Strength + "My exercises", Cycling, Running, Swimming, Squash, Other. `LogDestination` callback routes to the parent's correct destination.
- **`LogCyclingSheet.swift`** — manual cycling log. Required duration + intensity 1–5; optional distance. Audit H14: bounded ranges (1–1440 min, 0–300 km).
- **`LogOtherWorkoutSheet.swift`** — parameterized for running, swimming, squash, other. Sub-type picker (Hiking / Walking / Yoga / Other) only when `preset == .other`. Sub-type prefixes the notes field so the feed shows a distinction without a schema bump. Distance only shown for `.running` / `.swimming`.
- **`WorkoutDetailView.swift`** — detail screen for non-strength sessions. Hero shows duration + intensity + source badge. Stats grid auto-hides fields whose `has-Foo` is false (manual squash shows fewer cells than HK cycling). Swim-only HR chart (lazy-fetch via `hkService.fetchSwimDetail`) and Auto Sets sheet. Cycling shows a "Route view coming in a later release" placeholder. Delete soft-flags via `deletedFromIndex = true`.
- **`SwimAutoSetsSheet.swift`** — per-set summary + per-length breakdown for HK-imported swim workouts. Sets are the primary surface (more visual weight); lengths are denser secondary view. Read-only — spec excludes granularity toggle or splits. 25m pool only.

### Strength sub-views

- **`ActiveStrengthSessionView.swift`** — live logging surface. Top bar with elapsed timer + End button. Current exercise card with weight + reps fields, quick-adjust chips (`-2.5 / -1.25 / +1.25 / +2.5` kg, `-1 / +1` reps), "Complete set" primary action. Bottom "Add exercise" switches mid-session. Audit H17: `@Query` bounded to 365 days via `init`-time predicate so the cascade chain doesn't pull every `SetEntry` ever logged. Audit H18: `thisSessionSets` cached once per body (1Hz timer drives frequent re-evals). `endSession()` either inserts a parallel `WorkoutSession(.strength)` + flips `inProgress = false`, or hard-deletes the empty session (prevents empty-session leaks on re-appear).
- **`RestTimerOverlay.swift`** — translucent countdown overlay. 1Hz `Timer.publish`. Auto-dismiss at 0 with `UINotificationFeedbackGenerator.success`. Tap-to-dismiss early (no haptic).
- **`StrengthLibraryView.swift`** — user's exercise library list (filtered on `!hiddenFromLibrary`). Tap → `ExerciseDetailView`. Swipe sets `hiddenFromLibrary = true` (audit DQ4 soft-hide). "+" toolbar opens `AddExerciseSheet`.
- **`AddExerciseSheet.swift`** — picker over the 10-item starter catalog. Tap inserts a `UserExercise` keyed to the catalog id (or un-hides an existing hidden row — never duplicates). "Added" rows are disabled + opacified.
- **`ExercisePickerSheet.swift`** — picker over current library for the mid-session exercise switcher in `ActiveStrengthSessionView`.
- **`ExerciseDetailView.swift`** — per-exercise detail. Last session preview + progress chart (1M / 3M / 1Y, top-set weight per day). Audit H17: `@Query` bounded to 365 days. "Log new session" launches `ActiveStrengthSessionView` seeded with this exercise.
- **`StrengthSessionDetailView.swift`** — past strength session detail. Hero duration + Exercises/Sets summary + per-performance set rows + delete (soft-delete the parallel WorkoutSession + hard-delete the StrengthSession + its cascade).

### Nutrition sub-views

- **`BarcodeScannerView.swift`** — fullscreen camera scanner. Verbatim v0 port (AVCaptureSession setup sequence — the v2 reimplementation added rectOfInterest tuning + custom session preset that broke detection on real devices). `SwiftUI` wrapper around a `UIViewController` (`ScannerViewController` extends `AVCaptureMetadataOutputObjectsDelegate`). Detects EAN-8, EAN-13, UPC-A, UPC-E, ITF-14, Code 128. Audit H22: `onSetupFailed` callback surfaces camera-unavailable reasons (no camera, permission denied, busy).
- **`BarcodeResultSheet.swift`** — product lookup result. Cache-first (90-day freshness window in `FoodProduct`), OFF fallback otherwise. Quantity slider 10–800 step 5 with shortcut chips (`30 / 50 / 100 / 150 / 200` g or `100 / 200 / 250 / 330 / 500` ml). Macro display scales via `food.macros(forGrams:)`. Audit H15: explicit `do/catch` on the dedup fetch (previous `try?` swallowed errors and silently double-inserted FoodProduct rows). Save increments `useCount` only on save (not on cache upsert).
- **`LogMealManualSheet.swift`** — manual meal entry. Label required (non-empty trimmed). Kcal required and 0–5000. Macros optional 0–500 g each. Pre-fillable via `prefilledLabel` / `prefilledKcal` / `prefilledProtein` / `prefilledCarbs` / `prefilledFat` so the barcode-fallback flow (OFF not-found) and the frequent-foods chip flow can hand off label + macros to the same sheet. `editing != nil` switches to update mode (entry's own values win over pre-fills).
- **`MealDetailView.swift`** — read view for a single `NutritionEntry`. Edit button delegates back to the parent via `onRequestEdit` callback (parent dismisses this sheet, then presents `LogMealManualSheet` pre-filled). Delete is hard (`context.delete`).

### Onboarding

- **`OnboardingView.swift`** — 8 steps:
  1. Sign in — `IdentityService.signIn()`.
  2. Welcome / module explainer.
  3. Profile basics — name, age, height (100–250 cm validated), sex.
  4. Activity level (sedentary → extra active).
  5. Goal direction (lose / maintain / gain) + optional target weight (30–300 kg validated).
  6. Module toggles (Body / Fitness / Nutrition).
  7. Exercise picker (top-5 from the 10-item starter catalog, ≥1 required — audit DQ6). Only shown when Fitness is enabled; navigation skips it otherwise.
  8. Apple Health connect — `hkService.requestAuthorization()`. Skip button bypasses; user can re-grant from Settings.

`OnboardingDraft` accumulates state across steps. `complete()` calls back to `ContentView.completeOnboarding(draft:)` which writes the Profile + UserExercise rows transactionally.

Audit H13: numeric validation ranges on height + target weight so a typed `0` doesn't propagate as garbage into MetricsEngine.

Root `.tint(IndexPalette.Brand.primary)` so the Continue button + progress bar + selection rings render in French Blue (no module context yet).

### Settings

- **`SettingsView.swift`** — Phase 7 all-in-one panel. Sections (top to bottom): Profile, Goal (with the eat-back-workout-calories toggle), Modules, Manual logging, Strength exercises (link to library), Apple Health (status + sync toggles), Notifications, Data (export stub + reset), Account (sign-out + delete-account), About (version + build date).

  - Field edits route to single-field sheets (`activeSheet: SheetRoute?` enum), each surfacing failures via `onError` callback to a non-blocking banner.
  - Module toggles call `profileService.setModuleEnabled` per change; `.body` is `alwaysOn = true` so it can't be turned off.
  - HK sync toggles flip the UserDefaults flags AND arm/stop the matching HK observer in real time. `hkToggleTick` forces a re-render after a toggle so the UI reflects the new state.
  - Notification toggles are async-throws — flipping ON requests iOS permission first; on denial surfaces a one-time "enable in iOS Settings" alert.
  - Tint is `Module.settings` (French Blue, same as Body). X-dismiss button explicitly overrides to `Text.secondary` so it stays neutral.
  - Section caption helper centralizes the uppercase + kerning + `sectionCap` font for every section.

- **Edit sheets** (`NameEditSheet`, `AgeEditSheet`, `HeightEditSheet`, `SexEditSheet`, `DirectionEditSheet`, `CalorieAdjustmentEditSheet`, `ProteinTargetEditSheet`, `TargetWeightEditSheet`) — single-field sheets following the same pattern: `FieldValidation` numeric guards (height 100–250 cm, age 13–120, calorie adjustment −1000 to +1000 in 50-kcal steps, protein 50–300 g, target weight 30–300 kg), `ProfileService.update*` on save, `onError` callback for failure banner.
  - `CalorieAdjustmentEditSheet` has the signed slider (negative = deficit, positive = surplus) with hint text per direction.
  - `TargetWeightEditSheet` has the `hasTargetWeight` toggle gating the numeric field — matches the onboarding pattern.

- **`HealthStatusSheet.swift`** — read-only HK status (Connected / Not connected), Re-authorize affordance when not authorized, Health-app deep link via `x-apple-health://`.

---

## Patterns in active use

### Data integrity

- **CloudKit shape on every model.** Every property has a default; every to-one relationship is optional; no `@Attribute(.unique)`. Re-verified during the audit.
- **`has-Foo` boolean companion** for every nullable numeric (`hasKcal`, `hasMaxHeartRate`, `hasLeanMass`, ...). Never Swift-optional numerics; the Bool companion queries cleanly through SwiftData `#Predicate`.
- **UUID-first HK dedup.** Primary by `hk*UUID` field, fallback by ±N-min date window. Workouts ±2 min; weights ±5 min. Audit H5 / baseline.
- **`deletedFromIndex` soft-delete tombstones** on HK-mirrored models. Swipe sets it true. `@Query` filters on `!deletedFromIndex`. HK dedup predicates do NOT filter on the flag — that's what makes swipe-as-tombstone work against re-import. (Field is `// DEPRECATED:` on `NutritionEntry` per audit H3 + DQ2 — that model never mirrored to HK.)
- **Soft-link by string id** for cross-model references that deliberately bypass cascade delete: `WorkoutSession.strengthSessionId` → `StrengthSession.id`, `ExercisePerformance.userExerciseId` → `UserExercise.id`. Read sites gracefully render "Unknown exercise" / "Strength session deleted" when the link is dangling.
- **Soft-hide for catalog-keyed library items.** `UserExercise.hiddenFromLibrary` (audit DQ4). Library/picker `@Query` filters out hidden rows, but old session history's soft-link still resolves the name. Re-adding the same catalog id un-hides instead of inserting a duplicate.
- **Explicit boolean over date-equality heuristic** for in-progress / completed state. `StrengthSession.inProgress` (audit H16) replaces the previous `endDate <= date` check.

### Save discipline

- **Transactional save where it matters.** Onboarding completion + ProfileService migration accept/decline use explicit `try modelContext.save()` rather than relying on SwiftData autosave (audit H6 + H12). SwiftData autosave is "next runloop tick when dirty"; an app kill in that window loses the result.
- **`try?` is for reads, not writes.** `try?` on a `FetchDescriptor` returning an empty array is fine. `try?` on `context.save()` or HK `store.save(_:)` is not. Use a real `do/catch` with a user-visible failure mode.

### View architecture

- **`@Query` directly in views.** No ViewModels.
- **Sheet draft pattern.** `@State` text fields buffer the *display* of a model's values; explicit `model.field = parsed` on Save commits. Cancel rolls back implicitly because nothing was mutated.
- **`FieldValidation` value type** (in `LogWeightSheet.swift`) — three-state (`parsed` / `parsedInRange` / `error`) for any numeric form field. Reused by 7+ sheets after audit H13/H14. Comma-as-decimal locale handled.
- **Hoist body-derived metrics** to a single body-scoped `let derived = makeDerived()` and thread through subsections. Avoids 4× duplicated MetricsEngine/Brain work across computed-property accessor calls. Audit H18.
- **Bounded `@Query` via init-time predicate** for unbounded-growth tables. Construct `_query = Query(filter: #Predicate { $0.date > cutoff }, ...)` in the view's `init(...)` so the cutoff refreshes per presentation. Audit H17 — see `ActiveStrengthSessionView.init` and `ExerciseDetailView.init`.
- **VStack-of-Buttons over List for cards** when the trailing scrollbar gutter would clip the card visually. Long-press `contextMenu` replaces swipe-to-delete in these places.

### Service shape

- **Pure-static services for math.** `MetricsEngine` and `BrainService` have no state, no fetching — callers pass `@Query` data in.
- **Profile abstraction from day one.** No hard-coded "Yannis" anywhere. Every screen reads via `ProfileService.activeProfile`.
- **Identity behind a protocol.** `IdentityService` swap-seam in `AppDependencies.identity` is the only line that changes when paid enrollment lands.
- **Singleton for delegate-owning services.** `NotificationService.shared` because both `IndexApp`'s `@State` injection AND `HealthKitService`'s constructor dependency need the same `UNUserNotificationCenterDelegate` instance.
- **No side-channel mutation of services from views.** Services receive their dependencies at construction in `IndexApp`. `HealthKitService` was the one historical violation (audit H10 fixed).

### Defensive formatting

- **`SafeFormat`** for any `Int(Double)` display path (kg, kcal, BMR, HRV ms). Returns `"—"` for non-finite or magnitude > threshold. Floor against the 2026-05-14 corruption incident.
- **Centralized type system.** `IndexFont` tokens for every numerical site; `.font(.system(size:))` outside `IndexTypography.swift` is forbidden on data + section-cap sites.
- **Centralized color system.** `IndexPalette` for every color; no hex literals outside the palette file (data-viz colors in `RingsWidget` etc. that were never promoted are documented in-place when present).

### Error recovery

- **Discriminated catch on `SwiftDataError.loadIssueModelContainer`** (audit H9). Schema mismatch / store corruption triggers a single-shot wipe + retry (audit DQ5). Other errors preserve the user's data.
- **Non-trapping fallbacks.** `IndexApp.makeFallbackContainer` makes an in-memory ModelContainer if the persistent one is unrecoverable, so the app launches and ContentView can render the hard-error screen with a path forward. `AppleSignInIdentityService` stubs never `fatalError` (audit H7). One documented `fatalError` remains: `BarcodeScannerView.init?(coder:)` boilerplate (unreachable in SwiftUI presentation).

### Settings invariants

- **iOS retains per-type HK authorization** even after the app stops requesting it. Removing a read type means Index simply stops querying — the user's prior grant stays inert in iOS Settings → Health → Index. No programmatic revocation needed.
- **Notification permission gates are async.** Toggle-ON flow requests permission first; on denial the flag stays off and the caller surfaces a one-time alert.
- **HK observer toggle does NOT delete previously-imported rows** (audit DQ10). It only stops new delivery.

---

## Build + dev rules

See `CLAUDE.md` for the working agreement:

- Build commands (`DEVELOPER_DIR=... xcodebuild -target Index -sdk iphonesimulator26.5 ...`).
- Schema evolution rules (additive only; no deletes, renames, type changes; `// SCHEMA:` markers on every schema-change commit).
- Audit-derived defensive coding rules (no silent error swallowing; insert + save is one operation; no `fatalError` reachable in production except documented exceptions; HK observers must be stoppable).
- Code style (no emojis; default to no comments; `// DECISION:` for judgment calls; `// FUTURE:` for revisit-later markers).
- What's explicitly NOT in v1 (TSS / FTP, sleep tab, finance, workout templates, custom exercise creation, photo-to-macros, imperial units, dashboard prose).

---

## v0 lessons baked into v2

1. **Active-logging is a different design problem from reading.** v0's editorial design worked for calm browsing and was wrong for fast gym logging. v2's active screens get bigger inputs, more aggressive primary buttons, less whitespace.
2. **LOG is a primary action** when manual logging is enabled. It belongs visible on each module main (and gated on the user's preference for that module).
3. **Apple Health is read-mostly, write-rarely.** Index writes only `bodyMass`. HK is the source of truth.
4. **Migrations are cheap if you plan for them.** Lightweight-only is the only acceptable kind. The original V1/V2/V3 + `IndexMigrationPlan` design proved this isn't free.
5. **Type-tolerant parsing wins** when the third-party data shape is unstable. The v0 OFF parser uses `JSONSerialization` + `(value as? Double) ?? (value as? Int).map(Double.init) ?? 0`. The v2 rewrite using strict Codable structs returned zeros for half the products tested.
6. **Defensive formatting at every display boundary.** `SafeFormat` returns `"—"` for non-finite / out-of-range. The 2026-05-14 incident (a `WeightEntry.weightKg` of ~5×10³⁸ trapping `Int(kg)` in BodyView's formatter) is the proof point.
7. **Apple Health is a peer, not master, on the write path.** Audit H4 + DQ3: when Index writes `bodyMass` and HK rejects, the local `WeightEntry` stays and a non-blocking banner surfaces the failure. Rolling back the local insert would punish the user for HK's auth-state surprises.
8. **Identity-bearing values go in Keychain, not UserDefaults.** UserDefaults is for operational state (sync anchors, toggles, one-shot flags). DevIdentityService's `kSecAttrSynchronizable` flag preserves the userId across uninstall + reinstall when iCloud Keychain is on.
9. **Speculative widgets get cut, not iterated forever.** The Fitness Today widgets (rings → arrows → inset overflow → horizontal bars → delete) burned five iterations in one session before the user decided removing them was the right call. Ship the minimum; revisit when real usage surfaces the need.
