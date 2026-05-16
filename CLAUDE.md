# CLAUDE.md — Index v2 working agreement

Read this before changing anything. The product overview lives in `CONTEXT.md`. The phase-by-phase progress log + the consolidated audit punch list live in `PROGRESS.md`.

---

## Build commands

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project /Users/yannis/Index/Index/Index.xcodeproj \
  -target Index \
  -sdk iphonesimulator26.5 \
  -configuration Debug build
```

The Xcode-26.4.1 SDK is `iphonesimulator26.5` even though the runtime installed is iOS 26.4 — `xcodebuild -showsdks` confirms. Using `-target` (not `-scheme`) plus explicit `-sdk` bypasses destination resolution, which otherwise gets confused when a real iPhone is plugged in with an unbuilt iOS version (e.g. iOS 26.5 device, 26.4 host SDK).

Build clean **before every commit**. If the build breaks, fix it before moving on. Don't accumulate broken builds.

To actually launch the app on a simulator, boot one and use a `-destination 'id=<UDID>'` form instead.

## Project layout

```
Index/
├── CLAUDE.md, CONTEXT.md, PROGRESS.md, README.md   — root docs (this directory)
├── Index/                                          — Xcode project + sources
│   ├── Index.xcodeproj/
│   └── Index/
│       ├── IndexApp.swift                          — @main, ModelContainer setup, self-healing recovery
│       ├── ContentView.swift                       — root router (orphan / active profile / onboarding)
│       ├── Index.entitlements                      — HealthKit + background delivery
│       ├── Assets.xcassets/
│       ├── Models/                                 — 10 @Model classes + IndexSchema list
│       ├── Services/                               — HK bridge, Profile, Identity, Brain, Metrics, OFF, Format helpers
│       └── Views/
│           ├── Body/                               — BodyView + log / detail / history sheets
│           ├── Fitness/                            — FitnessMainView + per-activity log sheets + WorkoutDetailView
│           ├── Strength/                           — Active session, library, picker, detail
│           ├── Nutrition/                          — NutritionMainView + scanner + result sheet + manual + detail
│           └── Onboarding/                         — 8-step OnboardingView
└── .git/
```

Xcode is configured with `PBXFileSystemSynchronizedRootGroup` — new `.swift` files in `Index/Index/**/` are auto-discovered. No manual `project.pbxproj` edits needed for sources.

## Capabilities — what's wired, what's pending

| Capability | Status | Notes |
|---|---|---|
| HealthKit | ✅ entitlement + usage strings present | full read of 14 types + `bodyMass` write per the v0 pattern |
| HealthKit background delivery | ✅ entitlement present | `com.apple.developer.healthkit.background-delivery` |
| Camera (barcode) | ✅ wired Phase 6 | `INFOPLIST_KEY_NSCameraUsageDescription` set; AVFoundation scanner ships EAN-8/13, UPC-A/E, ITF-14, Code 128 |
| Sign in with Apple | ⏳ pending paid enrollment | JWT signing requires paid Developer Program; do NOT add `com.apple.developer.applesignin` until enrollment completes. `AppleSignInIdentityService` stub exists with **non-trapping** stubs (audit H7) — fill bodies and flip `AppDependencies.identity` as the swap |
| iCloud / CloudKit | ⏳ pending paid enrollment | models are CloudKit-shape compliant (re-verified by audit); flipping the capability is a single `ModelConfiguration` change to add `cloudKitDatabase: .private(...)` |
| `LSApplicationCategoryType` | ✅ set 2026-05-15 | `INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.healthcare-fitness"` for App Store submission |

Until paid enrollment lands, use `DevIdentityService` — UUID stored in **Keychain** (audit H21) with `kSecAttrAccessibleAfterFirstUnlock` + `kSecAttrSynchronizable` so identity persists across uninstall + reinstall when the user has iCloud Keychain on. The `IdentityService` protocol lets the rest of the app stay identical when we swap to real Sign in with Apple.

## CloudKit-shape rules — non-negotiable

Every `@Model` class in `Models/` must satisfy:

1. **Every stored property has a default** (or is Swift-optional). Never `var foo: Double` without `= 0`.
2. **All to-one relationships are optional** (`var session: StrengthSession?`). The parent side is `[Child]?` matching the spec.
3. **No `@Attribute(.unique)` anywhere.** CloudKit doesn't enforce uniqueness; use logical keys + dedup predicates.
4. **No required cross-model relationships at insert time.** Set the parent after both sides exist.
5. **Cascade delete via `@Relationship(deleteRule: .cascade, inverse: \Child.parent)`** — never `.nullify` for parent-child.

If a new model can't satisfy these, the problem is the model design, not the rule.

## Patterns to keep using

- **`has-foo` boolean companion** for every nullable numeric (`hasKcal`, `hasMaxHeartRate`, `hasLeanMass`). Never Swift-optional numerics; the Bool companion queries cleanly through SwiftData `#Predicate`.
- **`deletedFromIndex` soft-delete** on every model that mirrors HealthKit data. Filter `@Query` results with `#Predicate { !$0.deletedFromIndex }`. HK dedup predicates **do NOT** filter on this flag — that's what makes swipe-delete-as-tombstone work. The flag is meaningless on non-mirrored models (e.g. NutritionEntry never touches HK; the swipe there is hard-delete; the field there is `// DEPRECATED:` per audit H3).
- **Soft-link by string id** for cross-model references that must survive a deliberate hard-delete on the linked side: `WorkoutSession.strengthSessionId` → `StrengthSession.id`, `ExercisePerformance.userExerciseId` → `UserExercise.id`. Read sites must guard for the dangling case (render "Unknown exercise" or similar).
- **Soft-hide for catalog-keyed library items.** When a UserExercise (id == catalog id) is "removed" by the user, set `hiddenFromLibrary = true` rather than deleting. Library/picker `@Query` filters on `!hiddenFromLibrary`; old session history's `userExerciseId` soft-link still resolves the name. Re-adding the same catalog id from `AddExerciseSheet` un-hides the row instead of inserting a duplicate (catalog ids are deterministic; duplicate inserts would break soft-link resolution). Pattern from audit DQ4.
- **UUID-first dedup for HK-mirrored writes.** Two-tier dedup, in order:
  1. Primary — `hk*UUID` field on the SwiftData model matches the HK sample's `uuid.uuidString`. Used by `WorkoutSession.hkWorkoutUUID` (audit baseline) and `WeightEntry.hkSampleUUID` (audit H5).
  2. Fallback — ±N-min date window for manual rows (no HK UUID) and pre-UUID-field legacy rows. ±2 min for workouts, ±5 min for weight entries.
  
  Neither tier filters on `deletedFromIndex` — that's still the swipe-as-tombstone contract that prevents resurrection.
- **Apple Health is the source of truth.** Index writes only `bodyMass` (manual weight mirrors out, surfaced as `async throws` so failures bubble up — audit H4). Read-mostly, write-rarely. The HK boundary is one file (`HealthKitService.swift`); HK types do NOT leak past it.
- **Anchor gating on HK observer.** When the import toggle is off, do NOT advance the HK anchor — otherwise workouts delivered during the off-window are stranded forever.
- **Explicit boolean over date-equality heuristic** for in-progress / completed state. `StrengthSession.inProgress` (audit H16) replaces the previous `endDate <= date` check, which lied about state in the same-tick edge case (create + immediate-end on a fast CPU returned `true` after end).
- **Pure-static services for math** (`MetricsEngine`, `BrainService`). No state, no fetching — callers pass `@Query` data in.
- **`@Query` directly in views.** No ViewModels.
- **Sheet draft pattern.** `@State` text fields buffer the *display* of a model's values; explicit `model.field = parsed` on Save commits. Cancel rolls back implicitly because nothing was mutated. Used by every Log* and *DetailSheet.
- **`FieldValidation` value type** (in `Views/Body/LogWeightSheet.swift`) for any numeric form input — three-state (parsed / parsedInRange / error). Reused by 7+ sheets after audit H13/H14. Comma-as-decimal locale handled.
- **`SafeFormat` defensive formatters** for any `Int(Double)` display path. Returns `"—"` for non-finite or magnitude > threshold. Floor against the 2026-05-14 incident (a `WeightEntry.weightKg` ~5×10³⁸ trapped BodyView's formatter on launch).
- **Profile abstraction from day one.** There is no hard-coded "Yannis." Every screen reads the active profile via `ProfileService`.
- **Identity behind a protocol.** `IdentityService` swap-seam in `AppDependencies.identity` is the only line that changes when paid enrollment lands. `DevIdentityService` stores in Keychain (audit H21); `AppleSignInIdentityService` stubs are non-trapping (audit H7) so a partial swap doesn't crash.
- **Migrations are lightweight-only.** See "Schema evolution rules" below — if a change can't be made via lightweight migration, redesign the change.

## Schema evolution rules

The first attempt at versioned migrations (V1 / V2 / V3 + `IndexMigrationPlan`) generated **"Duplicate version checksums detected"** because each VersionedSchema's `.models` returned the same compile-time Swift class types. The proper SwiftData per-version snapshot pattern (nested `@Model` declarations inside each VersionedSchema enum) wasn't applied. For purely additive changes the simpler approach is to drop VersionedSchema entirely and rely on SwiftData's automatic lightweight migration, which is what `IndexSchema` now does.

These rules are non-negotiable. Violating them invalidates every prior schema evolution decision.

- **Only additive changes between versions.** Add fields, add models. Anything else (rename / delete / type change) is a redesign, not a migration.
- **Never delete a field.** Mark unused fields with a `// DEPRECATED:` comment explaining when use stopped and why. The column stays in the model definition forever.
- **Never rename a field.** Add a new field with the new name, leave the old one in place (deprecated), and migrate readers over time.
- **Never change a field's type.** Same pattern as rename — add a new field of the new type, deprecate the old one.
- **Every new field must have a default value or be Swift-optional.** Required for SwiftData's lightweight migration to populate stored rows automatically. Already a CloudKit-shape requirement.
- **No VersionedSchema declarations for additive changes.** SwiftData lightweight migration handles them automatically when you give the ModelContainer a single `Schema(IndexSchema.models)`.
- **If a non-additive change is ever needed**, that's the moment to introduce proper VersionedSchema snapshots with nested `@Model` types per version. Don't reach for them prophylactically.
- **Every schema change requires a clean build + device test before committing.** Not simulator-only. The "Duplicate version checksums" incident reproduced on device but not on a fresh simulator install — schema evolution has to be verified against an existing store. Audit H5 / H16 / DQ4 (and any future schema bump) follow this gate.
- **Every schema change commit must include a `// SCHEMA:` marker line in the message body** so the schema-related commits are findable via `git log --grep`.
- **The ModelContainer init in `IndexApp` is wrapped in a discriminated do/catch** (audit H8 + H9). Only `SwiftDataError.loadIssueModelContainer` triggers wipe + retry; any other error (disk full, file-permission, unknown future error type) falls through to a non-trapping in-memory fallback so the user reaches `ContentView`'s hard-error screen instead of crashing. Single-shot wipe — no three-strikes retry. Self-healing where it makes sense; honest failure where it doesn't.

## Commit conventions

Every commit message follows:

```
Phase N step M: short imperative description

Body explaining what changed and why (not how — diff shows that).
The user reads these to confirm progress; keep them concrete.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

Commit after every numbered step in the takeover doc. Don't batch multiple steps. If a step turns out to be larger than expected, split it.

## Code style

- **No emoji** in code or commit messages. The Index aesthetic is editorial-brutalist; emojis break the voice.
- **Default to writing no comments.** Identifiers carry the meaning. Comment only when the *why* is non-obvious — a hidden constraint, a subtle invariant, a workaround.
- **`// DECISION:`** marks a judgment call not covered by the takeover doc. Future readers should be able to understand and revisit.
- **`// FUTURE:`** marks something to revisit later but not block v1.
- **No "while we're at it" additions.** Don't add fields, refactor neighboring code, or build features not on the build-order list.
- **Don't build empty states later.** Build them as each screen lands.
- **`@Query` directly in views.** No ViewModels.

## Things explicitly NOT in v1

Do not implement these. They were considered and cut.

- TSS / FTP / normalized power (pro-cyclist metrics)
- Sleep as a top-level tab (Sleep is a tile on Body if at all)
- Finance models entirely
- Structured cycling workout templates (HIIT Sprints, Tempo, Recovery)
- Strength workout templates (no Push Day / Pull Day; freestyle only)
- Custom exercise creation (the 10-exercise starter catalog is the whole catalog)
- Metric explanation overlays (long-press to explain BMI etc.)
- Notification system (zero notifications in v1)
- Dashboard tab / "Today's Read" prose
- WorkoutDetailData lazy-fetch (v2 persists HR series + zone breakdown to SwiftData)
- **Photo-to-macros.** `Services/ClaudeService.swift` and `Models/PhotoEstimateLog.swift` were deleted in audit H1 + H2 (2026-05-15). `NutritionEntry.photoEstimated` and `NutritionSource.photo` remain in the model marked `// DEPRECATED:` per the schema rules ("Never delete a field"). Reviving the feature post-v1 means re-adding the service + model as additive changes, not un-deprecating the existing slots.

(Frequent foods on Nutrition main is now shipped as a behavior-based chip row built from last-30-day NutritionEntry frequency — see commit `3d88285`.)

## Audit-derived defensive coding rules

Added 2026-05-15 after the line-by-line audit, then enforced through audit Phase 5 (24 H-tier fixes + DQ4 / DQ8 — all on `origin/main` between commits `daca14c` and `cbff27c`). These are non-negotiable patterns going forward.

- **No silent error swallowing on write paths.** `try?` is acceptable for *reads* where an empty result is the right fallback (the SwiftData `FetchDescriptor` calls in `HealthKitService` and `ProfileService` qualify). It is NOT acceptable for writes — `context.save()`, HK `store.save(_:)`, file removal during recovery — those need a real `do/catch` with a user-visible failure mode or an explicit log. Audit references: H4 (HK saveWeight), H6 (ProfileService migration), H12 (onboarding completion), H15 (BarcodeResultSheet dedup).
- **Insert + save is one operation.** Any path that inserts a model and depends on the data being durable across an app kill must explicitly call `try modelContext.save()` and handle the throw. SwiftData autosave is "next runloop tick when dirty" — fine for incidental edits, not safe for onboarding completion or migration accept/decline.
- **No `fatalError` reachable in production.** Three documented exceptions remain: `init?(coder:)` boilerplate in `BarcodeScannerView` (unreachable in SwiftUI presentation); the `IndexApp.makeFallbackContainer` last-resort trap (only fires if even an in-memory schema init fails — fundamentally broken Schema, nothing to fall back to); the `AppleSignInIdentityService` stubs are now non-trapping (audit H7). Any new `fatalError` needs a written justification.
- **HK observers must be stoppable.** Every new `HKObserverQuery` / `HKAnchoredObjectQuery` needs to be retained on the service so a future Settings toggle-off can call `store.stop(query:)`. **Still pending — Phase 7 ships the toggle UI together with the stop API.** Per DQ10: stopping HK delivery does NOT delete previously-imported HK rows.
- **Pre-emptive numeric range guards on form inputs.** Any `TextField` that binds to a `Double`/`Int` used by `MetricsEngine` or persisted to a model needs a `FieldValidation` range check before save. `0` is rarely a valid input for height, target weight, or duration; accept-and-coerce-to-0 silently corrupts downstream math. See audit H13 (onboarding) and H14 (manual workout sheets) for the pattern in use.
- **Cache derived metrics inside `body`, don't recompute per render.** Brain insights and `MetricsEngine.dailyTargets` are pure but not cheap. Compute once in a body-scoped `let derived = makeDerived()` at the top of the view's `body` and thread through the subsections that need it; avoid 4× duplicated work across computed-property accessor calls. The `NutritionMainView.heroRow(targets:)` / `insightSection(targets:)` / `workoutCaption(targets:)` parameter pattern (audit H18) is the canonical example.
- **Bound `@Query` results when the underlying table grows unbounded.** StrengthSession history accumulates forever; an unbounded `@Query` transitively pulls every `SetEntry` ever logged. Construct the `@Query` in a view's `init(...)` with a date-cutoff predicate so the cutoff refreshes per presentation. See `ActiveStrengthSessionView.init` and `ExerciseDetailView.init` for the pattern (audit H17 — both bound to last 365 days).
- **Don't use `print(...)`.** Use `os.Logger`. Existing `print` sites are a known cleanup item (Phase 8 polish).
- **No `URL(string: ...)!` for network endpoints.** Any string-built URL goes through `URLComponents` or a `guard let url else { throw }` — the force-unwrap survives a refactor that *does* introduce a parsing failure mode.
- **Side-channel mutation of services from views is forbidden.** Services receive their dependencies (`ModelContainer`, identity provider) at construction in `IndexApp`. `HealthKitService` was the one historical violation (`modelContext` set from `ContentView.task`); fixed in audit H10 — service now takes `ModelContainer` at construction via the `IndexApp.sharedContainer` static. Same pattern for any future service.

## Pattern recommendations going forward

Direct outcomes of the audit findings — adopt these for new work:

- **Sheet sequencing without `asyncAfter` magic.** When one sheet's dismiss must trigger another's presentation, use `.sheet(isPresented:onDismiss:)` chained — NOT `DispatchQueue.main.asyncAfter(deadline: .now() + 0.4)`. The 0.4s constant is brittle on slower devices and breaks if iOS animation curves change. (Existing offenders in `FitnessMainView.handleActivityChoice` and `NutritionMainView.routeAfterScanner` are Phase 8 polish.)
- **Centralize `WeightSource.caption` (and similar) on the enum**, not as a duplicated helper inside three separate view files. New display-string mappings on enums go on the enum. (Phase 8 polish for the existing triplication.)
- **Hoist formatter instances to `static let`.** `RelativeDateTimeFormatter`, `DateFormatter`, `UINotificationFeedbackGenerator` — instantiating per call wastes cycles and isn't measurably more readable.
- **Don't trust `UserDefaults` to survive uninstall.** Anything identity-bearing (userId, API keys if ever needed) goes in Keychain. UserDefaults is for operational state (sync anchors, toggles, one-shot flags). The audit migrated `DevIdentityService` to Keychain (H21) including a one-shot UD → Keychain copy in `init` for existing installs.
- **Discriminate catch blocks on error type** when "wipe and retry" is the recovery. `IndexApp`'s migration recovery now pattern-matches on `SwiftDataError.loadIssueModelContainer` specifically (audit H9); other errors route to the non-trapping in-memory fallback so user data isn't wiped on a transient I/O issue.
- **Typography is centralized in `Views/Theme/IndexTypography.swift`.** SF Pro across the app, with `.monospacedDigit()` on every numerical helper for tabular alignment — Geist Mono was tried and rolled back because its full-width `.` glyph rendered decimals as "87 . 3". Tokens are point-size constants (`IndexFont.hero` / `tileValue` / `heroCaption` / `sectionCap` / `rowTitle` / `rowValue` / `rowSecondary` / `tileLabel` / `tileUnit` / `heroUnit`) shared across all modules so Body / Fitness / Nutrition heroes render at the same size and weight. New screens MUST use these helpers — raw `.font(.system(size:))` / `.font(.title*)` / `.font(.caption.smallCaps())` on numerical or section-caption sites are forbidden so the three modules stay typographically aligned.
- **AI features go through `ClaudeService`.** The Anthropic API key lives in iOS Keychain only (`index.ai.anthropicAPIKey`, `kSecAttrAccessibleAfterFirstUnlock` + iCloud sync) — NEVER compiled into the binary, NEVER committed to git, NEVER written into source files or docs. Every network call to Anthropic MUST be cost-gated through `claudeService.isWithinBudget(in:)` before the request, and MUST record the result via `claudeService.recordUsage(inputTokens:outputTokens:in:)` after the response so the monthly cap stays honest. Cost constants are Haiku 4.5 (claude-haiku-4-5-20251001) per-million-token rates; re-verify against anthropic.com/pricing if month-to-date totals look wrong. The meal-photo vision call lives in `ClaudeService.estimateMacros(from:in:)` — images are downscaled to 1024px longest edge + JPEG q=0.7 before send so input-token cost stays low; usage is recorded BEFORE the JSON-parse step so a parse failure still bills correctly.

---

## Audit Phase 5 milestone — 2026-05-15

Foundation hardening shipped. 24 H-tier fixes + 1 DQ-derived schema bump landed across 5 rounds, all on `origin/main` between commits `daca14c` and `cbff27c`. Headline outcomes:

- **Dead code gone:** `Services/ClaudeService.swift` + `Models/PhotoEstimateLog.swift` deleted; four dead fields marked `// DEPRECATED:` (`NutritionEntry.photoEstimated`, `NutritionSource.photo`, `NutritionEntry.deletedFromIndex`, `UserExercise.notes`).
- **Three additive schema bumps shipped (// SCHEMA:):** `WeightEntry.hkSampleUUID` (H5), `StrengthSession.inProgress` (H16), `UserExercise.hiddenFromLibrary` (DQ4). Plus `DailyHealthMetrics.date` default → `Date.distantPast` sentinel (H20).
- **Identity moved to Keychain** (H21) with iCloud Keychain sync for reinstall survival; `AppleSignIn` stubs no longer trap (H7).
- **`IndexApp` recovery rebuilt** with discriminated catch + non-trapping fallback + ContentView hard-error screen (H8 + H9 + H11 + H12).
- **HK boundary tightened**: constructor injection of `ModelContainer` (H10), UUID-first dedup on weight imports (H5), `saveWeight → async throws` with non-blocking failure banner (H4).
- **UX guards added** in onboarding (H13 — DQ6 min-1 exercise) and manual workout sheets (H14).
- **Performance**: bounded Strength `@Query` (H17), hoisted derived-metrics in main views (H18).
- **Project config**: `LSApplicationCategoryType` set (H23); `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` for Release (H24).

Build clean (Debug + Release, zero warnings) at the close of every round. Two device-test gates honored (Round 3 H5 + H21; Round 4 H16 + DQ4). See `PROGRESS.md` for the per-round commit table + the carry-forward list of Medium / Low items deferred to Phase 8 polish.

## When to ask Yannis vs. decide

**Ask** when: personal preference, product-fundamental, money.
**Decide and leave a `// DECISION:` comment** when: SwiftUI modifiers, struct-vs-class, naming, async/await vs callbacks, anything code-style.

Yannis is not a developer. He's a vibe coder who understands what the app should do but can't reasonably evaluate a code-style question. Don't block on him for technical judgment.
