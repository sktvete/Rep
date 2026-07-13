# Rep

Rep is a quiet, local-first strength-training log for iPhone. It is designed to make the normal repeated workout fast: start a likely routine, reuse the last useful set values, and complete a set with one tap.

Rep is an adaptive logbook, not a coach. Suggestions describe observed behavior and always leave the user in control.

## Platform and tools

- iOS 18 or later
- Swift 6 and SwiftUI
- SwiftData for offline persistence
- Swift Charts for progress and bodyweight
- Swift Testing for business logic
- No third-party packages

## Exercise catalog and form references

The app starts with its curated offline exercise library, then incrementally synchronizes the free ExerciseDB catalog when an exercise picker is opened. The current catalog contains approximately 1,500 exercises with GIF demonstrations, muscle and equipment metadata, and step-by-step instructions. Catalog pages are saved immediately, so an interrupted update resumes without discarding earlier pages.

Search ranks names, common aliases, muscles, and equipment together, including prefix and typo matching. Queries such as “Back dead” prioritize deadlift variations instead of simply filtering by literal title text. A short debounced online lookup can surface uncommon exercises before the full background catalog update reaches them.

Catalog metadata remains available offline after synchronization. Demonstration media loads on demand and may require a connection if it is not already cached. Each form-reference screen includes source attribution and uses observational language rather than presenting the demonstration as authoritative coaching.

Open `Rep.xcodeproj` in the current stable Xcode. Select an iPhone simulator and run the `Rep` scheme. Run tests with Product → Test or:

```sh
xcodebuild test -project Rep.xcodeproj -scheme Rep -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Project structure

- `Rep/App`: application entry point and primary navigation
- `Rep/Models`: SwiftData schema and domain values
- `Rep/Services`: repositories, workout behavior, patterns, metrics, timer and sample data
- `Rep/Features`: Today, routines, workout logging, history, progress and settings
- `Rep/Shared`: small reusable presentation and support code
- `RepTests`: deterministic unit tests
- `Documentation/ARCHITECTURE.md`: design decisions and future service boundaries

## Data model

Saved `Routine` objects own ordered `RoutineExercise` templates. Starting one creates a separate `WorkoutSession` snapshot with `WorkoutExercise` and `WorkoutSet` children. Completed history therefore cannot be changed by later routine edits. `Exercise`, `BodyweightEntry` and `LearnedPattern` are independent user-owned records with stable UUIDs and timestamps.

Measurement types include weight/repetitions, repetitions-only, duration, weight/duration, distance/duration, bodyweight, added-weight and assisted movements. Calculations intentionally return no result when a metric would be misleading.

## Sample data

Production users receive the modest built-in exercise library but no fabricated workout history. In a Debug build, Settings offers development sample data with Push, Pull and Legs routines, several weeks of deterministic training history, bodyweight entries and an active-workout recovery example. Sample data can also be removed from Settings.

## Current limitations

- Logging and data remain on this device; CloudKit is not enabled.
- Exercise catalog updates and uncached demonstrations depend on ExerciseDB availability and an internet connection.
- HealthKit permission is not requested and no health data is read or written.
- Rest timer feedback is in-app; richer Lock Screen behavior is planned behind the timer service boundary.
- Routine-difference reconciliation is intentionally lightweight in this MVP.
- Import/export and historical workout editing are prepared for but not yet exposed as complete workflows.
- No Apple Watch target is included yet.

## Planned integrations

CloudKit will synchronize private records while SwiftData remains the immediate offline source of truth. Before enabling it, add the iCloud capability and container, validate the schema in a development environment, define migration/conflict behavior and test offline edits plus account changes.

HealthKit will use explicit, just-in-time permission to read bodyweight and write a standardized workout summary. Detailed strength sets remain in Rep. A future Watch app will use stable workout identifiers and shared domain semantics while preserving independent phone-side logging.

See [Documentation/ARCHITECTURE.md](Documentation/ARCHITECTURE.md) for session durability, patterns, export direction and service boundaries.

## Product boundaries

This version deliberately excludes accounts, social features, nutrition, GPS, subscriptions, generative coaching, computer vision, program marketplaces and production cloud/health integrations.
