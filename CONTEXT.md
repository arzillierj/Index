# Index v2 — Context

Everything a new contributor needs to understand what this app is, how it's organized, and what state it's in right now.

For build commands and the working agreement, see `CLAUDE.md`. For a phase-by-phase log of what shipped (and what's next), see `PROGRESS.md`.

---

## What it is

Index v2 is an iOS app for someone with serious gear — Apple Watch, smart scale (RENPHO), Apple Health — who wants their data **interpreted**, not just displayed. Three modules — **Body**, **Fitness**, **Nutrition** — sit on top of Apple's stack (HealthKit as the data source; CloudKit for private per-user sync once paid Developer Program enrollment lands; Sign in with Apple as the future identity provider). Each module shows raw data plus templated insight sentences from a pure-function **Brain** that reads cross-module signals. The audience is a casual-to-serious gym-goer, not a pro athlete.

This is the v2 rebuild. The v0 app lives at `/Users/yannis/Dashboard` and is reference-only — patterns and formulas carry over, code does not.

---

## Where the project is right now (2026-05-15)

**Phases 1–6 are complete.** The app builds clean, has working onboarding, and has all three modules wired end-to-end with logging, listing, detail, and (for Fitness) HK auto-import. The barcode scanner works against real products via Open Food Facts. The Swimming workout detail view ships HR chart + Avg SWOLF + Pool Length + Auto Sets sheet (per-set summary + per-length breakdown). See `PROGRESS.md` for the phase-by-phase log and the per-step commit chain.

**Audit Phase 5 complete.** A line-by-line audit ran 2026-05-15, then 24 H-tier fixes + 1 DQ-derived schema bump shipped across 5 rounds (commits `daca14c` → `cbff27c` on `origin/main`). Headline outcomes:

- Dead code removed (`ClaudeService`, `PhotoEstimateLog`); four dead fields marked `// DEPRECATED:`.
- Three additive schema bumps shipped with `// SCHEMA:` markers and device-test verification (`WeightEntry.hkSampleUUID`, `StrengthSession.inProgress`, `UserExercise.hiddenFromLibrary`).
- Identity moved from UserDefaults to Keychain (with iCloud Keychain sync).
- `IndexApp` recovery rebuilt: discriminated catch on `SwiftDataError`, non-trapping in-memory fallback, ContentView hard-error screen with "Reset all data" button.
- HealthKitService now takes `ModelContainer` at construction (no more side-channel set from a view); `saveWeight` is `async throws` with non-blocking failure banner; HK weight dedup is UUID-first with date-window fallback.
- Onboarding numeric guards + min-1 exercise gate; manual-workout input range validation; `BarcodeScannerView` setup-failure surface.
- Performance: bounded Strength `@Query` (last 365 days, init-time predicate) and hoisted derived-metrics in main views.

**Phase 7 (Settings) has not started.** Most module-level toggles (workout import on/off, modules enabled, profile editing, calorie/protein adjustment, units imperial/metric) currently use either UserDefaults defaults or hard-coded values because there is no UI yet to change them.

**Identity is currently dev-stub.** `DevIdentityService` stores a UUID in **Keychain** (audit H21) with `kSecAttrAccessibleAfterFirstUnlock` + `kSecAttrSynchronizable` so identity persists across uninstall + reinstall when the user has iCloud Keychain on. `AppleSignInIdentityService` exists as **non-trapping stubs** (audit H7); fill the bodies post-enrollment and flip `AppDependencies.identity` as the swap. CloudKit is similarly pending — models are CloudKit-shaped but `ModelConfiguration` does not yet pass `cloudKitDatabase:`.

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
- **Sign in with Apple** — pending paid Developer Program enrollment. Non-trapping stub class exists (audit H7); current identity is Keychain-backed `DevIdentityService` (audit H21).
- **CloudKit private database** — pending paid Developer Program enrollment. Models are CloudKit-shaped today; flipping the capability is a one-line `ModelConfiguration` change.

(`Services/ClaudeService.swift` was deleted in audit H2 — photo-to-macros is out of v1, see "Things explicitly NOT in v1" below.)

---

## Modules

### Body
Weight, body composition (body fat %, lean mass), daily vitals (HRV SDNN, VO2 max, resting HR), BMI/BMR/TDEE/ideal range. Logs manual weight; mirrors to Apple Health (write-only `bodyMass`). Reads RENPHO scale data via Apple Health and groups bodyMass + bodyFatPercentage + leanBodyMass samples *from the same HK source bundle id* into a single `WeightEntry`.

### Fitness
Apple Watch workout auto-import via `HKAnchoredObjectQuery` + manual logs (cycling, running, swimming, squash, other) + freestyle strength training (no templates). Strength sessions decompose into `ExercisePerformance` rows (one per exercise per session) of `SetEntry` rows (weight in kg, reps, completedAt). The 10-exercise starter catalog (5 free-weight, 3 machine, 2 bodyweight) is the whole catalog — user picks up to 5 during onboarding, can add later from "My exercises". A historical backfill runs once per device install and pulls every workout from January 1 of the current year.

### Nutrition
Barcode scanning via AVFoundation → Open Food Facts → 90-day local cache (`FoodProduct`). Manual meal entry. Per-entry kcal + macros, meal type (breakfast/lunch/dinner/snack), source (manual/barcode). Deletion is hard-delete via swipe (`NutritionEntry.deletedFromIndex` is `// DEPRECATED:` — never queried per audit H3 + DQ2). The Nutrition main hero floats Calories + Protein side-by-side without card chrome; a behavior-based "Frequent" chip row beneath the action buttons surfaces the top 5 most-logged labels from the last 30 days for one-tap pre-fill.

Photo-to-macros is **cut from v1** — `ClaudeService` and `PhotoEstimateLog` were deleted in audit H1 + H2 (commits `daca14c` + `a878ab1`).

### Brain (cross-module)
Pure-static functions in `MetricsEngine` (formulas — BMR, TDEE, LBM, IBW, daily target reconciliation across workouts and 14-day weight trend) and `BrainService` (one templated insight sentence per module — body / fitness / nutrition). Take profile + per-module data, return daily targets and insight strings. No state, no fetching — callers pass `@Query` data in.

---

## Data model — 10 SwiftData classes

All in `Index/Index/Index/Models/`. Every property has a default; every relationship is optional; no `@Attribute(.unique)` anywhere. CloudKit-shape compliance across all 10 (re-verified during the audit).

| Model | Purpose |
|---|---|
| `Profile` | One per active userId. Holds personalization (age, height, sex, activity, goal, target weight, units, enabled modules, calorie adjustment, protein target, HK-auth flag, onboarding-completed flag, createdAt). Enabled modules stored as a JSON-encoded `[String]` blob in `enabledModulesJSON` (encode/decode failure paths are symmetric — audit H19). |
| `WeightEntry` | One weight log. Carries body fat % and lean mass when source provides them. `source ∈ {manual, healthkit, renpho}`. `deletedFromIndex` tombstones for HK re-import dedup. **`hkSampleUUID: String?`** (audit H5) is the primary dedup key for HK auto-imports; ±5-min date window is the secondary fallback for manual rows. |
| `DailyHealthMetrics` | One row per calendar day. HRV / VO2 max / resting HR upserted from HK. Has-Foo companions on each. `date` default is `Date.distantPast` (audit H20) — sentinel so any latent migration is obvious instead of collapsing every back-filled row to a single timestamp on the upsert key. |
| `WorkoutSession` | One workout (Watch auto-import or manual). 6 `WorkoutType` cases: cycling, running, swimming, strength, squash, other. `hkWorkoutUUID` is the primary dedup key for HK auto-imports; ±2-min date window is the secondary. `strengthSessionId` soft-links to a parallel `StrengthSession` when `type == .strength`. |
| `StrengthSession` | One gym session. Stable string `id` (UUID). Cascade-deletes `[ExercisePerformance]?`. **`inProgress: Bool = true`** (audit H16) replaces the previous `endDate <= date` heuristic; `ActiveStrengthSessionView.endSession` flips it false on real session-end. |
| `ExercisePerformance` | One (session, userExercise) pair. `userExerciseId` is a soft link to `UserExercise.id` so removing a UserExercise from the library doesn't cascade through old session history. Cascade-deletes `[SetEntry]?`. |
| `SetEntry` | One completed set. `weightKg` can be negative (assisted exercises subtract from bodyweight). `completedAt` is the per-set timestamp. |
| `UserExercise` | The user's personal exercise library (max 5 in v1, soft-hide pattern). Derived from `ExerciseCatalog.starter` definitions; ids are catalog ids verbatim ("bench-press", "squat", …). **`hiddenFromLibrary: Bool = false`** (audit DQ4) — library swipe sets it true; library + picker `@Query` filter on `!hiddenFromLibrary`; AddExerciseSheet un-hides on re-add instead of inserting a duplicate. `notes: String` is `// DEPRECATED:`. |
| `NutritionEntry` | One meal/food log. `mealType ∈ {breakfast, lunch, dinner, snack}`, `source ∈ {manual, barcode}`. `photoEstimated`, `NutritionSource.photo`, and `deletedFromIndex` are all `// DEPRECATED:` (audit H3 + DQ2) — no path queries them; swipe is hard-delete. |
| `FoodProduct` | Barcode-keyed product cache. Per-100g (or per-100ml) macros. `useCount + lastUsed` drive the behavior-based "Frequent" chip row on Nutrition main. `unit` ("g" / "ml") records solid vs liquid. |

`PhotoEstimateLog` was deleted in audit H1 (commit `a878ab1`) — phantom on-disk table, never written by any path; safe non-additive removal because no user data ever existed for it.

Schema is `IndexSchema` (no `V1` suffix; the original V1/V2/V3 + `IndexMigrationPlan` design generated "Duplicate version checksums detected" because of how SwiftData's per-version checksum works, and was replaced with a single `IndexSchema.models` list relying on lightweight migration). See `CLAUDE.md` "Schema evolution rules" for the non-negotiable constraints.

---

## HealthKit

**Read types** (14): `bodyMass`, `bodyFatPercentage`, `leanBodyMass`, `heartRateVariabilitySDNN`, `vo2Max`, `restingHeartRate`, `workoutType()`, `heartRate`, `activeEnergyBurned`, `basalEnergyBurned`, `distanceCycling`, `distanceWalkingRunning`, `distanceSwimming`, `cyclingPower`.

**Write types** (1): `bodyMass` only — manual weight mirrors back to Apple Health. Other apps see Index's writes. The write is `async throws` (audit H4); local entry stays even if HK rejects, surfaced as a non-blocking banner in `LogWeightSheet`.

**Service wiring**: `HealthKitService` is `@MainActor @Observable` and takes a `ModelContainer` at construction (audit H10 — instance shared with `IndexApp.modelContainer` via `IndexApp.sharedContainer`). Internally derives `mainContext` for SwiftData writes. No more side-channel mutation from a view's `.task`.

**Anchor management**: HK observer's anchor is gated on the import toggle. If toggle is off, do NOT advance the anchor. This prevents data loss when the user temporarily disables import. (The toggle has no UI yet — defaults to ON via UserDefaults; Phase 7 ships the toggle UI together with the observer-stop API.)

**Dedup for HK auto-imports** is two-tier (audit baseline for workouts; audit H5 for weights):
- Primary — match the HK sample's UUID against `WorkoutSession.hkWorkoutUUID` / `WeightEntry.hkSampleUUID`.
- Secondary — ±N-min date window (±2 min for workouts, ±5 min for weights). Catches manual entries (no HK UUID) and pre-UUID-field legacy rows.
Neither tier filters on `deletedFromIndex` — that's still the swipe-as-tombstone contract that prevents re-import resurrection.

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

- **Pure-static services for math** (`MetricsEngine`, `BrainService`). No state, no fetching — callers pass `@Query` data in. Documented v0 audit-fix M1: "don't recompute targets per re-render"; honored at the call sites by hoisting `let targets = computedTargets` once per `body` and threading through subsections (audit H18).
- **`has-Foo` boolean companion** for every nullable numeric (`hasKcal`, `hasMaxHeartRate`, `hasLeanMass`, …). Never Swift-optional numerics; the Bool companion queries cleanly through SwiftData `#Predicate`.
- **`deletedFromIndex` soft-delete** on every model that mirrors HealthKit data. Filter `@Query` results with `#Predicate { !$0.deletedFromIndex }`. HK dedup predicates **do NOT** filter on this flag — that's what makes swipe-delete-as-tombstone work. (Field is `// DEPRECATED:` on `NutritionEntry` per audit H3 + DQ2 — that model never mirrored to HK.)
- **Soft-link by string id** for cross-model references that deliberately bypass cascade delete: `WorkoutSession.strengthSessionId` → `StrengthSession.id`, `ExercisePerformance.userExerciseId` → `UserExercise.id`. Read-side gracefully renders "Unknown exercise" / "Strength session deleted" when the link is dangling.
- **Soft-hide for catalog-keyed library items.** `UserExercise.hiddenFromLibrary` (audit DQ4) — library/picker `@Query` filters out hidden rows, but old session history's soft-link still resolves the name. Re-adding the same catalog id un-hides instead of inserting a duplicate. Pattern applies to any future model where ids are deterministic and reused across history.
- **UUID-first HK dedup** (audit H5 / baseline) — primary by `hk*UUID` field, fallback by ±N-min date window for manual rows.
- **Explicit boolean over date-equality heuristic** for in-progress / completed state — `StrengthSession.inProgress` (audit H16) replaces the previous `endDate <= date` check.
- **Transactional save discipline** — onboarding completion + ProfileService migration accept/decline use explicit `try modelContext.save()` rather than relying on SwiftData autosave (audit H6 + H12). SwiftData autosave is "next runloop tick when dirty"; an app kill in that window loses the result for identity-bearing operations.
- **`@Query` directly in views.** No ViewModels.
- **Sheet draft pattern**: `@State` text fields buffer the *display* of a model's values; explicit `model.field = parsed` on Save commits. Cancel rolls back implicitly because nothing was mutated.
- **`FieldValidation` value type** (`Views/Body/LogWeightSheet.swift`): three-state (parsed / parsedInRange / error) for any numeric form field. Reused by 7+ sheets after audit H13/H14. Comma-as-decimal locale handled.
- **`SafeFormat` defensive formatters** for any `Int(Double)` display path (kg, kcal, BMR, HRV ms). Returns `"—"` for non-finite or magnitude > threshold. Floor against the 2026-05-14 corruption incident (a `WeightEntry.weightKg` ~5×10³⁸ trapped the Body screen).
- **Bounded `@Query` via init-time predicate** for unbounded-growth tables (Strength session history). Construct `_query = Query(filter: #Predicate { $0.date > cutoff }, ...)` in the view's `init(...)` so the cutoff refreshes per presentation. Audit H17 — see `ActiveStrengthSessionView.init` and `ExerciseDetailView.init` for the canonical implementation.
- **Hoist body-derived metrics** to a single body-scoped `let derived = makeDerived()` and thread through subsections that need it; avoid 4× duplicated MetricsEngine/Brain work across computed-property accessor calls. Audit H18.
- **Profile abstraction from day one.** No hard-coded "Yannis" anywhere. Every screen reads via `ProfileService.activeProfile`.
- **Identity behind a protocol.** `IdentityService` swap-seam in `AppDependencies.identity` is the only line that changes when paid enrollment lands. `DevIdentityService` stores in Keychain (audit H21); `AppleSignInIdentityService` stubs are non-trapping (audit H7).

---

## Things explicitly NOT in v1

Cut after the v0 retrospective. Do not implement.

- TSS / FTP / normalized power (pro-cyclist metrics)
- Sleep as a top-level tab (Sleep is a tile on Body if at all)
- Finance models entirely
- Structured cycling workout templates (HIIT Sprints, Tempo, Recovery)
- Strength workout templates (no Push Day / Pull Day; freestyle only)
- Custom exercise creation (the 10-exercise starter catalog is the whole catalog)
- Metric explanation overlays (long-press to explain BMI etc.)
- Notification system (zero notifications in v1)
- Dashboard tab / "Today's Read" prose
- `WorkoutDetailData` lazy-fetch (v2 persists HR series + zone breakdown to SwiftData when it lands; deferred past v1)
- **Photo-to-macros.** `Services/ClaudeService.swift` and `Models/PhotoEstimateLog.swift` were deleted in audit H1 + H2. `NutritionEntry.photoEstimated` and `NutritionSource.photo` remain on the model marked `// DEPRECATED:` per the schema rules ("Never delete a field"). Reviving the feature post-v1 means re-adding the service + model as additive changes, not un-deprecating the existing slots.
- Imperial display units (`MetricsEngine.kgToLbs`/`lbsToKg`/`cmToFtIn` exist but no view branches on `Profile.units` yet)
- Custom launch screen (auto-generated for now)

(Frequent-foods chips on Nutrition main is now shipped as a behavior-based row built from last-30-day NutritionEntry frequency — see commit `3d88285`. The original "no frequently-eaten chips" cut was about a curated/favorites system; behavior-based is a different design.)

---

## Audit Phase 5 outcome (2026-05-15)

A line-by-line audit ran on 2026-05-15, then **24 H-tier fixes + 1 DQ-derived schema bump shipped across 5 rounds** (commits `daca14c` → `cbff27c` on `origin/main`). No critical issues were found; all High-priority items landed. Build clean (Debug + Release, zero warnings) at every round close. Two device-test gates honored (Round 3 H5 + H21; Round 4 H16 + DQ4).

Per-round summary:

| Round | Theme | Fixes | Commits |
|---|---|---|---|
| 1 | Deletions + config | H1 H2 H3 H19 H20 H23 H24 (+1 follow-up) | 8 |
| 2 | Foundation hardening | H8 H9 H10 H11 H12 (H11 bundled) | 3 |
| 3 | Data integrity | H4 H5 H6 H15 H21 (+ hero polish) | 6 |
| 4 | UX + validation | H7 H13 H14 H16 H22 + DQ4 (DQ8 reviewed) | 6 |
| 5 | Performance | H17 H18 | 2 |

See `PROGRESS.md` for the per-fix commit table and the deferred-question answers in full.

### What's still open (carry-forward into Phase 7 / Phase 8)

- **HK observer-stop API.** Phase 7 ships the Settings toggle UI together with the stop call. Per DQ10, stopping HK delivery does NOT delete previously-imported HK rows.
- **Phase 7 Settings UI in general** — workout import toggle, profile editor, calorie/protein adjustment editor, units toggle, "Reset all data" affordance, multi-orphan profile picker.
- **Medium-priority polish** (M1–M18 in `PROGRESS.md`): `print` → `os.Logger`, sheet sequencing without `asyncAfter` magic, formatter hoisting, centralizing `WeightSource.caption` on the enum, magic-number extraction in MetricsEngine, `BrainService.mealGapHours` cap fallback at 36 hours, etc. Phase 8 polish.
- **Swift 5.0 → Swift 6.0 build mode bump** (DQ9). Deferred until after Phase 7.
- **Long-term post-v1 backlog**: photo-to-macros revival, cycling route view, HR-series persistence, imperial display, custom launch screen + icon design pass.

---

## v0 lessons baked into v2

1. **Active-logging is a different design problem from reading.** v0's editorial design worked for calm browsing and was wrong for fast gym logging. v2's active screens get bigger inputs, more aggressive primary buttons, less whitespace.
2. **LOG is a primary action.** It belongs visible on every module main, not hidden behind a "+".
3. **Apple Health is read-mostly, write-rarely.** Index writes only `bodyMass`. HK is the source of truth.
4. **Migrations are cheap if you plan for them.** Lightweight-only is the only acceptable kind. The original V1/V2/V3 + `IndexMigrationPlan` design proved this isn't free — see `CLAUDE.md` "Schema evolution rules" for the rules and the recovery contract.
5. **Type-tolerant parsing wins** when the third-party data shape is unstable. The v0 OFF parser uses `JSONSerialization` + `(value as? Double) ?? (value as? Int).map(Double.init) ?? 0`. The v2 rewrite using strict Codable structs returned zeros for half the products tested. Verbatim port restored parity.
6. **Defensive formatting at every display boundary.** `SafeFormat` returns `"—"` for non-finite / out-of-range. The 2026-05-14 incident (a `WeightEntry.weightKg` of ~5×10³⁸ trapping `Int(kg)` in BodyView's formatter) is the proof point.
7. **Apple Health is a peer, not master, on the write path.** Audit H4 + DQ3: when Index writes `bodyMass` and HK rejects, the local `WeightEntry` stays and a non-blocking banner surfaces the failure. Rolling back the local insert would punish the user for HK's auth-state surprises.
8. **Identity-bearing values go in Keychain, not UserDefaults.** UserDefaults is for operational state (sync anchors, toggles, one-shot flags). DevIdentityService's `kSecAttrSynchronizable` flag preserves the userId across uninstall + reinstall when iCloud Keychain is on — important precedent for the Sign-in-with-Apple swap, where Apple's `userIdentifier` is the survivor.
