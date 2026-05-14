# Index v2 — Progress

What shipped, what's next, and what the audit surfaced.

For the product overview see `CONTEXT.md`. For the working agreement see `CLAUDE.md`.

---

## Status (2026-05-15)

- **Phases 1–6 complete.** App builds clean. Onboarding works end-to-end. All three modules (Body, Fitness, Nutrition) wired with logging + listing + detail. Apple Watch workout auto-import + historical backfill working. Barcode scanner working against real products via Open Food Facts.
- **Phase 7 (Settings) not started.**
- **Audit complete; punch list pending triage.** No critical issues found; ~24 high-priority items, mostly silent-failure paths, dead code, and a handful of additive schema bumps.

---

## Phases shipped

### Phase 1 — Foundation

| Step | What |
|---|---|
| 1 | HealthKit usage descriptions in build settings |
| 2 | 11 SwiftData models, IndexSchemaV1, ModelContainer (later replaced — see Phase 5 hotfix below) |
| 3 | Root docs (CLAUDE.md, CONTEXT.md, README.md) |
| 4 | IdentityService protocol + Dev/Apple implementations |
| 5 | ProfileService with orphan-profile migration path |

### Phase 2 — Services

| Step | What |
|---|---|
| 6 | MetricsEngine — ported v0 formulas verbatim (BMI, BMR, TDEE, LBM, IBW + daily target reconciliation) |
| 7 | BrainService — per-module insight sentences |
| 8 | HealthKitService — reads + bodyMass write + v0 audit fixes (anchor gating, kcalBurned read, max HR capture, RENPHO source detection, distance read perms) |
| 9 | ClaudeService — photo-to-macros only **(now dead code; photo flow cut from v1)** |

### Phase 3 — Onboarding

| Step | What |
|---|---|
| 10 | Onboarding flow screens 1–8 |
| 11 | Profile persistence + routing |
| 12 | Apple Health authorization at onboarding step 8 |
| fix | Onboarding layout + keyboard responsiveness |

### Phase 4 — Body

| Step | What |
|---|---|
| 13 | BodyView main screen |
| 14 | LogWeightSheet |
| 15 | WeightEntryDetailSheet |
| 16 | WeightHistoryView |
| 17 | RENPHO grouping requires matching HK source bundle id |
| fix | Chart x-axis date format + recent-entries swipe-to-delete |
| fix | Remove tap-to-explain on Body metric tiles (per "no metric overlays" cut) |

### Phase 5 — Fitness + Strength

| Step | What |
|---|---|
| 18 | FitnessMainView + TabView wiring |
| 19 | LogActivitySheet activity picker |
| 20 | LogCyclingSheet + intensity field |
| 21 | LogOtherWorkoutSheet (parameterized for running / swimming / squash / other) |
| 22 | WorkoutDetailView (parameterized for all non-strength types) |
| 23 | Strength sub-flow (ActiveStrengthSession + library + picker + detail + rest timer) |
| 24 | HealthKit workout auto-import wired in |
| hotfix | One-shot data wipe on next launch (a transient state-corruption recovery) |
| hotfix | Input guard rails + defensive formatting (`SafeFormat`, `FieldValidation`) — direct response to the 5×10³⁸ kg incident |
| step+ | Historical Apple Health workout backfill (one-shot since Jan 1) |
| hotfix | **Schema recovery** — V1/V2/V3 + IndexMigrationPlan generated "Duplicate version checksums detected"; replaced with single `IndexSchema.models` list relying on lightweight migration. See `CLAUDE.md` "Schema evolution rules" |

### Phase 6 — Nutrition

| Step | What |
|---|---|
| 25 | NutritionMainView + 3-tab wiring |
| 26 | Log method picker + manual entry + meal detail |
| 27 | BarcodeScannerView (AVFoundation, EAN-8/13, UPC-A/E, ITF-14, Code 128) |
| port | Verbatim port of v0 OFF service + result sheet — replaces broken v2 Codable parser that returned zeros for products with valid macros |
| 28 | Barcode scanner UI polish — full-word macro labels + g/ml unit toggle |

---

## Phase 7 — Settings (not started)

Planned scope, derived from audit-surfaced gaps:

- Workout import on/off toggle (currently UserDefaults-defaulted to ON, no UI)
- Module enable/disable toggles (currently set during onboarding only)
- Profile editor (name, age, height, sex, activity, goal — onboarding-only today)
- Calorie adjustment + protein target editor (currently default 0 / 150)
- Imperial/metric units (model field exists; no view branches on it)
- Re-grant Apple Health authorization
- "Reset all data" affordance (wires into the existing self-healing recovery)
- Sign out / delete account (will need real bodies once SIWA enrollment lands)
- Multi-orphan-profile picker (audit DQ7-adjacent)

Audit fixes that should land **with or before** Phase 7:
- Observer-stop API on `HealthKitService` so the Settings toggle actually stops new HK delivery
- HK write failure surfacing to LogWeightSheet (`saveWeight → async throws`)
- Transactional save in ProfileService migration accept/decline
- Discriminated catch in IndexApp recovery (don't wipe on disk-full)
- Replace second-fail `fatalError` with hard-error UI

---

## Audit punch list (2026-05-15)

Full per-file findings live in the conversation transcript. Headline numbers: 0 critical, ~24 high, ~30 medium, ~13 low. Effort estimate: ~20-25h for High tier, ~10-12h for Medium.

### High-priority items, grouped

**Dead-code removal (4 items, all S effort)**
- Delete `Services/ClaudeService.swift` — photo flow cut.
- Delete `Models/PhotoEstimateLog.swift` + remove from `IndexSchema.models` — phantom on-disk table.
- Mark `NutritionEntry.photoEstimated`, `NutritionSource.photo`, `NutritionEntry.deletedFromIndex`, `UserExercise.notes` as `// DEPRECATED:`. (Cannot delete per schema rules; deprecate the writers.)

**HK + write-path failure surfacing (4 items)**
- `HealthKitService.saveWeight` → async throws + banner in LogWeightSheet.
- `HealthKitService` — bind WeightEntry dedup to HK sample UUID (additive `WeightEntry.hkSampleUUID: String?`).
- `HealthKitService.enableBackgroundDelivery` — log enrollment failure instead of swallowing.
- `HealthKitService` — observer-stop API for Phase 7 Settings toggle-off.

**Schema bumps (4 additive items, each must include `// SCHEMA:` marker)**
- Add `WeightEntry.hkSampleUUID: String?` (with paired dedup change above).
- Add `StrengthSession.inProgress: Bool = true` (replaces the same-tick `endDate <= date` heuristic).
- Add `Profile.hasProteinTarget: Bool = false` (so default-150 is distinguishable from user-set-150).
- Change `DailyHealthMetrics.date` default from `Calendar.current.startOfDay(for: .now)` to `.distantPast` sentinel (latent migration safety).

**ProfileService transactional saves (2 items)**
- `acceptMigration` / `declineMigration` need explicit `try context.save()` wrapped in do/catch.
- `ContentView.completeOnboarding` needs the same.

**Identity / IndexApp robustness (3 items)**
- Replace four `fatalError`s in `AppleSignInIdentityService` with non-trapping stubs (return nil/false/throw soft error).
- Migrate `DevIdentityService` userId from UserDefaults to Keychain (with one-shot UserDefaults → Keychain copy on first launch under new code).
- `IndexApp` — discriminate the recovery catch on `SwiftDataError` migration cases; remove the second-fail `fatalError`; gate `hkService.bootstrapIfAuthorized()` on having an active Profile.

**Onboarding numeric guards (1 multi-site item)**
- Range-validate `heightCm` (100–250), `targetWeightKg` (when `hasTargetWeight`), and require `selectedExerciseIds.count >= 1` when Fitness is enabled.

**Manual workout input guards (2 items)**
- `LogCyclingSheet` and `LogOtherWorkoutSheet` — bound duration (1–1440 min) and distance (0–300 km) via `FieldValidation`.

**Performance / caching (3 items)**
- Cache derived metrics in `BodyView`, `FitnessMainView`, `NutritionMainView`, `ActiveStrengthSessionView` so MetricsEngine + BrainService don't run per `body` render.
- Bound `ActiveStrengthSessionView` and `ExerciseDetailView` `@Query<StrengthSession>` predicates to a sane time horizon.
- Hoist per-call formatters (RelativeDateTimeFormatter, DateFormatter, UINotificationFeedbackGenerator) to static lets.

**Eliminate side-channel mutation (1 item)**
- `HealthKitService.modelContext` — pass `ModelContainer` at construction instead of mutating from `ContentView.task`.

**Misc HIGH (3 items)**
- `BarcodeResultSheet` save dedup → replace `try?` with explicit error handling.
- `BarcodeScannerView` setup failures → surface to SwiftUI parent instead of silent black screen.
- `Profile.encodeModules` failure fallback → return the full default-set JSON, not `"[]"` (encode/decode symmetric).

**Project config (2 items)**
- Add `INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.healthcare-fitness"` (App Store submission requirement).
- `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` for Release.

### Medium-priority items (samples)

- Centralize `print` → `os.Logger` (5 sites).
- Sheet sequencing without `asyncAfter(0.4)` magic (FitnessMainView + NutritionMainView).
- Combine `fetchAvgHeartRate` + `fetchMaxHeartRate` into one HK round-trip.
- WeightEntry input range validation at the HK auto-import path (defense against the 5×10³⁸ class of incident at the *write* path, not just display).
- Centralize `WeightSource.caption` (currently triplicated across BodyView, WeightHistoryView, WeightEntryDetailSheet).
- `URL(string: ...)!` force-unwrap removal in OpenFoodFactsService (and ClaudeService if not deleted).
- `StrengthLibraryView` swipe → confirmation dialog.
- Extract magic numbers in `MetricsEngine` (1200 kcal floor, 1.1 BMR safety, 0.01 weekly-rate threshold).
- `BrainService.mealGapHours` cap fallback at 36 hours so an empty week doesn't render "168 hours".
- `BrainService.hrvTrendPct` add `.isFinite` guards.
- `setupOnAppear` in `ActiveStrengthSessionView` — gate on `session == nil` to be re-appear-safe.
- Explicit `SWIFT_STRICT_CONCURRENCY = complete` build setting.

### Deferred questions (need product-level decisions)

The audit surfaced 10 items where current behavior could be intentional. Listed here so they can be answered before fixes proceed:

1. **MetricsEngine 75 kg fallback** — when no weight history AND no target, every body-math call falls back to 75 kg. Intentional ballpark or should the brain insight suppress until real data exists?
2. **NutritionEntry.deletedFromIndex** — field exists but the swipe path uses hard-delete. Was a future "show deleted" surface planned, or just deprecate?
3. **HealthKitService.saveWeight failure UX** — banner-and-keep-local, or roll back the SwiftData insert if HK rejects?
4. **StrengthLibraryView delete cascade** — keep "history shows 'Unknown exercise'" or soft-hide-from-library and preserve the row?
5. **IndexApp second-fail recovery** — show error UI once, or build a small retry budget?
6. **Onboarding step 7 minimum-1-exercise validation** when Fitness is on — block or allow?
7. **`Profile.calorieAdjustmentKcal` and `proteinTargetG`** — Phase 7 Settings exposure planned, or vestigial?
8. **`WeightEntry.notes`** — write-only display-wise; surface or deprecate?
9. **Swift 5.0 → Swift 6.0 build-mode bump** — now or after Phase 7?
10. **HK observer toggle-off** — also delete previously-imported HK rows, or just stop new imports?

---

## Long-term backlog (post-v1)

From the v0 carryover + audit notes:

- **Photo-to-macros (revived)** — Claude Haiku / future model + UserDefaults → Keychain for the API key. Photo audit log model (`PhotoEstimateLog`) currently dead; would need to come back if the feature is revived.
- **Cycling route view** — `WorkoutDetailView` cycling section has a placeholder "coming in a later release" tile.
- **HR series + Tanaka zone breakdown on WorkoutDetailView** — v0 pattern was lazy-fetch from HK; v2 design is to persist with the WorkoutSession (schema bump).
- **Imperial display units** — `MetricsEngine.kgToLbs` etc. exist but no view branches on `Profile.units`.
- **Custom launch screen + app icon design pass.**
- **Multi-orphan profile picker** in Settings (today only the count==1 case auto-stages a migration prompt).
- **Sleep tile** on Body (cut from top-level tab; tile is open).
