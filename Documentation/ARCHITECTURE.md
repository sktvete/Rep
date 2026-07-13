# Rep architecture

Rep is an offline-first strength log. The architecture is intentionally small: SwiftUI feature views, SwiftData domain models, and focused services for behavior that must be deterministic and testable.

## Local-first persistence

SwiftData is the immediate source of truth. Views may observe queries, but mutations that span multiple models live in services. Every meaningful workout mutation is saved at the point of interaction. Logging never waits for a network request.

Models use UUID identifiers, scalar values and explicit timestamps. Enums are stored by raw string where required. These choices keep a future CloudKit-backed `ModelContainer` practical without changing feature code. A synchronization failure must never prevent a local save.

## Session durability

A workout is inserted as soon as it starts. Set edits, completions, additions, removals, exercise ordering and session completion each save the model context immediately. An active-session query restores the newest active workout at launch. The rest timer derives its remaining time from an absolute end date, so navigating between views does not reset it.

The timer is an independent service. This is the seam for future local notifications, Live Activities, Dynamic Island controls and Watch connectivity. Only one timer can be active, which prevents duplicate countdowns.

## Saved routines and workout snapshots

`Routine` and `RoutineExercise` describe reusable intent. Starting a workout creates independent `WorkoutSession`, `WorkoutExercise` and `WorkoutSet` objects. The active workout retains stable source identifiers for comparison and previous-performance lookup, but it never shares mutable children with its routine.

This separation makes it possible to offer “keep this workout”, “update routine” or “save as new routine” later without changing historical data. Completed sessions are treated as editable records rather than immutable analytics events.

## Previous-performance selection

Prefilling follows a deterministic order:

1. Most recent completed instance of the exercise sourced from the same routine.
2. Most recent completed instance of the exercise in any workout.
3. Routine target sets and default repetitions.
4. Empty values appropriate to the exercise measurement type.

Previous values are copied into new sets. They are also shown separately in the logging interface; no historical object is reused or mutated.

## Pattern detection

Pattern assistance is deterministic, observational and optional. The engine considers completed sessions only and evaluates weekday repetition, routine transitions and routine rotation. Scores account for frequency, recency, observation count, competing outcomes and prior dismissals. Thresholds are centralized.

Suggestions include their evidence in plain language. Dismissals reduce confidence; suppression prevents a pattern from returning. Detection is a service boundary, so its results can be recomputed without coupling the Today screen to storage details.

## Metrics

Metric calculations are pure utilities. Estimated one-repetition maximum uses a replaceable strategy (Epley by default). Volume is returned only for compatible measurement types. Date-range filtering, personal records and unit conversion use deterministic inputs and are covered by tests.

Kilograms are the canonical stored mass unit. The user’s kilograms/pounds setting affects formatting and input conversion only.

## Exercise discovery and media

The curated local exercise library remains immediately available offline. `ExerciseDBCatalogService` augments it with a cursor-paginated remote catalog, saving each page to SwiftData before advancing a durable checkpoint. Existing records merge by external identifier or normalized name; remote searches can import close matches while the full catalog continues in the background.

`ExerciseSearchEngine` deterministically ranks name, alias, muscle, and equipment matches. Complete multi-token matches outrank partial matches, and bounded edit distance supports small typing errors without turning unrelated results into suggestions.

Picker thumbnails use the remote GIF’s first frame. A form-reference sheet loads animated GIF or video media only when requested, so browsing and workout logging do not create a large up-front media cost. Catalog metadata is persisted; media remains an on-demand boundary suitable for a later explicit download manager.

## Future boundaries

The following boundaries are intentionally present or documented without pretending that integrations work today:

- `CloudSyncService`: configure a private CloudKit container, migrations and conflict policy; keep the local container authoritative while writes synchronize asynchronously.
- `HealthDataService`: request explicit HealthKit permission only when bodyweight reads and workout-summary writes ship. Detailed sets remain in Rep.
- `WorkoutImportService`: parse Strong/Hevy/generic CSV into a previewable canonical representation with exercise mapping, duplicate checks and an import transaction identifier for undo.
- `ExerciseMediaService`: resolve optional local/downloaded demonstration media without making the exercise model network-dependent.
- Notification/rest timer boundary: schedule timer completion feedback without making a notification the timer’s source of truth.
- Watch target: share domain semantics and transfer stable identifiers/snapshots; do not make Watch connectivity necessary for phone logging.

## Canonical export direction

A future full-fidelity JSON export should be versioned and contain exercises, routines, routine exercises, workouts, workout exercises, sets, bodyweight entries and user-controlled learned-pattern state. Relationships should use stable UUIDs rather than display names. CSV export can be a flattened convenience format; it should not be the only portable backup.

## Error handling and diagnostics

Recoverable input problems are shown beside the relevant control. Persistence failures are surfaced to the user and logged through Apple’s unified logging system using technical context only. Workout details are not written to diagnostic logs.
