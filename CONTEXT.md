# Index v2 — Context

Everything a new contributor needs to understand what this app is, how it's organized, and what state it's in right now.

For build commands and the working agreement, see `CLAUDE.md`. For a phase-by-phase log of what shipped (and what's next), see `PROGRESS.md`.

---

## What it is

Index v2 is an iOS app for someone with serious gear — Apple Watch, smart scale (RENPHO), Apple Health — who wants their data **interpreted**, not just displayed. Three modules — **Body**, **Fitness**, **Nutrition** — sit on top of Apple's stack (HealthKit as the data source; CloudKit for private per-user sync once paid Developer Program enrollment lands; Sign in with Apple as the future identity provider). Each module shows raw data plus templated insight sentences from a pure-function **Brain** that reads cross-module signals. The audience is a casual-to-serious gym-goer, not a pro athlete.

This is the v2 rebuild. The v0 app lives at `/Users/yannis/Dashboard` and is reference-only — patterns and formulas carry over, code does not.

---

## Where the project is right now (2026-05-15)

**Phases 1–6 are complete.** The app builds clean, has working onboarding, and has all three modules wired end-to-end with logging, listing, detail, and (for Fitness) HK auto-import. The barcode scanner works against real products via Open Food Facts. See `PROGRESS.md` for the phase-by-phase log and the per-step commit chain.

**Phase 7 (Settings) has not started.** Most module-level toggles (workout import on/off, modules enabled, profile editing, calorie/protein adjustment, units imperial/metric, manual API key entry if photo flow is ever revived) currently use either UserDefaults defaults or hard-coded values because there is no UI yet to change them.

**A deep audit just ran.** See the "Audit findings" section near the bottom of this document and the consolidated punch list in `PROGRESS.md`. No critical issues found. ~24 high-priority items, mostly around silent-failure paths in HK + onboarding, dead code (PhotoEstimateLog, ClaudeService), and a handful of additive schema bumps.

**Identity is currently dev-stub.** `DevIdentityService` stores a UUID in UserDefaults; `AppleSignInIdentityService` exists as a stub with `fatalError` bodies that will be filled in post-enrollment. CloudKit is similarly pending — models are CloudKit-shaped but `ModelConfiguration` does not yet pass `cloudKitDatabase:`.

---

## Architecture

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

## Stack

- **Swift** — `SWIFT_VERSION = 5.0` in build settings, with Swift 6-style upcoming features opted in (`InferSendableFromCaptures`, `GlobalActorIsolatedTypesUsability`, `MemberImportVisibility`, `InferIsolatedConformances`, `NonisolatedNonsendingByDefault`, `DisableOutwardActorInference`). Every type isolated to `@MainActor` by default. The "5.0 with Swift 6 features" mode is intentional during transition; bump to `6.0` is a deferred decision (see `PROGRESS.md`).
- **SwiftUI + SwiftData** — every view uses `@Query` directly; no ViewModels. Sheet drafts use `@State` text + manual `model.field = …` on save so Cancel reliably rolls back.
- **iOS 26.4+** deployment target. Build SDK is `iphonesimulator26.5` (Xcode 26.4.1 ships with that SDK; the runtime is 26.4).
- **HealthKit** — read 14 sample types, write `bodyMass` only. Background delivery entitlement enabled.
- **Open Food Facts API** — barcode lookup, no auth. Verbatim port of v0's tolerant JSONSerialization parser (see `OpenFoodFactsService.swift`); the v2 strict-Codable rewrite that returned zeros was discarded.
- **AVFoundation** — barcode scanning (EAN-8, EAN-13, UPC-A, UPC-E, ITF-14, Code 128).
- **Anthropic Claude Haiku** (`claude-haiku-4-5-20251001`) — wired in `ClaudeService` for photo-to-macros, but the **photo flow is cut from v1**. The file is currently dead code and a candidate for deletion (see audit).
- **Sign in with Apple** — pending paid Developer Program enrollment. Stub class exists.
- **CloudKit private database** — pending paid Developer Program enrollment. Models are CloudKit-shaped today; flipping the capability is a one-line `ModelConfiguration` change.

---

## Modules

### Body
Weight, body composition (body fat %, lean mass), daily vitals (HRV SDNN, VO2 max, resting HR), BMI/BMR/TDEE/ideal range. Logs manual weight; mirrors to Apple Health (write-only `bodyMass`). Reads RENPHO scale data via Apple Health and groups bodyMass + bodyFatPercentage + leanBodyMass samples *from the same HK source bundle id* into a single `WeightEntry`.

### Fitness
Apple Watch workout auto-import via `HKAnchoredObjectQuery` + manual logs (cycling, running, swimming, squash, other) + freestyle strength training (no templates). Strength sessions decompose into `ExercisePerformance` rows (one per exercise per session) of `SetEntry` rows (weight in kg, reps, completedAt). The 10-exercise starter catalog (5 free-weight, 3 machine, 2 bodyweight) is the whole catalog — user picks up to 5 during onboarding, can add later from "My exercises". A historical backfill runs once per device install and pulls every workout from January 1 of the current year.

### Nutrition
Barcode scanning via AVFoundation → Open Food Facts → 90-day local cache (`FoodProduct`). Manual meal entry. Per-entry kcal + macros, meal type (breakfast/lunch/dinner/snack), source (manual/barcode). Deletion is hard-delete via swipe (NutritionEntry has a vestigial `deletedFromIndex` field that no path actually reads — slated for `// DEPRECATED:` mark, see audit).

Photo-to-macros is **cut from v1** — `ClaudeService` and `PhotoEstimateLog` exist as dead code and are slated for deletion before Phase 7.

### Brain (cross-module)
Pure-static functions in `MetricsEngine` (formulas — BMR, TDEE, LBM, IBW, daily target reconciliation across workouts and 14-day weight trend) and `BrainService` (one templated insight sentence per module — body / fitness / nutrition). Take profile + per-module data, return daily targets and insight strings. No state, no fetching — callers pass `@Query` data in.

---

## Data model — 11 SwiftData classes

All in `Index/Index/Index/Models/`. Every property has a default; every relationship is optional; no `@Attribute(.unique)` anywhere. CloudKit-shape compliance across all 11 (re-verified during the audit).

| Model | Purpose |
|---|---|
| `Profile` | One per active userId. Holds personalization (age, height, sex, activity, goal, target weight, units, enabled modules, calorie adjustment, protein target, HK-auth flag, onboarding-completed flag, createdAt). Enabled modules stored as a JSON-encoded `[String]` blob in `enabledModulesJSON`. |
| `WeightEntry` | One weight log. Carries body fat % and lean mass when source provides them. `source ∈ {manual, healthkit, renpho}`. `deletedFromIndex` tombstones for HK re-import dedup. |
| `DailyHealthMetrics` | One row per calendar day. HRV / VO2 max / resting HR upserted from HK. Has-Foo companions on each. |
| `WorkoutSession` | One workout (Watch auto-import or manual). 6 `WorkoutType` cases: cycling, running, swimming, strength, squash, other. `hkWorkoutUUID` is the primary dedup key for HK auto-imports; ±2-min date window is the secondary. `strengthSessionId` soft-links to a parallel `StrengthSession` when `type == .strength`. |
| `StrengthSession` | One gym session. Stable string `id` (UUID). Cascade-deletes `[ExercisePerformance]?`. |
| `ExercisePerformance` | One (session, userExercise) pair. `userExerciseId` is a soft link to `UserExercise.id` so deleting a UserExercise from the library doesn't cascade through old session history. Cascade-deletes `[SetEntry]?`. |
| `SetEntry` | One completed set. `weightKg` can be negative (assisted exercises subtract from bodyweight). `completedAt` is the per-set timestamp. |
| `UserExercise` | The user's personal exercise library (max 5 in v1). Derived from `ExerciseCatalog.starter` definitions; ids are catalog ids verbatim ("bench-press", "squat", …). |
| `NutritionEntry` | One meal/food log. `mealType ∈ {breakfast, lunch, dinner, snack}`, `source ∈ {manual, barcode, photo}`. `photoEstimated` and `source = .photo` are dead in v1 (slated for `// DEPRECATED:` mark). |
| `FoodProduct` | Barcode-keyed product cache. Per-100g (or per-100ml) macros. `useCount + lastUsed` for future frequently-eaten surfaces. `unit` ("g" / "ml") records solid vs liquid. |
| `PhotoEstimateLog` | Audit log for photo-to-macros estimates. **Dead code in v1** — never written by any path. Slated for deletion before Phase 7. |

Schema is `IndexSchema` (no `V1` suffix; the original V1/V2/V3 + `IndexMigrationPlan` design generated "Duplicate version checksums detected" because of how SwiftData's per-version checksum works, and was replaced with a single `IndexSchema.models` list relying on lightweight migration). See `CLAUDE.md` "Schema evolution rules" for the non-negotiable constraints.

---

## HealthKit

**Read types** (14): `bodyMass`, `bodyFatPercentage`, `leanBodyMass`, `heartRateVariabilitySDNN`, `vo2Max`, `restingHeartRate`, `workoutType()`, `heartRate`, `activeEnergyBurned`, `basalEnergyBurned`, `distanceCycling`, `distanceWalkingRunning`, `distanceSwimming`, `cyclingPower`.

**Write types** (1): `bodyMass` only — manual weight mirrors back to Apple Health. Other apps see Index's writes.

**Anchor management**: HK observer's anchor is gated on the import toggle. If toggle is off, do NOT advance the anchor. This prevents data loss when the user temporarily disables import. (The toggle has no UI yet — defaults to ON via UserDefaults.)

**Body composition source-matching**: a RENPHO weigh-in's body-fat / lean-mass samples must come from the same HK source bundle id as the bodyMass sample. Otherwise a manual Index weight write could accidentally absorb a stale RENPHO body-fat reading and tag it onto a non-RENPHO source.

**Apple Watch workout-type mapping**:

| HKWorkoutActivityType | Index `WorkoutType` |
|---|---|
| `.cycling` | `.cycling` |
| `.running`, `.walking` | `.running` |
| `.swimming`, `.swimBikeRun` | `.swimming` |
| `.squash` | `.squash` |
| `.traditionalStrengthTraining`, `.functionalStrengthTraining`, `.crossTraining`, `.highIntensityIntervalTraining`, `.coreTraining` | `.strength` |
| anything else | `.other` |

Hiking, yoga, pilates, tennis, badminton, racquetball, table tennis, rowing, elliptical, stair-stepping all map to `.other` deliberately — none drive the protein-add bonus the way strength training does, and the MET differences are within the noise of activity-level personalization.

---

## Patterns in active use

- **Pure-static services for math** (`MetricsEngine`, `BrainService`). No state, no fetching — callers pass `@Query` data in. Documented v0 audit-fix M1: "don't recompute targets per re-render."
- **`has-Foo` boolean companion** for every nullable numeric (`hasKcal`, `hasMaxHeartRate`, `hasLeanMass`, …). Never Swift-optional numerics; the Bool companion queries cleanly through SwiftData `#Predicate`.
- **`deletedFromIndex` soft-delete** on every model that mirrors HealthKit data. Filter `@Query` results with `#Predicate { !$0.deletedFromIndex }`. HK dedup predicates **do NOT** filter on this flag — that's what makes swipe-delete-as-tombstone work.
- **Soft-link by string id** for cross-model references that deliberately bypass cascade delete: `WorkoutSession.strengthSessionId` → `StrengthSession.id`, `ExercisePerformance.userExerciseId` → `UserExercise.id`. Read-side gracefully renders "Unknown exercise" / "Strength session deleted" when the link is dangling.
- **`@Query` directly in views.** No ViewModels.
- **Sheet draft pattern**: `@State` text fields buffer the *display* of a model's values; explicit `model.field = parsed` on Save commits. Cancel rolls back implicitly because nothing was mutated.
- **`FieldValidation` value type** (`Views/Body/LogWeightSheet.swift`): three-state (parsed / parsedInRange / error) for any numeric form field. Reused by 5+ sheets. Comma-as-decimal locale handled.
- **`SafeFormat` defensive formatters** for any `Int(Double)` display path (kg, kcal, BMR, HRV ms). Returns `"—"` for non-finite or magnitude > threshold. Floor against the 2026-05-14 corruption incident (a `WeightEntry.weightKg` ~5×10³⁸ trapped the Body screen).
- **Profile abstraction from day one.** No hard-coded "Yannis" anywhere. Every screen reads via `ProfileService.activeProfile`.
- **Identity behind a protocol.** `IdentityService` swap-seam in `AppDependencies.identity` is the only line that changes when paid enrollment lands.

---

## Things explicitly NOT in v1

Cut after the v0 retrospective. Do not implement.

- TSS / FTP / normalized power (pro-cyclist metrics)
- Sleep as a top-level tab (Sleep is a tile on Body if at all)
- Finance models entirely
- Structured cycling workout templates (HIIT Sprints, Tempo, Recovery)
- Strength workout templates (no Push Day / Pull Day; freestyle only)
- Custom exercise creation (the 10-exercise starter catalog is the whole catalog)
- Frequently-eaten chips on Nutrition main
- Metric explanation overlays (long-press to explain BMI etc.)
- Notification system (zero notifications in v1)
- Dashboard tab / "Today's Read" prose
- `WorkoutDetailData` lazy-fetch (v2 persists HR series + zone breakdown to SwiftData when it lands; deferred past v1)
- **Photo-to-macros** (originally planned for Nutrition; cut on retrospective)
- Imperial display units (`MetricsEngine.kgToLbs`/`lbsToKg`/`cmToFtIn` exist but no view branches on `Profile.units` yet)
- Custom launch screen (auto-generated for now)

---

## Audit findings (2026-05-15)

A line-by-line audit of every Swift file just completed. Headline:

- **Critical issues: 0.** The app's foundation is fundamentally sound.
- **High-priority items: ~24.** Mostly silent-failure paths (HK write swallows errors, ProfileService migration not transactional, BarcodeResultSheet dedup uses `try?`), dead code (PhotoEstimateLog, ClaudeService), bounded-fetch needs (Strength queries unbounded), missing onboarding numeric guards, and four additive schema bumps (`WeightEntry.hkSampleUUID`, `StrengthSession.inProgress`, `Profile.hasProteinTarget`, `DailyHealthMetrics.date` default sentinel).
- **Medium / Low: ~30 / ~13.** Polish, naming consistency, hoisted formatters.

The audit also surfaced **10 deferred questions** where current behavior could be intentional — the answers shape several fixes. See `PROGRESS.md` for the consolidated punch list and the open questions.

### Concrete known limitations (carried into Phase 7)

- HK write failures (`HealthKitService.saveWeight`) are silently swallowed — user has no signal if Apple Health rejects the write.
- HK observers are never torn down — Settings toggle-off (Phase 7) will need an observer-stop API.
- `IndexApp` migration recovery wipes the store on *any* ModelContainer init error, not just SwiftDataError migration cases. Disk-full / file-permission errors would also wipe.
- Second-fail recovery in `IndexApp` calls `fatalError` — reachable in production.
- `DevIdentityService` stores in UserDefaults, which clears on uninstall. Reinstall regenerates userId and triggers the orphan-migration prompt. Pre-SIWA fix is to move to Keychain.
- Several main views recompute Brain insights and MetricsEngine targets per `body` render (BodyView, FitnessMainView, NutritionMainView, ActiveStrengthSessionView). Not user-visible today; will matter once data volumes grow.
- Onboarding accepts 0 cm height, 0 kg target weight, and 0 selected exercises silently — propagates as garbage into MetricsEngine.
- Manual workout sheets (LogCyclingSheet, LogOtherWorkoutSheet) accept unbounded duration / distance.
- `LSApplicationCategoryType` not set in Info.plist — required for App Store submission.
- `SWIFT_TREAT_WARNINGS_AS_ERRORS` not enabled for Release.

### Dead code marked for removal / deprecation

- `Services/ClaudeService.swift` — entire file. Photo flow cut.
- `Models/PhotoEstimateLog.swift` — entire file + remove from `IndexSchema.models`. Phantom on-disk table.
- `Models/NutritionEntry.photoEstimated`, `NutritionSource.photo` — deprecate (cannot delete per schema rules).
- `Models/NutritionEntry.deletedFromIndex` — deprecate; the swipe path uses hard-delete.
- `Models/UserExercise.notes` — deprecate; never read or written.

---

## v0 lessons baked into v2

1. **Active-logging is a different design problem from reading.** v0's editorial design worked for calm browsing and was wrong for fast gym logging. v2's active screens get bigger inputs, more aggressive primary buttons, less whitespace.
2. **LOG is a primary action.** It belongs visible on every module main, not hidden behind a "+".
3. **Apple Health is read-mostly, write-rarely.** Index writes only `bodyMass`. HK is the source of truth.
4. **Migrations are cheap if you plan for them.** Lightweight-only is the only acceptable kind. The original V1/V2/V3 + `IndexMigrationPlan` design proved this isn't free — see `CLAUDE.md` "Schema evolution rules" for the rules and the recovery contract.
5. **Type-tolerant parsing wins** when the third-party data shape is unstable. The v0 OFF parser uses `JSONSerialization` + `(value as? Double) ?? (value as? Int).map(Double.init) ?? 0`. The v2 rewrite using strict Codable structs returned zeros for half the products tested. Verbatim port restored parity.
6. **Defensive formatting at every display boundary.** `SafeFormat` returns `"—"` for non-finite / out-of-range. The 2026-05-14 incident (a `WeightEntry.weightKg` of ~5×10³⁸ trapping `Int(kg)` in BodyView's formatter) is the proof point.
