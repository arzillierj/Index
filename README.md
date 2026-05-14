# Index

A private iOS app that interprets your body, fitness, and nutrition data instead of just displaying it.

iOS 26.4+. SwiftUI, SwiftData, HealthKit. Pre-1.0; no public release.

## Status

Phases 1–6 complete (foundation, services, onboarding, body, fitness + strength, nutrition). Phase 7 (Settings) is next. Audit complete; consolidated punch list in `PROGRESS.md`.

## Build

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Index/Index.xcodeproj \
  -target Index \
  -sdk iphonesimulator26.5 \
  -configuration Debug build
```

The Xcode-26.4.1 SDK is `iphonesimulator26.5` even though the runtime installed is iOS 26.4 — using `-target` (not `-scheme`) plus explicit `-sdk` bypasses destination resolution.

## Docs

| File | Purpose |
|---|---|
| `README.md` | This file — what the app is, how to build, where to look |
| `CONTEXT.md` | Product + architecture overview, current state, known limitations |
| `CLAUDE.md` | Working agreement — non-negotiable rules, patterns, audit-derived defensive coding rules |
| `PROGRESS.md` | Phase-by-phase log of what shipped, audit punch list, deferred questions, post-v1 backlog |
