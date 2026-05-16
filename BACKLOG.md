# Index v2 — Backlog

Single home for everything not yet built: open bugs, pre-release requirements, deferred features, and code polish.

Nothing in this file describes shipped behaviour. If an item ships, move it out of here and into `CONTEXT.md`.

---

## Open bugs (undiagnosed)

- **Lean-mass delta missing on the Body screen.** The body-fat tile shows a delta; the lean-mass tile does not. Cause unknown — either the demo generator writes body-fat and lean-mass independently (so some demo rows have one field but not the other), or the lean-mass delta's previous-value lookup is wrong.
  - **Status:** Reproduced in demo; not yet investigated in real mode.
  - **Next step:** Open the Body tab in REAL mode and check whether lean mass shows a delta. Present → demo-generator fix. Absent → delta-logic fix. Do not write a fix until this is known.

---

## Required before TestFlight

- **Privacy policy.** HealthKit apps need one for App Review (guideline 5.1.1(i)) before any external tester. A short plain-text page with a URL entered in App Store Connect is enough.
  - **Status:** Not started.
  - **Next step:** Write the page, host it, add the URL in App Store Connect.

---

## Deferred — not built, by choice or by blocker

- **Dynamic Type on hero numerals.** Type scaling was applied partially via semantic font tokens; the large hero numerals may still be fixed-size.
  - **Status:** Partial — small/mid tokens scale; hero point sizes are fixed.
  - **Next step:** Confirm current behaviour at the largest Dynamic Type setting, then decide whether to finish it.

- **Dark Mode.** Deliberately not built. Backlog only.
  - **Status:** Not started, not planned for v1.
  - **Next step:** None until v1 ships.

- **CloudKit sync.** Blocked on paid Apple Developer enrollment.
  - **Status:** Models are CloudKit-shape compliant; capability not enabled.
  - **Next step:** After enrollment, add `cloudKitDatabase: .private(...)` to the `ModelConfiguration` in `IndexApp.sharedContainer`. Single-line change.

- **Sign in with Apple.** Blocked on paid Apple Developer enrollment.
  - **Status:** `AppleSignInIdentityService` exists as non-trapping stubs; protocol seam is in place.
  - **Next step:** After enrollment, fill the four method bodies and flip `AppDependencies.identity` from `DevIdentityService()` to `AppleSignInIdentityService()`.

- **Cycling route view.** `WorkoutDetailView` cycling section renders a "coming in a later release" placeholder tile.
  - **Status:** Placeholder only.
  - **Next step:** Decide between a static snapshot (HK route polyline) and a richer MapKit pass; build whichever once a real cycling workout with route data is in hand.

- **Tanaka HR-zone breakdown.** The HR chart is live for every workout type via `HealthKitService.fetchHRSeries(forWorkoutUUID:)`; the per-zone summary on top of those samples is not built.
  - **Status:** Series available; aggregation not built.
  - **Next step:** Compute % time in each Tanaka zone from the existing series; surface as a small horizontal bar under the chart in `WorkoutDetailView`.

- **Imperial display units.** `MetricsEngine.kgToLbs` / `lbsToKg` / `cmToFtIn` exist but no view branches on `Profile.units`.
  - **Status:** Helpers in place; no view consumer.
  - **Next step:** Route every weight / height display through a single formatter that reads `Profile.units`; pick one display surface (BodyView hero is a reasonable first target) and wire it.

- **Multi-orphan profile picker.** Today only the `count == 1` orphan case auto-stages a migration prompt. Two or more orphan Profiles on the same device have no UI path.
  - **Status:** Single-orphan path only.
  - **Next step:** Add a Settings affordance that lists every orphan Profile and lets the user pick / merge / delete.

- **Swift 5 → Swift 6 build mode bump (DQ9).** Build mode is currently Swift 5 with the Sendable upcoming features explicitly enabled (see `project.pbxproj`).
  - **Status:** Deferred until after Phase 7-era features settle.
  - **Next step:** Flip to Swift 6 mode, fix the resulting actor / Sendable diagnostics, run device tests.

- **Custom launch screen.** Auto-generated launch screen ships today; the app icon shipped separately (`I.` wordmark with green accent dot, commit `c846d97`).
  - **Status:** Auto-generated.
  - **Next step:** Design a custom launch screen and wire it into the asset catalog.

---

## Code polish (post-audit)

Audit Medium-tier items (M1–M18) that did not ship in the Phase 5 rounds. Items the audit flagged but classified as polish rather than correctness; each is small and independently committable.

- **M1 — `print` → `os.Logger`.** 5 sites: `IndexApp:27`, `HealthKitService:81`, `BarcodeResultSheet:285 / 290 / 350`.
  - **Status:** All sites still use `print`.
  - **Next step:** Define a single `Logger(subsystem:category:)` per file and replace each `print`.

- **M3 — `SWIFT_STRICT_CONCURRENCY = complete` explicit setting.**
  - **Status:** Not set explicitly in the Index target's build settings.
  - **Next step:** Add the setting at the target level; fix the resulting diagnostics.

- **M4 — `FitnessMainView` sheet sequencing.** `handleActivityChoice` uses `DispatchQueue.main.asyncAfter(deadline: .now() + 0.4)` to bridge a sheet dismiss into the next presentation.
  - **Status:** `asyncAfter(0.4)` in place.
  - **Next step:** Replace with `.sheet(isPresented:onDismiss:)` chained against a pending-intent enum.

- **M5 — `Profile.hasProteinTarget` companion.** Today there's no way to distinguish "default 150 g" from "user explicitly set 150 g". Additive schema bump.
  - **Status:** Field not present.
  - **Next step:** Add `hasProteinTarget: Bool = false` with `// SCHEMA: additive` marker; flip it true when the user saves a value through `ProteinTargetEditSheet`.

- **M6 — Log unmapped `HKWorkoutActivityType`.** `HealthKitService.mapWorkoutType(_:)` silently maps everything unknown to `.other`.
  - **Status:** Silent mapping.
  - **Next step:** Telemetry-style `print` (or `os.Logger` once M1 lands) for the unmapped raw value so a future addition is discoverable.

- **M7 — One HK round-trip for avg + max HR.** `processHKWorkout` calls `fetchAvgHeartRate` and `fetchMaxHeartRate` separately, doubling the query for every imported workout.
  - **Status:** Two round-trips.
  - **Next step:** Combine into one statistics-options query.

- **M9 — Input range validation at the HK auto-import path for weight.** `LogWeightSheet` has `FieldValidation` guards; the HK observer-driven write path does not. Defense-in-depth against the 5×10³⁸ kg class of incident at the *write* path.
  - **Status:** Only the manual path validates.
  - **Next step:** Apply a sanity range to `handleNewBodyMass` before inserting `WeightEntry`.

- **M10 — Hoist formatters to `static let`.** `RelativeDateTimeFormatter`, `DateFormatter`, `UINotificationFeedbackGenerator` are instantiated per call at several sites.
  - **Status:** Multi-site.
  - **Next step:** Replace per-call inits with file-scoped `static let` instances.

- **M11 — Centralize `WeightSource.caption` on the enum.** Currently triplicated across `BodyView`, `WeightHistoryView`, `WeightEntryDetailSheet`.
  - **Status:** Triplicated.
  - **Next step:** Add `var caption: String` to the enum; delete the per-view helpers.

- **M12 — Force-unwrapped URL in `OpenFoodFactsService`.** `URL(string: ...)!` survives a refactor that *does* introduce a parsing failure mode.
  - **Status:** Force-unwrapped.
  - **Next step:** Route through `URLComponents` or `guard let url else { throw }`.

- **M13 — `StrengthLibraryView` swipe → confirmation dialog.** DQ4 made the swipe a soft-hide (less destructive than it was), but a confirm step is still worth it.
  - **Status:** No confirmation.
  - **Next step:** Wrap the soft-hide action in `.confirmationDialog`.

- **M14 — Extract magic numbers in `MetricsEngine`.** 1200 kcal floor, 1.1 BMR safety, 0.01 weekly-rate threshold are bare literals in the body of `dailyTargets` / `aggressiveLossBuffer`. (Note: the 1200 / 1.1 floor was removed in the calorie-target fix; the 0.01 weekly-rate threshold remains.)
  - **Status:** Literal in source.
  - **Next step:** Pull surviving constants into named `static let` at the engine's top level.

- **M15 — `BrainService.mealGapHours` cap fallback at 36 hours.** Prevents the rule from rendering "168 hours since last meal" for empty-week users.
  - **Status:** Uncapped.
  - **Next step:** Cap at 36 h; rule short-circuits above.

- **M16 — `BrainService.hrvTrendPct` `.isFinite` guards.** A zero baseline divides cleanly to infinity; the rule fires nonsense.
  - **Status:** No guard.
  - **Next step:** Add `.isFinite` checks on latest and baseline before the percent compare.

- **M17 / DQ1 — `Optional<DailyTargets>` when no weight.** Today `MetricsEngine.dailyTargets` falls back to a 75 kg sentinel and produces a target the user never asked for. Brain insights then fire against that fiction.
  - **Status:** Sentinel weight returned.
  - **Next step:** Return `DailyTargets?` and suppress the Nutrition hero numerals + the brain insights on day-one (no logged weight).

- **M18 — `asyncAfter` cleanup mirroring M4.** `NutritionMainView.routeAfterScanner` uses the same brittle `asyncAfter(0.4)` pattern.
  - **Status:** Same as M4.
  - **Next step:** Apply the same `.sheet(onDismiss:)` chain treatment.

---

## Standing note

- **Dogfood before building.** The build phase is essentially done and the app has ~1 year of demo data. Use Index daily for ~2 weeks before adding features so the next changes come from real friction. The calorie-target bug is the precedent — it was found by using the app and checking the math, not by planning.
