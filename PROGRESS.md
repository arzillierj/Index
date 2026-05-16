# Index v2 — Progress

What shipped, what's next, and what the audit produced.

For the product overview see `CONTEXT.md`. For the working agreement see `CLAUDE.md`.

---

## Status (2026-05-16)

- **Phases 1–7 complete + theme refresh + AI macro estimator + camera redesign.** App builds clean (Debug + Release, zero warnings). All three modules wired end-to-end with logging + listing + detail. Apple Watch workout auto-import + historical backfill working. Settings ships every Phase 7 toggle (modules, manual-logging gates, eat-back workout calories, signed calorie adjustment, notifications, AI estimator). Local notifications fire on new HK workout / weigh-in (opt-in per type). Centralized `IndexPalette` colors + `IndexFont` SF Pro typography. Per-module tab tinting.
- **AI macro estimator shipped.** Nutrition Camera screen does both barcode lookup (free, OFF) and AI photo macro estimates (Anthropic Haiku 4.5, image downscaled, cost-gated through a monthly budget cap stored in `AIUsageRecord` rows). Camera redesigned: meal capture is the default posture, barcode auto-fires on stable detection (no chip, no tap — same OFF lookup, just a different trigger).
- **Audit Phase 5 complete.** 24 H-tier fixes + 1 DQ-derived schema bump + DQ8 review shipped across 5 rounds — see "Audit Phase 5" section below for the per-round commit table.

### Post-Phase-7 follow-ups

- **AI macro estimator — foundation.** ClaudeService revived (was deleted in audit H2 with the rest of the photo-to-macros flow). New `AIUsageRecord` SwiftData model tracks one row per successful API call; sum across the current calendar month gates the budget. Anthropic API key is stored in **Keychain** (`index.ai.anthropicAPIKey`, `kSecAttrAccessibleAfterFirstUnlock` + iCloud-Keychain sync) — never compiled in, never committed, never written to a doc. Monthly budget (UserDefaults, default $2.00) is editable via a Settings slider $0 – $50 step $0.50. Cost constants are Haiku 4.5 (claude-haiku-4-5-20251001) per-million-token rates, verified May 2026. Settings ships a new "AI estimation" section between Notifications and Data: API key row (Set / Configured ✓ — never displays the stored key back), Monthly budget row, This month spend row (renders red when over budget). No API call wired up in this commit — the network commit was a separate follow-up.

- **AI macro estimator — camera + vision call.** Nutrition "Scan barcode" button became **Camera**: a single live-preview screen that handles both paths. Barcode auto-detect is unchanged + free (existing OpenFoodFacts path). A shutter button + photo-library picker route a still image through the new `ClaudeService.estimateMacros(from:in:)` — pre-flight gates on `isWithinBudget` + `hasAPIKey`, image downscaled to ≤1024px longest edge JPEG q=0.7, POSTs to `api.anthropic.com/v1/messages` with the model id `claude-haiku-4-5-20251001`, parses the structured `MacroEstimate` JSON the model returns (strips optional ``` ```json fences ``` defensively), records the response's `usage.input_tokens` + `usage.output_tokens` as an `AIUsageRecord` row BEFORE the parse step so the cost lands even if parsing fails. The estimate's `isFood` self-check keeps the camera open with a "That doesn't look like food" inline message rather than opening the result sheet on a non-food photo. Success routes to the existing `LogMealManualSheet` pre-filled with name + macros + an AI-confidence hint ("low" gets a warning-tinted caption). Hard-stop errors (budget exceeded, no key, network failure, parse failure) surface as alerts with a manual-entry fallback button. Info.plist gained `NSPhotoLibraryUsageDescription`; existing camera description expanded to mention meal-photo capture.

- **Camera screen redesigned — meal capture is the default.** Removed the green framing rectangle, the animated scan line, the vignette darkening, and the supported-formats caption — the camera feed now shows full-frame and undimmed. Barcode detection still runs continuously in the background but no longer auto-fires the OFF lookup; instead a chip ("Barcode detected — tap to look up") slides up from above the shutter when a code is in frame, slides away after a 2-second grace period without a fresh detection, and routes to the existing OFF lookup only on tap. ScannerViewController gains a 0.5s detection throttle so a continuously-in-frame barcode ticks the chip's grace timer once per ~half-second rather than at the camera's frame rate. Reason for the tap-to-confirm shift: with a full-frame camera and no aiming rectangle, barcodes drift through frame incidentally while the user is lining up a meal photo — auto-firing would yank them into a barcode result they didn't ask for. (Superseded — the chip was removed for auto-fire; see the auto-fire entry below.)

- **Nutrition food history screen (2026-05-16).** New `FoodHistoryView` pushed from Nutrition via a "See all" link next to TODAY'S LOG. Shows every `NutritionEntry` grouped by `MealType` (Breakfast → Lunch → Dinner → Snack — empty sections collapse), newest-first within each. Tap → dismisses + re-logs through the existing `manualEntryPrefill` → `LogMealManualSheet` flow with name + macros + meal type pre-filled. Saving creates a NEW entry dated today; the original is untouched. `ManualEntryPrefill` gained an optional `mealType` field; `LogMealManualSheet` gained `prefilledMealType`. Duplicates intentional (full log, not deduplicated). Empty state: "No meals logged yet". Demo mode's ~1200 entries populate the screen richly out of the box.

- **Camera barcode auto-fire on stable detection (2026-05-16).** Removed the tap-to-confirm chip + its 2s grace-period task. SwiftUI parent now keeps a `(candidateCode, firstSeenAt, lastDetectionAt, lastFiredCode)` stability tuple; when the same barcode value is detected continuously for ≥ 0.6s (`stabilityWindow`) the OpenFoodFacts lookup fires automatically. A detection gap >0.8s (`gapResetWindow`) restarts the window, so a stale code can't accumulate stale time. Each code fires at most once per camera presentation; dismissing the result and reopening the camera resets via fresh `@State`. Controller throttle tightened from 0.5s → 0.15s so the stability window gets ~4 samples before firing — a single-frame sweep across a barcode never accumulates. Shutter + photo-library paths unchanged.

- **Nutrition calorie target fix (2026-05-16).** `MetricsEngine.dailyTargets` had a soft clamp `let caloriesBase = max(max(1200, BMR * 1.1), TDEE + adjustment)` that silently lifted any deficit-driven target above ~BMR×1.1. For a 2674 TDEE / 1945 BMR profile with a -1000 adjustment the user saw 2139 (= BMR × 1.1) instead of the expected 1674 — roughly half the requested deficit silently eaten. Removed the soft clamp entirely; target is now linear `TDEE + signed adjustment`. Safety lives at the input boundary (slider already bounded to ±1000 kcal in 50-kcal steps). Verified across the range: 0 → 2674, -1000 → 1674, +1000 → 3674. New CLAUDE.md rule under audit-derived patterns documents the linear-target contract.

- **Body "Time asleep" tile (2026-05-16).** Replaces the static "Ideal range" tile in the COMPOSITION grid. New `HealthKitService.fetchLastNightSleep` reads `HKCategoryType(.sleepAnalysis)` in a yesterday-6pm → today-2pm window, sums only the asleep category values (`asleepCore` / `asleepDeep` / `asleepREM` / `asleepUnspecified` — never `inBed`), and dedups across sources by picking the bundle with the most coverage. `sleepAnalysis` added to `readTypes`; covered by the existing `NSHealthShareUsageDescription`. Tile renders e.g. "7h 12m" or the "—" empty state for no-data / no-auth — never "0h 0m". No delta (sleep data is too sparse for a reliable comparison). In demo mode, `DemoDataService.lastNightSleepSeconds()` returns a day-seeded believable value (6h 20m – 8h 10m) so the showcase doesn't read empty.

- **Body tile delta — VITALS on its own line (2026-05-16).** VITALS tiles are three-across and too narrow for inline value+unit+delta — resting HR was clipping to "↑ 1...". New `DeltaPlacement.belowValue` mode renders the delta as a third row beneath the value+unit; an invisible placeholder reserves the same line height when a delta is absent so a real-mode tile with only one HK measurement still aligns with its siblings. COMPOSITION stays `.inline` (two-across, fits fine). Colors, direction-of-good logic, comparison basis unchanged.

- **Body tile delta — inline (2026-05-16).** Moved the delta indicator from a third line below the value to the same HStack as value+unit so a tile with a delta has the SAME height as one without — COMPOSITION + VITALS grids are uniform again. `layoutPriority(-1)` on the delta so it compresses BEFORE the value under tight space (the value owns the line). `lineLimit(1)` + `minimumScaleFactor(0.7)` on the delta keep it readable at large Dynamic Type sizes without bumping the tile height. VO2 max delta omits the trailing-space-unit since its unit is empty.

- **Body tile delta indicators (2026-05-16).** Five Body tiles (body fat, lean mass, HRV, VO2 max, resting HR) gained a small arrow + absolute-change indicator vs. the previous recorded measurement. Color follows direction-of-good (`GoodDirection.up` / `.down` per metric) — body fat dropping is GREEN, lean mass dropping is RED, resting HR rising is RED, HRV/VO2 rising is GREEN. Arrow direction tracks the number; color tracks the user-good interpretation. Descriptive metrics (BMI / BMR / TDEE / ideal range) intentionally show no delta — coloring them would lie. Body-comp deltas walk the newest-two WeightEntry rows with the metric's has-flag (so RENPHO entries with composition are compared to the previous RENPHO weigh-in, manual entries without are skipped); vitals deltas walk DailyHealthMetrics with hasHRV / hasVO2Max / hasRestingHeartRate. Sub-display-precision changes return nil (no "↑ 0.0" arrows). Uses existing `IndexPalette.Semantic.success` / `.error` + `IndexFont.tileUnit` — no new color or font tokens introduced.

- **Demo data mode (2026-05-16).** UserDefaults flag (`demoModeEnabled`) selects between two physically separate SwiftData stores at launch — real (`default.store`) or demo (`Index-demo.store`). `IndexApp.sharedContainer` reads the flag once and builds a single `ModelConfiguration` against the chosen URL; the two stores are never co-resident. New `DemoMode` helper centralizes the flag + store URL + reset. New `DemoDataService.seedFreshDataset` generates a believable rolling-year dataset on first launch into demo mode (one Profile, 10 starter exercises, ~280 weights with downward trend and gaps, ~150 workouts clustered with realistic week-by-week density, ~25 strength sessions with set/rep progression, ~1200 nutrition entries averaging ~3.5/day, ~320 daily HRV/VO2/RHR rows). Workouts are HK-shape (source = .healthkit + fake `hkWorkoutUUID` + `hasHeartRate = true`) so the workout-detail HR chart fires; new `DemoHRSeriesGenerator` stands in for the live HK fetch with a procedural deterministic-per-UUID series (warmup → noisy plateau → cooldown). `AIUsageRecord` is **not** seeded; `ClaudeService.estimateMacros` short-circuits with `.demoModeActive` so the AI cost ledger stays at $0.00 in demo. HK bootstrap is skipped in demo mode. New `DemoBadge` pill rendered next to each module page-title when the flag is on so the user can never mistake demo for real data. New Demo section in Settings with toggle + confirmation alert + clean `exit(0)` (iOS doesn't allow self-relaunch) + "Reset demo data" action that deletes the demo store files for regeneration on next launch. NO schema change, NO model flag, NO `@Query` filter — isolation is structural (distinct files on disk).

- **HR chart on every workout type (2026-05-16).** Live `HealthKitService.fetchHRSeries(forWorkoutUUID:)` (generic, time-window query against `HKQuantityType(.heartRate)`) replaces the Swimming-only swim-detail HR slot in `WorkoutDetailView`. Squash, Cycling, Running, Other now render the same red HR chart + "XXX BPM AVG" annotation that Swimming has — same component, no second implementation. Gated on `session.source == .healthkit && session.hasHeartRate && session.hkWorkoutUUID != nil`; manual workouts and HR-less imports hide the section entirely. View-only change — no schema touch (Case A: HR series is fetchable live, was never persisted). Swim path still calls `fetchSwimDetail` for sets/lengths/SWOLF, then mirrors `swimDetail.hrSamples` into the unified `hrSeries` state so the chart reads one source.

- **Layout-hardening regression fix (2026-05-16).** Two regressions from the seven-section commit. (a) `BodyView.trendChart` AreaMark used Swift Charts' implicit y=0 baseline; with the new tight `chartYScale(domain: lo...hi)` the area drew from y=0 up to the data point and bled outside the chart frame — tinting COMPOSITION / VITALS / RECENT ENTRIES blue. Fix: explicit `yStart: .value("Floor", domain.lowerBound)` so the area is bounded inside the visible plot region; `.clipped()` on the chart frame as defense. (b) `.toolbarBackground(.visible, for: .navigationBar)` still rendered a translucent Liquid Glass material on iOS 26, so scrolled content remained visible under the status bar. Fix: pass an explicit `Color` (`IndexPalette.Surface.background`) plus `.toolbarBackgroundVisibility(.visible, for: .navigationBar)` — the bar is now fully opaque and matches the page surface. Applied to Body, Fitness, Nutrition + WorkoutDetailView + StrengthSessionDetailView (the last two didn't have any toolbarBackground at all in the original commit). The Section 5 grid + Section 1 y-axis auto-range from the prior commit are intact and untouched.

- **Layout hardening pass (2026-05-16).** Seven-section device-feedback fix across Body / Fitness / Nutrition / WorkoutDetail. (1) **Weight chart Y-axis** — `BodyView.trendChart` now auto-ranges via `weightDomain(_:)` with padding `max(span * 0.15, 0.5)`; previous fixed `0…100` domain collapsed a real 87.3–87.5 kg series into a flat line. (2) **Safe-area top inset** — `.toolbarBackground(.visible, for: .navigationBar)` on each module's `ScrollView` so scrolling page-title content stops at the safe-area boundary instead of bleeding under the status bar. (3) **Page-title breathing room** — `.padding(.top, 6)` on every module `pageTitle` so cap-height glyphs don't sit flush against the nav bar edge. (4) **Tile clip-proofing** — every `tile / statTile / macroTile` helper across `BodyView`, `WorkoutDetailView`, `StrengthSessionDetailView`, `NutritionMainView` gained `.lineLimit(1) + .minimumScaleFactor(0.6)` on the numeral and `.layoutPriority(1)` on the trailing unit so "67.0 kg" / "74–90 kg" / "410 kcal" / "188 cm" never let the unit clip; numeral shrinks first. (5) **WorkoutDetailView card grid** — `LazyVGrid` → SwiftUI `Grid` walked in pairs with the trailing odd cell `.gridCellColumns(2)` for full-width; Cycling's "2+1 with orphan card" layout becomes "2+1 full-width". (6) **Apple Health attribution placement** — `sourceBadge` moved from the duration-hero HStack to the date line, freeing the hero to take its row and reading as a quiet sibling of the date rather than a chip pressed against the numeral. (7) **Dynamic Type — partial.** `IndexFont.tileLabel / tileUnit / sectionCap / heroCaption / rowTitle / rowValue / rowSecondary` now use semantic `Font.system(.style, weight:)` so they scale with system text size; `hero` 56pt + `tileValue` 24pt + `heroUnit` 22pt stay fixed point sizes (deferred — `Font.custom` is the only path to scaling-system-font at a specific point size and we don't use a custom font). The tile clip-proofing from (4) compensates: tile values shrink when surrounding labels grow.

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
| 9 | ClaudeService — photo-to-macros only **(deleted in audit H2; photo flow cut from v1)** |

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

### Phase 6+ — Swim detail + Nutrition main refresh

| Commit | What |
|---|---|
| `9af2eff` | Swimming workout detail — HR chart + Avg SWOLF + Pool Length + Auto Sets sheet (per-set summary groups same-stroke runs; per-length breakdown shows individual 25m laps with stroke + time + SWOLF) |
| `3d88285` | Nutrition main: Calories + Protein dual hero + behavior-based Frequent foods chip row (top-5 by last-30-day frequency) |
| `1609989` | Nutrition main hero polish — Calories + Protein floats on page background (cards stripped) |

### Audit Phase 5 — 2026-05-15

5 rounds, 25 commits on `origin/main` between `daca14c` (H2 dead-code delete) and `cbff27c` (H18 derived-metrics hoisting). Build clean (Debug + Release, zero warnings) at every round close. Two device-test gates honored. Headline numbers: 0 critical, 24 high, 1 DQ-derived schema bump, DQ8 reviewed and confirmed already-satisfied.

| Round | Theme | Fixes | Commits |
|---|---|---|---|
| 1 | Deletions + config | H1 H2 H3 H19 H20 H23 H24 (+1 follow-up for Date.distantPast qualification) | 8 |
| 2 | Foundation hardening | H8 H9 H10 H11 H12 (H11 bundled with H8/H9 in `c1a73f7`) | 3 |
| 3 | Data integrity | H4 H5 H6 H15 H21 (+ hero polish slipped in mid-round) | 6 |
| 4 | UX + validation | H7 H13 H14 H16 H22 + DQ4 (DQ8 reviewed) | 6 |
| 5 | Performance | H17 H18 | 2 |

**Per-fix commit map:**

| ID | Title | Commit | Notes |
|---|---|---|---|
| H1 | delete PhotoEstimateLog model + remove from schema | `a878ab1` | // SCHEMA: |
| H2 | delete ClaudeService.swift | `daca14c` | photo flow cut |
| H3 | deprecate dead fields and stop filtering on them | `6a46658` | photoEstimated, .photo, NutritionEntry.deletedFromIndex, UserExercise.notes |
| H4 | HealthKitService.saveWeight async throws + banner | `f252e1c` | DQ3 confirmed: keep local on HK reject |
| H5 | WeightEntry.hkSampleUUID + UUID-first dedup | `ccf2758` | // SCHEMA:, device-test |
| H6 | ProfileService — explicit save on migration accept/decline | `6507003` | |
| H7 | AppleSignInIdentityService — non-trapping stubs | `c5cc47c` | |
| H8 + H9 + H11 | discriminate recovery + non-trapping fallback + bootstrap profile gate | `c1a73f7` | bundled (same `.task` block) |
| H10 | HealthKitService takes ModelContainer at construction | `b0c10d3` | side-channel removal |
| H12 | completeOnboarding transactional save | `b0baa1c` | |
| H13 | onboarding numeric guards + min-1-exercise gate | `47a8663` | DQ6 confirmed |
| H14 | manual workout input range guards | `c6671d7` | |
| H15 | BarcodeResultSheet save dedup — explicit error handling | `4920fc2` | |
| H16 | StrengthSession.inProgress + idempotent setupOnAppear | `73684e9` | // SCHEMA:, device-test |
| H17 | bound Strength @Query results to last 365 days | `f3092c7` | init-time predicate |
| H18 | hoist derived metrics inside body evaluations | `cbff27c` | NutritionMainView 4× → 1×, ActiveStrengthSessionView 3× → 1×, BodyView unit ternary precompute |
| H19 | Profile.encodeModules — symmetric encode-failure fallback | `a7c1bd1` | |
| H20 | DailyHealthMetrics.date default → .distantPast sentinel | `3601ed5` + `9ce257a` | // SCHEMA: + follow-up to qualify Date.distantPast for the @Model macro |
| H21 | DevIdentityService Keychain identity persistence | `b7d1f6a` | one-shot UD → Keychain migration in init; iCloud Keychain sync for reinstall survival |
| H22 | surface BarcodeScannerView setup failures | `f3f7bab` | |
| H23 | LSApplicationCategoryType (App Store submission) | `59e4c6b` | `public.app-category.healthcare-fitness` |
| H24 | SWIFT_TREAT_WARNINGS_AS_ERRORS = YES for Release | `5088ede` | |
| DQ4 | UserExercise.hiddenFromLibrary soft-hide pattern | `0952736` | // SCHEMA:, device-test |
| DQ8 | WeightEntry.notes display | (no commit) | reviewed — already surfaced by existing `WeightEntryDetailSheet` Notes section |

**Deferred-question answers** (provided 2026-05-15, applied during the rounds):

| DQ | Question | Answer | Applied where |
|---|---|---|---|
| DQ1 | MetricsEngine 75 kg fallback | Return Optional<DailyTargets>; suppress brain insights when no real weight | NOT applied yet (medium-priority carry-forward) |
| DQ2 | NutritionEntry.deletedFromIndex | Deprecate; stop querying. Hard-delete remains the swipe path | H3 |
| DQ3 | saveWeight failure UX | Keep local entry, non-blocking banner | H4 |
| DQ4 | UserExercise library delete | Soft-hide via `hiddenFromLibrary` | DQ4 commit `0952736` |
| DQ5 | Migration recovery retries | Single-shot wipe + hard-error screen, no three-strikes | H8 |
| DQ6 | Onboarding min-1 exercise | Required when Fitness module enabled | H13 |
| DQ7 | Profile.calorieAdjustmentKcal / proteinTargetG | Real Phase 7 features — left untouched | (none — Phase 7 work) |
| DQ8 | WeightEntry.notes | Surfaced in WeightEntryDetailSheet (already was) | (no commit) |
| DQ9 | Swift 5 → Swift 6 build mode | Defer until after Phase 7 | (deferred) |
| DQ10 | HK observer stop on toggle-off | Stop importing only; preserve previously-imported rows | Phase 7 carry-forward |

---

## Phase 7 — Settings (shipped)

Phase 7 closed before the post-Phase-7 follow-ups above. What landed:

- Workout import on/off toggle (HK observer-stop API on `HealthKitService` — M8 / DQ10).
- Module enable/disable toggles.
- Profile editor (name, age, height, sex, activity, goal).
- Signed calorie adjustment slider (deficit/surplus, −1000…+1000 in 50-kcal steps) + protein target editor (DQ7).
- Eat-back-workout-calories toggle.
- Manual logging toggles (hide the Log button when off).
- Re-grant Apple Health authorization (`HealthStatusSheet`).
- Notifications section — workout + weight, with async iOS-permission gating.
- AI estimation section — Anthropic key (Keychain) + monthly budget slider + month-to-date spend readout (red when over budget).
- "Reset all data" affordance — wipes WeightEntry / WorkoutSession / StrengthSession / NutritionEntry / DailyHealthMetrics / FoodProduct rows; preserves Profile + UserExercise library.
- Sign out / delete account (Apple-Sign-In bodies fill in post enrollment).
- Demo section — toggle + confirmation + clean `exit(0)` for the physically-separate demo store.
- About row (version + build date + Swiss footer).

---

## Carry-forward + long-term backlog

Both moved to `BACKLOG.md` (single source for everything not yet built).

Shipped from prior backlog: **AI photo-to-macros** (revived via the AI macro estimator), **HR series on every workout type** (live fetch via `fetchHRSeries`), **Sleep tile** on Body ("Time asleep" replaced the static Ideal range tile).
