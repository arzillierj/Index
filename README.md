# Index

A private iOS app that interprets your body, fitness, and nutrition data instead of just displaying it. iOS 26.4+. SwiftUI, SwiftData, HealthKit. Pre-1.0; no public release.

## What it does

Three modules — **Body**, **Fitness**, **Nutrition** — sit on top of Apple's stack. HealthKit feeds in workouts (anchored observer from Apple Watch), weight + body composition (RENPHO via HK), and daily vitals (HRV / VO2 / resting HR). Index reads them, writes back only `bodyMass`, and runs a pure-function **Brain** that returns one templated insight sentence per module ("HRV down 12% — consider lighter training", "Strong week — 4 sessions logged", "+314 kcal target adjustment from today's swim").

Logging is fast and gym-first: the LOG button is a primary action when manual entry is enabled, hidden when automated sources are doing the work. Weights, workouts, meals, and strength sets all land in one tap from each module's main screen.

The barcode scanner reads EAN-8 / EAN-13 / UPC-A / UPC-E / ITF-14 / Code 128 against Open Food Facts with a 90-day local product cache. Strength training is freestyle (no templates) over a 10-item starter catalog. Notifications fire when Apple Health imports a new workout or weigh-in (off by default; opt-in per type).

## Status

The app has shipped through Phase 7 and the audit:

- **Foundation, services, onboarding, Body, Fitness + Strength, Nutrition** all wired end-to-end.
- **Phase 7 Settings** complete — profile editing, calorie adjustment slider (signed deficit/surplus), protein target, module toggles, manual-logging toggles, eat-back workout calories, Apple Health connection panel, notifications (workout + weight), reset / sign-out / delete-account.
- **Audit Phase 5** complete — 24 H-tier fixes + DQ-derived schema bumps across 5 rounds; build clean (Debug + Release, zero warnings) at every round close.
- **Centralized theme** — `IndexPalette` for colors, `IndexFont` for typography (SF Pro + `monospacedDigit`).
- **Per-module accent tinting** — Body blue, Fitness coral, Nutrition teal; tab tint switches with the active tab.

Not yet shipped: CloudKit private database sync (model shape is ready; flipping `cloudKitDatabase:` is a one-line edit when Developer Program enrollment lands), real Sign in with Apple (`AppleSignInIdentityService` exists as non-trapping stubs), imperial units (helpers exist; no view branches on `Profile.units`), HR-series persistence on import, custom launch screen + icon.

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
├── README.md, CONTEXT.md, CLAUDE.md, PROGRESS.md   — root docs
└── Index/                                          — Xcode project + sources
    ├── Index.xcodeproj/
    └── Index/
        ├── IndexApp.swift                          — @main, ModelContainer + service wiring
        ├── ContentView.swift                       — root router (hard-error / orphan / onboarding / tabs)
        ├── Index.entitlements                      — HealthKit + background delivery
        ├── Assets.xcassets/
        ├── Models/                                 — 10 @Model classes + IndexSchema list
        ├── Services/                               — HK bridge, Profile, Identity, Brain, Metrics, Notifications, OFF
        └── Views/
            ├── Body/                               — BodyView + log / detail / history
            ├── Fitness/                            — FitnessMainView + log sheets + WorkoutDetailView + SwimAutoSets
            ├── Strength/                           — Active session, library, picker, detail, RestTimer
            ├── Nutrition/                          — NutritionMainView + scanner + result + manual + detail
            ├── Settings/                           — SettingsView + 8 edit sheets + HealthStatusSheet
            ├── Onboarding/                         — 8-step OnboardingView
            └── Theme/                              — IndexPalette + IndexTypography
```

Xcode 16+ `PBXFileSystemSynchronizedRootGroup` is on — new `.swift` files in `Index/Index/**/` auto-discover. No manual `project.pbxproj` edits needed for sources.

## Docs

| File | Purpose |
|---|---|
| `README.md` | This file — what the app is, how to build, where to look. |
| `CONTEXT.md` | Comprehensive architecture map — every module, every service, every model, every view, plus the patterns binding them together. Start here for a deep read. |
| `CLAUDE.md` | Working agreement — build commands, schema evolution rules, non-negotiable patterns, audit-derived defensive coding rules, code style, what's explicitly NOT in v1. |
| `PROGRESS.md` | Phase-by-phase log of what shipped, audit punch list, deferred-question answers, post-v1 backlog. |
