# Index

A private iOS app that interprets your body, fitness, and nutrition data instead of just displaying it. iOS 26.4+. SwiftUI, SwiftData, HealthKit. Pre-1.0; no public release.

## What it does

Three modules — **Body**, **Fitness**, **Nutrition** — sit on top of Apple's stack. HealthKit feeds in workouts (anchored observer from Apple Watch), weight + body composition (RENPHO via HK), and daily vitals (HRV / VO2 / resting HR). Index reads them, writes back only `bodyMass`, and runs a pure-function **Brain** that produces templated insight sentences per module ("HRV down 12% — consider lighter training", "Strong week — 4 sessions logged").

Logging is fast and gym-first: the LOG button is a primary action when manual entry is enabled, hidden when automated sources are doing the work. Weights, workouts, meals, and strength sets all land in one tap from each module's main screen.

Nutrition has a single **Camera** screen that handles two paths from the same live preview:

- **Barcode** — meal capture is the default posture, so barcode lookup is opportunistic. When a code drifts into frame a chip slides up offering the OpenFoodFacts lookup; the user taps to confirm. Free, no API cost.
- **AI meal-photo macro estimate** — shutter button (or photo-library picker) sends a downscaled JPEG to Claude Haiku 4.5 via the Anthropic API. The response carries an `isFood` self-check, name, kcal + macros, and a confidence level. Successful estimates open the editable manual-entry sheet pre-filled. Every call is cost-gated through a hard monthly budget cap stored in `AIUsageRecord` rows; the API key lives only in iOS Keychain.

Strength training is freestyle (no templates) over a 10-item starter catalog. Local notifications fire when Apple Health imports a new workout or weigh-in (off by default; opt-in per type).

## Status

Phases 1–7 complete + post-Phase-7 features:

- **Foundation, services, onboarding, Body, Fitness + Strength, Nutrition** all wired end-to-end.
- **Phase 7 Settings** complete — profile editing, calorie adjustment slider (signed deficit/surplus), protein target, module toggles, manual-logging toggles, eat-back workout calories, Apple Health connection panel, notifications (workout + weight), AI estimator (API key + monthly budget + month-to-date spend), reset / sign-out / delete-account.
- **AI macro estimator** — Anthropic Haiku 4.5 vision call, Keychain-stored key, `AIUsageRecord` per-call usage tracking, monthly budget cap.
- **Camera redesign** — meal capture is the default; barcode lookup is a tap-to-confirm chip rather than auto-fire.
- **Audit Phase 5** complete — 24 H-tier fixes + DQ-derived schema bumps across 5 rounds; build clean at every round close.
- **Centralized theme** — `IndexPalette` for colors, `IndexFont` for SF Pro typography with `.monospacedDigit()` for tabular alignment.
- **Per-module accent tinting** — Body blue, Fitness coral, Nutrition teal; tab tint switches with the active tab.

Not yet shipped: CloudKit private database sync (model shape is ready; flipping `cloudKitDatabase:` is a one-line edit when Developer Program enrollment lands), real Sign in with Apple (`AppleSignInIdentityService` exists as non-trapping stubs), imperial display units (helpers exist; no view branches on `Profile.units`), HR-series persistence on import, custom launch screen + icon.

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
        ├── Models/                                 — 11 @Model classes + IndexSchema list
        ├── Services/                               — HK bridge, Profile, Identity, Brain, Metrics,
        │                                            Notifications, OFF, Keychain, Claude (AI), SafeFormat
        └── Views/
            ├── Body/                               — BodyView + log / detail / history
            ├── Fitness/                            — FitnessMainView + log sheets + WorkoutDetailView + SwimAutoSets
            ├── Strength/                           — Active session, library, picker, detail, RestTimer
            ├── Nutrition/                          — NutritionMainView + camera (barcode + AI) + result + manual + detail
            ├── Settings/                           — SettingsView + 10 edit sheets + HealthStatusSheet
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
