# Index

A private iOS app that interprets your body, fitness, and nutrition data instead of just displaying it. iOS 26.4+. SwiftUI, SwiftData, HealthKit. Pre-1.0; no public release.

## What it does

Three modules — **Body**, **Fitness**, **Nutrition** — sit on top of Apple's stack. HealthKit feeds in workouts (anchored observer from Apple Watch), weight + body composition (RENPHO via HK), daily vitals (HRV / VO2 / resting HR), and last-night sleep duration. Index reads them, writes back only `bodyMass`, and runs a pure-function **Brain** that produces templated insight sentences per module ("HRV down 12% — consider lighter training", "Strong week — 4 sessions logged").

Logging is fast and gym-first: the LOG button is a primary action when manual entry is enabled, hidden when automated sources are doing the work. Weights, workouts, meals, and strength sets all land in one tap from each module's main screen.

Nutrition has a single **Camera** screen that handles two paths from the same live preview:

- **Barcode** — auto-fires on stable detection. When the same barcode value is in frame continuously for ~0.6 s the OpenFoodFacts lookup runs automatically and routes to the result sheet. A short stability window prevents a barcode sweeping past the edge of frame from hijacking a meal-photo capture. Free, no API cost.
- **AI meal-photo macro estimate** — shutter button (or photo-library picker) sends a downscaled JPEG to Claude Haiku 4.5 via the Anthropic API. The response carries an `isFood` self-check, name, kcal + macros, and a confidence level. Successful estimates open the editable manual-entry sheet pre-filled. Every call is cost-gated through a hard monthly budget cap stored in `AIUsageRecord` rows; the API key lives only in iOS Keychain.

A **Food history** screen pushed from Nutrition shows every meal ever logged, grouped by meal type. Tapping any past entry re-logs it to today through the same editable sheet — fast-logging shortcut for the things you eat repeatedly.

Strength training is freestyle (no templates) over a 10-item starter catalog. Local notifications fire when Apple Health imports a new workout or weigh-in (off by default; opt-in per type).

## Status

Phases 1–7 complete + post-Phase-7 features:

- **Foundation, services, onboarding, Body, Fitness + Strength, Nutrition** all wired end-to-end.
- **Phase 7 Settings** complete — profile editing, calorie adjustment slider (signed deficit/surplus), protein target, module toggles, manual-logging toggles, eat-back workout calories, Apple Health connection panel, notifications (workout + weight), AI estimator (API key + monthly budget + month-to-date spend), reset / sign-out / delete-account.
- **AI macro estimator** — Anthropic Haiku 4.5 vision call, Keychain-stored key, `AIUsageRecord` per-call usage tracking, monthly budget cap.
- **Camera** — meal capture is the default; barcode auto-fires on stable detection (no chip, no tap).
- **Heart-rate chart on every workout type** — Squash, Cycling, Running, Swimming, Other all render the same chart via a generic live HealthKit fetch (`HealthKitService.fetchHRSeries`).
- **Body composition + delta indicators** — every Body tile with a clear direction-of-good (body fat, lean mass, HRV, VO2, resting HR) shows a green/red arrow + change vs. the previous measurement. "Time asleep" tile reads last night's sleep duration from HealthKit `sleepAnalysis`.
- **Food history screen** — push-from-Nutrition view of every meal ever logged, grouped by meal type, tap-to-re-log via the existing editable sheet.
- **Audit Phase 5** complete — 24 H-tier fixes + 1 DQ-derived schema bump across 5 rounds; build clean at every round close.
- **Centralized theme** — `IndexPalette` for colors, `IndexFont` for SF Pro typography with `.monospacedDigit()` for tabular alignment. `IndexTabScaffold` paints the alabaster surface across all three tabs.
- **Per-module accent tinting** — Body blue, Fitness coral, Nutrition teal; tab tint switches with the active tab.
- **Layout hardening** — auto-ranged weight chart, safe-area-respecting nav bars (explicit opaque toolbar background under iOS 26 Liquid Glass), clip-proof tiles (numeral scales, unit pinned), workout-detail card grid uniform across types, partial Dynamic Type via semantic font tokens.
- **Calorie target is linear** — `caloriesBase = TDEE + adjustment`. A prior `max(1200, BMR * 1.1)` soft-clamp that silently overrode user deficits was removed; safety lives at the slider boundary (±1000 kcal in 50-kcal steps).
- **Demo data mode** — Settings toggle that switches Index to a physically separate SwiftData store (`Index-demo.store`) pre-populated with a believable rolling year of data. Real and demo stores can never mix — only one is opened per launch. AI estimates are off and `AIUsageRecord` is untouched in demo, so the cost ledger stays honest.

Not yet shipped: CloudKit private database sync (model shape is ready; flipping `cloudKitDatabase:` is a one-line edit when Developer Program enrollment lands), real Sign in with Apple (`AppleSignInIdentityService` exists as non-trapping stubs), imperial display units (helpers exist; no view branches on `Profile.units`), HR-series persistence on import (the series is fetched **live** from HealthKit when a workout-detail screen opens — see `HealthKitService.fetchHRSeries(forWorkoutUUID:)` — so the chart renders for every workout type with HR data; persistence would only be needed if we wanted the chart available offline or without HK), custom launch screen.

## Build

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Index/Index.xcodeproj \
  -target Index \
  -sdk iphonesimulator26.5 \
  -configuration Debug build
```

The Xcode-26.4.1 SDK is `iphonesimulator26.5` even though the runtime installed is iOS 26.4 — using `-target` (not `-scheme`) plus explicit `-sdk` bypasses destination resolution.

## Project layout

```
Index/
├── README.md, CONTEXT.md, CLAUDE.md, PROGRESS.md, BACKLOG.md   — root docs
└── Index/                                          — Xcode project + sources
    ├── Index.xcodeproj/
    └── Index/
        ├── IndexApp.swift                          — @main, ModelContainer + service wiring
        ├── ContentView.swift                       — root router (hard-error / orphan / onboarding / tabs)
        ├── Index.entitlements                      — HealthKit + background delivery
        ├── Assets.xcassets/
        ├── Models/                                 — 11 @Model classes + IndexSchema list
        ├── Services/                               — HK bridge, Profile, Identity, Brain, Metrics,
        │                                            Notifications, OFF, Keychain, Claude (AI), SafeFormat,
        │                                            DemoMode, DemoDataService, DemoHRSeriesGenerator
        └── Views/
            ├── Body/                               — BodyView + log / detail / history
            ├── Fitness/                            — FitnessMainView + log sheets + WorkoutDetailView + SwimAutoSets
            ├── Strength/                           — Active session, library, picker, detail, RestTimer
            ├── Nutrition/                          — NutritionMainView + camera (barcode + AI) + result + manual + detail + FoodHistoryView
            ├── Settings/                           — SettingsView + 10 edit sheets + HealthStatusSheet
            ├── Onboarding/                         — 8-step OnboardingView
            └── Theme/                              — IndexPalette + IndexTypography + DemoBadge
```

Xcode 16+ `PBXFileSystemSynchronizedRootGroup` is on — new `.swift` files in `Index/Index/**/` auto-discover. No manual `project.pbxproj` edits needed for sources.

## Docs

| File | Purpose |
|---|---|
| `README.md` | This file — what the app is, how to build, where to look. |
| `CONTEXT.md` | Comprehensive architecture map — every module, every service, every model, every view, plus the patterns binding them together. Start here for a deep read. |
| `CLAUDE.md` | Working agreement — build commands, schema evolution rules, non-negotiable patterns, audit-derived defensive coding rules, code style, what's explicitly NOT in v1. |
| `PROGRESS.md` | Phase-by-phase log of what shipped, audit punch list, deferred-question answers. |
| `BACKLOG.md` | The single source for open bugs, pre-release requirements, and deferred work. |
