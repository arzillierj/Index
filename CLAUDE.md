# CLAUDE.md — Index v2 working agreement

Read this before changing anything. The product overview lives in `CONTEXT.md`.

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
├── CLAUDE.md, CONTEXT.md, README.md      — root docs (this directory)
├── Index/                                — Xcode project + sources
│   ├── Index.xcodeproj/
│   └── Index/
│       ├── IndexApp.swift                — @main, ModelContainer setup
│       ├── ContentView.swift             — placeholder until Phase 4
│       ├── Index.entitlements            — HealthKit + background delivery
│       ├── Assets.xcassets/
│       └── Models/                       — every @Model class lives here
└── .git/
```

Xcode is configured with `PBXFileSystemSynchronizedRootGroup` — new `.swift` files in `Index/Index/**/` are auto-discovered. No manual `project.pbxproj` edits needed for sources.

## Capabilities — what's wired, what's pending

| Capability | Status | Notes |
|---|---|---|
| HealthKit | ✅ entitlement + usage strings present | full read + bodyMass write per the v0 pattern |
| HealthKit background delivery | ✅ entitlement present | `com.apple.developer.healthkit.background-delivery` |
| Sign in with Apple | ⏳ pending paid enrollment | JWT signing requires paid Developer Program; do NOT add `com.apple.developer.applesignin` until enrollment completes |
| iCloud / CloudKit | ⏳ pending paid enrollment | models are CloudKit-shaped from day one; flipping the capability is a single `ModelConfiguration` change |
| Camera (barcode) | ⏸ Phase 6 | `NSCameraUsageDescription` will be added then |

Until paid enrollment lands, use `DevIdentityService` (UUID in UserDefaults) instead of real Sign in with Apple. The `IdentityService` protocol lets the rest of the app stay identical when we swap.

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
- **`deletedFromIndex` soft-delete** on every model that mirrors HealthKit data. Filter `@Query` results with `#Predicate { !$0.deletedFromIndex }`. HK dedup predicates **do NOT** filter on this flag — that's what makes swipe-delete-as-tombstone work.
- **Apple Health is the source of truth.** Index writes only `bodyMass` (manual weight mirrors out). Read-mostly, write-rarely.
- **Anchor gating on HK observer.** When the import toggle is off, do NOT advance the HK anchor — otherwise workouts delivered during the off-window are stranded forever.
- **±5-minute match window** for reconciling Apple Watch workouts with manual logs.
- **Pure-static services for math** (`BodyCalculations`, `MetricsEngine`, eventual `BrainService`). No state, no fetching — callers pass `@Query` data in.
- **Profile abstraction from day one.** There is no hard-coded "Yannis." Every screen reads the active profile via `ProfileService`.
- **Migrations are lightweight-only.** Every schema change is a new `VersionedSchema` + a `.lightweight(from:to:)` stage in `IndexMigrationPlan`. If a change needs a custom migration, redesign the change.

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
- Frequently-eaten chips on Nutrition main
- Metric explanation overlays (long-press to explain BMI etc.)
- Notification system (zero notifications in v1)
- Dashboard tab / "Today's Read" prose
- WorkoutDetailData lazy-fetch (v2 persists HR series + zone breakdown to SwiftData)

## When to ask Yannis vs. decide

**Ask** when: personal preference, product-fundamental, money.
**Decide and leave a `// DECISION:` comment** when: SwiftUI modifiers, struct-vs-class, naming, async/await vs callbacks, anything code-style.

Yannis is not a developer. He's a vibe coder who understands what the app should do but can't reasonably evaluate a code-style question. Don't block on him for technical judgment.
