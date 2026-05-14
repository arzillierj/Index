# Index v2 — Context

Everything a new contributor needs to understand what this app is and how it's organized.

For build commands and the working agreement, see `CLAUDE.md`.

---

## What it is

Index v2 is an iOS app for someone with serious gear — Apple Watch, smart scale (RENPHO), Apple Health — who wants their data **interpreted**, not just displayed. Three modules — **Body**, **Fitness**, **Nutrition** — sit on top of Apple's stack (Sign in with Apple for identity, HealthKit as the data source, CloudKit for private per-user sync). Each module shows raw data plus templated insight sentences from a pure-function **Brain** that reads cross-module signals. Multi-user via Sign in with Apple; no backend, no accounts, no passwords. The audience is a casual-to-serious gym-goer, not a pro athlete.

This is the v2 rebuild. The v0 app lives at `/Users/yannis/Dashboard` and is reference-only — patterns and formulas carry over, code does not.

## Architecture

```
┌─────────────────────────────────────────────┐
│                   BRAIN                     │
│           (MetricsEngine, pure)             │
│  Reads all modules. Computes targets.       │
│  Returns insight sentences per module.      │
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

**Direction of dependency:** Views → Models, Views → Services, Services → Models. Models never import Views or Services.

## Stack

- Swift 6 (with relaxed approachable-concurrency mode)
- SwiftUI + SwiftData
- iOS 26.4+ deployment target
- HealthKit (read 13 types, write `bodyMass` only)
- Open Food Facts API (barcode lookup)
- Anthropic Claude Haiku API (`claude-haiku-4-5-20251001`) for photo-to-macros
- Sign in with Apple (pending paid Developer Program enrollment)
- CloudKit private database (pending paid Developer Program enrollment)

Build settings of note: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `IPHONEOS_DEPLOYMENT_TARGET = 26.4`.

## Modules

### Body
Weight, body composition (body fat %, lean mass), daily vitals (HRV SDNN, VO2 max, resting heart rate), BMI/BMR/TDEE. Logs manual weight; mirrors to Apple Health. Reads RENPHO scale data via Apple Health.

### Fitness
Apple Watch workout auto-import + manual cycling logs + freestyle strength training (no templates). Strength sessions decompose into `ExercisePerformance` rows (one per exercise per session) of `SetEntry` rows (weight, reps, completedAt). The 10-exercise starter catalog (5 free-weight, 3 machine, 2 bodyweight) is the whole catalog — user picks up to 5.

### Nutrition
Barcode scanning (Open Food Facts, cached in `FoodProduct`), photo-to-macros (Claude vision API, logged to `PhotoEstimateLog` for accuracy review), manual entry. Macros tracked as kcal/protein/carbs/fat per entry, plus meal type and source.

### Brain (cross-module)
Pure-static functions in `MetricsEngine` (formulas) + `BrainService` (templated insight sentences). Takes profile + per-module data, returns daily targets and insight strings. No state, no fetching — callers pass `@Query` data in.

## Data model — 11 SwiftData classes

All in `Index/Index/Models/`. Every property has a default; every relationship is optional; no `@Attribute(.unique)` anywhere. CloudKit-shaped from day one.

| Model | Purpose |
|---|---|
| `Profile` | One per Sign-in-with-Apple userId. Holds personalization (age, height, sex, activity, goal, target, units, enabled modules, calorie adjustment, protein target). |
| `WeightEntry` | One weight log. Carries body fat % and lean mass when source provides them. `source ∈ {manual, healthkit, renpho}`. |
| `DailyHealthMetrics` | One row per calendar day. HRV / VO2 max / resting HR upserted from HK. |
| `WorkoutSession` | One workout (Watch auto-import or manual). 6 `WorkoutType` cases: cycling, running, swimming, strength, squash, other. |
| `StrengthSession` | One gym session. Has many `ExercisePerformance` rows. Has a string `id` that `WorkoutSession.strengthSessionId` soft-links to. |
| `ExercisePerformance` | One (session, userExercise) pair. Has many `SetEntry` rows. |
| `SetEntry` | One completed set. Weight in kg, reps, completedAt. |
| `UserExercise` | The user's personal exercise library (max 5 in v1). Derived from `ExerciseCatalog.starter` definitions. |
| `NutritionEntry` | One meal/food log. `mealType ∈ {breakfast, lunch, dinner, snack}`, `source ∈ {manual, barcode, photo}`. |
| `FoodProduct` | Barcode-keyed product cache. Per-100g macros. `useCount` + `lastUsed` for future frequently-eaten surfaces. |
| `PhotoEstimateLog` | Audit log for photo-to-macros estimates with the photo, the estimate, and a `userCorrected` flag. |

Schema is `IndexSchemaV1`. The `IndexMigrationPlan` is wired into the `ModelContainer` from day one (currently empty stages list — every future schema change is a new `VersionedSchema` + a `.lightweight(from:to:)` stage).

## HealthKit

**Read types** (13): `bodyMass`, `bodyFatPercentage`, `leanBodyMass`, `heartRateVariabilitySDNN`, `vo2Max`, `restingHeartRate`, `workoutType()`, `heartRate`, `activeEnergyBurned`, `basalEnergyBurned`, `distanceCycling`, `distanceWalkingRunning`, `distanceSwimming`, `cyclingPower`.

**Write types** (1): `bodyMass` only — manual weight mirrors back to Apple Health.

**Anchor management**: gate anchor advance on the import toggle. If toggle is off, do NOT advance the anchor. This prevents data loss.

**Apple Watch workout-type mapping** — precise on purpose, fixes the two bugs from v0:

| HKWorkoutActivityType | Index `WorkoutType` |
|---|---|
| `.cycling` | `.cycling` |
| `.running`, `.walking` | `.running` |
| `.hiking` | `.other` (different MET — was incorrectly `.running` in v0) |
| `.swimming` | `.swimming` |
| `.squash` | `.squash` |
| `.tennis`, `.badminton`, `.racquetball`, `.tableTennis` | `.other` |
| `.traditionalStrengthTraining`, `.functionalStrengthTraining`, `.crossTraining`, `.highIntensityIntervalTraining`, `.coreTraining` | `.strength` |
| `.yoga`, `.pilates` | `.other` (doesn't drive MPS — was incorrectly `.strength` in v0) |
| `.rowing`, `.elliptical`, `.stairs`, `.stairStepping` | `.other` |
| anything else | `.other` |

## Patterns carried from v0

- Pure-static services for math (`BodyCalculations`, `MetricsEngine`) — formulas in `CLAUDE.md` "Patterns to keep using" section.
- `has-foo` boolean companions for nullable numerics.
- `deletedFromIndex` soft-delete flag on HK-mirrored models.
- ±5-minute reconciliation window for Apple Watch workouts.
- Schema versioning via `VersionedSchema` + `SchemaMigrationPlan` from day one.
- Editorial-Index UI primitives: Masthead, `IndexRow`, mono hero numbers, `IndexChip` quick-adjust rows, big "Complete set" button, rest-timer overlay.

## Things explicitly NOT in v2

Cut after the v0 retrospective. Do not implement.

- TSS / FTP / normalized power
- Sleep tab (Sleep is at most a tile on Body)
- Finance module entirely
- Structured cycling workout templates
- Strength workout templates
- Custom exercise creation
- Frequently-eaten chips
- Metric explanation overlays (long-press → explain BMI etc.)
- Notification system
- Dashboard tab / "Today's Read" prose
- `WorkoutDetailData` lazy-fetch pattern

## v0 lessons baked into v2

1. **Active-logging is a different design problem from reading.** v0's editorial design worked for calm browsing and was wrong for fast gym logging. v2's active screens get bigger inputs, more aggressive primary buttons, less whitespace.
2. **LOG is a primary action.** It belongs visible on every module main, not hidden behind a "+".
3. **Apple Health is read-mostly, write-rarely.** Index writes only `bodyMass`. HK is the source of truth.
4. **Migrations are cheap if you plan for them.** Lightweight-only is the only acceptable kind; redesign anything that needs custom migration logic.
