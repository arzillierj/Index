# Index v2 — Backlog

Single home for everything not yet built: open bugs, pre-release requirements, doc debt, and deferred ideas.

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

## Doc debt

- **`CLAUDE.md` still lists photo-to-macros under "things explicitly NOT in v1".** The AI macro estimator has shipped — this line is false and a future session could treat the feature as dead code.
  - **Status:** Inaccurate in current `CLAUDE.md`.
  - **Next step:** Remove the line.

- **`README.md` refers to `IndexFont`; the file is `IndexTypography.swift`.**
  - **Status:** Reference mismatched in current `README.md`.
  - **Next step:** Correct the reference.

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
  - **Next step:** After enrollment, add `cloudKitDatabase: .private(...)` to the `ModelConfiguration` in `IndexApp.sharedContainer`.

- **Sign in with Apple.** Blocked on paid Apple Developer enrollment.
  - **Status:** `AppleSignInIdentityService` exists as non-trapping stubs; protocol seam is in place.
  - **Next step:** After enrollment, fill the four method bodies and flip `AppDependencies.identity` from `DevIdentityService()` to `AppleSignInIdentityService()`.

---

## Standing note

- **Dogfood before building.** The build phase is essentially done and the app has ~1 year of demo data. Use Index daily for ~2 weeks before adding features so the next changes come from real friction. The calorie-target bug is the precedent — it was found by using the app and checking the math, not by planning.
