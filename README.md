# Index

A private iOS app that interprets your body, fitness, and nutrition data instead of just displaying it.

iOS 26.4+. SwiftUI, SwiftData, HealthKit. Pre-1.0; no public release.

## Build

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Index/Index.xcodeproj \
  -target Index \
  -sdk iphonesimulator26.5 \
  -configuration Debug build
```

See `CONTEXT.md` for the architecture overview and `CLAUDE.md` for the working agreement.
