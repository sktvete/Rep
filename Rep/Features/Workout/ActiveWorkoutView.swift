import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum WorkoutKeyboardDestination: CaseIterable, Hashable, Identifiable {
    case workout
    case history
    case routines
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .workout: "Workout"
        case .history: "History"
        case .routines: "Routines"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .workout: "bolt.fill"
        case .history: "clock.arrow.circlepath"
        case .routines: "list.bullet.rectangle"
        case .settings: "gearshape"
        }
    }
}

struct ActiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \Exercise.name)
    private var exerciseLibrary: [Exercise]

    @Query(sort: \WorkoutSession.startedAt, order: .reverse)
    private var allSessions: [WorkoutSession]

    @Query private var settings: [UserSettings]

    let session: WorkoutSession
    let onKeyboardNavigate: (WorkoutKeyboardDestination) -> Void
    let onClose: () -> Void

    @State private var selectedExerciseID: UUID?
    @State private var restTimer: WorkoutRestTimerViewModel
    @State private var isShowingExercisePicker = false
    @State private var draggedExerciseID: UUID?
    @State private var detailExercise: Exercise?
    @State private var isShowingFinishConfirmation = false
    @State private var isShowingDiscardConfirmation = false
    @State private var isShowingRemoveExerciseConfirmation = false
    @State private var exercisePendingRemoval: WorkoutExercise?
    @State private var isShowingCompletion = false
    @State private var errorMessage: String?
    @State private var debouncedSaveTask: Task<Void, Never>?

    init(
        session: WorkoutSession,
        onKeyboardNavigate: @escaping (WorkoutKeyboardDestination) -> Void = { _ in },
        onClose: @escaping () -> Void = {}
    ) {
        self.session = session
        self.onKeyboardNavigate = onKeyboardNavigate
        self.onClose = onClose
        _selectedExerciseID = State(initialValue: Self.restoredSelection(for: session))
        _restTimer = State(initialValue: WorkoutRestTimerViewModel(sessionID: session.id))
    }

    private var orderedExercises: [WorkoutExercise] { session.orderedExercises }

    private var currentExercise: WorkoutExercise? {
        orderedExercises.first { $0.id == selectedExerciseID } ?? orderedExercises.first
    }

    private var defaultRestSeconds: Int {
        settings.first?.defaultRestSeconds ?? 90
    }

    private var hapticsEnabled: Bool {
        settings.first?.hapticsEnabled ?? true
    }

    private var preferredUnit: WeightUnit {
        settings.first?.preferredWeightUnit ?? .kilograms
    }

    private var availableExercises: [Exercise] {
        exerciseLibrary.filter { !$0.isArchived }
    }

    @State private var isCreatingCustomExercise = false

    var body: some View {
        NavigationStack {
            ZStack {
                RepScreenBackground()

                Group {
                    if let currentExercise {
                        workoutContent(currentExercise)
                    } else {
                        emptyWorkout
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .exerciseThumbnailScope()
        .background(KeyboardDismissTapInstaller())
        .interactiveDismissDisabled(session.state == .active)
        .onAppear {
            if selectedExerciseID == nil {
                selectedExerciseID = orderedExercises.first?.id
            }
            ExercisePickerSessionCache.scheduleWarm(
                exercises: availableExercises,
                in: modelContext
            )
            updateRestTimerHapticsPreference()
            ActiveWorkoutRestTimerBridge.shared.register(timer: restTimer) {
                restTimer.start(seconds: 5, nextExerciseName: "Development test")
            }
            WorkoutLiveActivityWorkoutCoordinator.register(modelContext: modelContext) { exerciseID in
                selectedExerciseID = exerciseID
            }
            synchronizeLiveActivity()
        }
        .onDisappear {
            ActiveWorkoutRestTimerBridge.shared.unregister(timer: restTimer)
            WorkoutLiveActivityWorkoutCoordinator.unregister()
            debouncedSaveTask?.cancel()
            persist()
        }
        .onChange(of: settings.first?.hapticsEnabled) { _, _ in
            updateRestTimerHapticsPreference()
        }
        .onChange(of: settings.first?.preferredWeightUnitRaw) { _, _ in
            synchronizeLiveActivity()
        }
        .onChange(of: selectedExerciseID) { _, exerciseID in
            rememberSelection(exerciseID)
            synchronizeLiveActivity()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                restTimer.reconcileAfterForeground()
            } else {
                debouncedSaveTask?.cancel()
                persist()
            }
        }
        .onChange(of: orderedExercises.map(\.id)) { _, ids in
            if !ids.contains(selectedExerciseID ?? UUID()) {
                selectedExerciseID = ids.first
            }
        }
        .sheet(isPresented: $isShowingExercisePicker) {
            WorkoutExercisePicker(
                exercises: availableExercises,
                title: "Add exercise"
            ) { exercise in
                addExercise(exercise)
            }
        }
        .sheet(item: $detailExercise) { exercise in
            ExerciseDetailView(exercise: exercise)
        }
        .confirmationDialog(
            "Discard this workout?",
            isPresented: $isShowingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard workout", role: .destructive) { discardWorkout() }
            Button("Keep training", role: .cancel) {}
        } message: {
            Text(discardWorkoutMessage)
        }
        .confirmationDialog(
            session.completedSetCount == session.exercises.flatMap(\.sets).count
                ? "Finish workout?"
                : "Finish with incomplete sets?",
            isPresented: $isShowingFinishConfirmation,
            titleVisibility: .visible
        ) {
            Button("Finish workout") { finishWorkout() }
            Button("Keep training", role: .cancel) {}
        } message: {
            if session.completedSetCount < session.exercises.flatMap(\.sets).count {
                Text("Completed sets will be kept. Incomplete sets remain visible in workout history.")
            }
        }
        .confirmationDialog(
            "Remove this exercise?",
            isPresented: $isShowingRemoveExerciseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove exercise", role: .destructive) {
                if let exercisePendingRemoval {
                    removeExercise(exercisePendingRemoval)
                }
                exercisePendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                exercisePendingRemoval = nil
            }
        }
        .alert("Couldn’t save the workout", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Your changes remain on screen. Please try again.")
        }
        .sensoryFeedback(.success, trigger: hapticsEnabled ? session.completedSetCount : 0)
        .overlay {
            if isShowingCompletion {
                WorkoutCompletionView(
                    session: session,
                    preferredUnit: preferredUnit
                ) {
                    restTimer.endWorkout()
                    onClose()
                    dismiss()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.snappy(duration: 0.35), value: isShowingCompletion)
    }

    private func updateRestTimerHapticsPreference() {
        restTimer.shouldPlayCompletionHaptic = { hapticsEnabled }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                dismissKeyboard()
                persist()
                onClose()
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close workout")
            .accessibilityHint("Keeps the workout active so you can resume it later")
        }

        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text(session.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = session.duration(at: context.date)
                    Text(formattedLiveElapsed(elapsed))
                        .font(.body.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.primary)
                        .accessibilityLabel("Elapsed time \(formattedLiveElapsed(elapsed))")
                }
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            if session.exercises.isEmpty {
                Button("New Exercise", systemImage: "plus") {
                    isCreatingCustomExercise = true
                }
            }

            if restTimer.isPresented {
                Menu {
                    Button(
                        restTimer.isPaused ? "Resume rest" : "Pause rest",
                        systemImage: restTimer.isPaused ? "play.fill" : "pause.fill"
                    ) {
                        restTimer.togglePause()
                    }
                    Button("Add 15 seconds", systemImage: "plus") { restTimer.adjust(by: 15) }
                    Button("Remove 15 seconds", systemImage: "minus") { restTimer.adjust(by: -15) }
                    Button("Skip rest", systemImage: "xmark") { restTimer.skip() }
                } label: {
                    Image(systemName: restTimer.isPaused ? "pause.circle" : "timer")
                }
                .accessibilityLabel("Rest timer options")
            }

            Button("Finish") {
                dismissKeyboard()
                if shouldOfferDiscard {
                    isShowingDiscardConfirmation = true
                } else {
                    isShowingFinishConfirmation = true
                }
            }
            .font(.subheadline.weight(.semibold))
            .controlSize(.small)
        }

        ToolbarItem(placement: .keyboard) {
            HStack(spacing: 10) {
                ForEach(WorkoutKeyboardDestination.allCases) { destination in
                    Button {
                        navigateFromKeyboard(to: destination)
                    } label: {
                        Image(systemName: destination.systemImage)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(destination == .workout ? Color.accentColor : .primary)
                    .accessibilityLabel(destination.title)
                    .accessibilityHint("Opens \(destination.title.lowercased())")
                }

                Spacer(minLength: 4)

                Button("Done") { dismissKeyboard() }
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var shouldOfferDiscard: Bool {
        session.completedSetCount == 0
    }

    private var discardWorkoutMessage: String {
        if session.exercises.isEmpty {
            return "You haven't added any exercises yet. Nothing will be saved to your history."
        }
        return "Complete at least one set before finishing. Nothing will be saved to your history."
    }

    private func formattedLiveElapsed(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func workoutContent(_ workoutExercise: WorkoutExercise) -> some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                exerciseNavigation

                currentExerciseHeader(workoutExercise)
                previousPerformance(for: workoutExercise)
                setsCard(workoutExercise)

                Button {
                    dismissKeyboard()
                    addSet(to: workoutExercise)
                } label: {
                    Label("Add set", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .repSecondaryButton()
            }
            .padding(.horizontal)
            .padding(.top, 6)
            .padding(.bottom, 18)
        }
        .contentMargins(.bottom, 16, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .repSoftScrollEdges()
    }

    private var exerciseNavigation: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(orderedExercises) { workoutExercise in
                    let isSelected = workoutExercise.id == currentExercise?.id
                    let completeCount = workoutExercise.sets.filter(\.isCompleted).count
                    let isComplete = !workoutExercise.sets.isEmpty && completeCount == workoutExercise.sets.count

                    Button {
                        dismissKeyboard()
                        withAnimation(.easeOut(duration: 0.18)) {
                            selectedExerciseID = workoutExercise.id
                        }
                    } label: {
                        exerciseNavigationPill(
                            workoutExercise,
                            isSelected: isSelected,
                            isComplete: isComplete,
                            completeCount: completeCount
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(.dragPreview, Capsule())
                    .onDrag {
                        dismissKeyboard()
                        if hapticsEnabled {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
                        }
                        draggedExerciseID = workoutExercise.id
                        return NSItemProvider(object: workoutExercise.id.uuidString as NSString)
                    } preview: {
                        exerciseNavigationPill(
                            workoutExercise,
                            isSelected: isSelected,
                            isComplete: isComplete,
                            completeCount: completeCount
                        )
                        .contentShape(.dragPreview, Capsule())
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: WorkoutExerciseDropDelegate(
                            targetID: workoutExercise.id,
                            draggedID: $draggedExerciseID,
                            onMove: moveExercise,
                            onDrop: persist
                        )
                    )
                    .contextMenu {
                        Button("Remove exercise", systemImage: "trash", role: .destructive) {
                            exercisePendingRemoval = workoutExercise
                            isShowingRemoveExerciseConfirmation = true
                        }
                    }
                    .accessibilityLabel("\(workoutExercise.exercise?.name ?? "Exercise"), \(isComplete ? "complete" : "\(completeCount) of \(workoutExercise.sets.count) sets complete")")
                    .accessibilityHint("Press and hold for options, or drag to reorder")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }

                Button {
                    dismissKeyboard()
                    isShowingExercisePicker = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 13)
                        .frame(height: 44)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .repGlassControl(cornerRadius: 99)
                .accessibilityLabel("Add exercise")
                .accessibilityHint("Adds an exercise after the current exercise")
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func exerciseNavigationPill(
        _ workoutExercise: WorkoutExercise,
        isSelected: Bool,
        isComplete: Bool,
        completeCount: Int
    ) -> some View {
        HStack(spacing: 8) {
            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(isSelected ? .white : .green)
                    .imageScale(.small)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(workoutExercise.exercise?.name ?? "Exercise")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(isComplete ? "Complete" : "\(completeCount)/\(workoutExercise.sets.count) sets")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.82) : .secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .fixedSize(horizontal: true, vertical: false)
        .frame(minWidth: 112)
        .foregroundStyle(isSelected ? .white : .primary)
        .contentShape(.capsule)
        .repGlassControl(
            tint: isSelected ? RepVisualSystem.tint : (isComplete ? Color.green.opacity(0.12) : nil),
            cornerRadius: 99
        )
    }

    private func currentExerciseHeader(_ workoutExercise: WorkoutExercise) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if let exercise = workoutExercise.exercise {
                Button {
                    dismissKeyboard()
                    detailExercise = exercise
                } label: {
                    ExerciseMediaThumbnail(exercise: exercise, size: 56, listIndex: 0)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View instructions for \(exercise.name)")
                .accessibilityHint("Opens the exercise demonstration and instructions")
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(workoutExercise.exercise?.name ?? "Unavailable exercise")
                    .font(.title3.bold())
                    .lineLimit(2)
                if let exercise = workoutExercise.exercise {
                    Text("\(exercise.primaryMuscleGroup.displayName) · \(exercise.equipment.displayName)")
                        .font(.subheadline)
                        .repSecondaryText()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Menu {
                Button("Remove exercise", systemImage: "trash", role: .destructive) {
                    dismissKeyboard()
                    exercisePendingRemoval = workoutExercise
                    isShowingRemoveExerciseConfirmation = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Exercise options")
        }
    }

    @ViewBuilder
    private func previousPerformance(for workoutExercise: WorkoutExercise) -> some View {
        if let previous = previousWorkoutExercise(for: workoutExercise) {
            let completedSets = previous.exercise.orderedSets.filter(\.isCompleted)

            HStack(spacing: 10) {
                Text(previous.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption.weight(.semibold))
                    .repSecondaryText()
                    .fixedSize(horizontal: true, vertical: false)

                if completedSets.isEmpty {
                    Text("No completed sets")
                        .font(.caption)
                        .repSecondaryText()
                } else {
                    ScrollView(.horizontal) {
                        LazyHGrid(
                            rows: [
                                GridItem(.fixed(18), spacing: 3),
                                GridItem(.fixed(18), spacing: 3)
                            ],
                            spacing: 7
                        ) {
                            ForEach(Array(completedSets.enumerated()), id: \.element.id) { index, set in
                                HStack(spacing: 3) {
                                    Text("\(index + 1):")
                                        .foregroundStyle(.secondary)
                                    Text(shortSetDescription(set))
                                        .foregroundStyle(.primary)
                                }
                                .font(.caption.monospacedDigit().weight(.medium))
                                .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .frame(height: 39)
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private func setsCard(_ workoutExercise: WorkoutExercise) -> some View {
        VStack(spacing: 0) {
            SetColumnHeader(
                measurementType: workoutExercise.exercise?.measurementType ?? .weightAndRepetitions,
                preferredUnit: preferredUnit
            )

            if workoutExercise.orderedSets.isEmpty {
                ContentUnavailableView(
                    "No sets",
                    systemImage: "list.number",
                    description: Text("Add a set to begin logging this exercise.")
                )
                .padding(.vertical, 20)
            } else {
                ForEach(workoutExercise.orderedSets) { set in
                    Divider().padding(.leading, 38)
                    ActiveWorkoutSetRow(
                        set: set,
                        measurementType: workoutExercise.exercise?.measurementType ?? .weightAndRepetitions,
                        preferredUnit: preferredUnit,
                        weightStep: weightStep(for: workoutExercise.exercise),
                        onEdit: schedulePersist,
                        onToggleCompletion: {
                            dismissKeyboard()
                            toggleCompletion(of: set, in: workoutExercise)
                        },
                        onDelete: { removeSet(set, from: workoutExercise) }
                    )
                    .id(set.id)
                }
            }
        }
        .repSurface(cornerRadius: 14, shadowRadius: 3, shadowY: 1)
        .clipShape(.rect(cornerRadius: 14))
    }

    private func weightStep(for exercise: Exercise?) -> Double {
        guard exercise?.primaryMuscleGroup == .shoulders else { return 5 }
        return preferredUnit == .kilograms ? 1 : 2.5
    }

    private var emptyWorkout: some View {
        ExerciseQuickAddList(
            exercises: availableExercises,
            header: "Add exercises to start",
            footer: "Tap + to add. Search updates when you pause typing.",
            isCreatingExercise: $isCreatingCustomExercise,
            dismissOnSelect: false,
            onSelect: { addExercise($0) }
        )
    }

    private func addExercise(_ exercise: Exercise) {
        let insertionIndex = currentExercise
            .flatMap { current in orderedExercises.firstIndex(where: { $0.id == current.id }) }
            .map { $0 + 1 }
            ?? orderedExercises.count

        for existingExercise in orderedExercises where existingExercise.orderIndex >= insertionIndex {
            existingExercise.orderIndex += 1
        }

        let set = WorkoutSet(orderIndex: 0)
        let workoutExercise = WorkoutExercise(
            exercise: exercise,
            orderIndex: insertionIndex,
            defaultRestSeconds: defaultRestSeconds,
            sets: [set]
        )
        session.exercises.append(workoutExercise)
        session.normalizeExerciseOrder()
        session.updatedAt = .now
        selectedExerciseID = workoutExercise.id
        persist()
    }

    private func moveExercise(_ draggedID: UUID, over targetID: UUID) {
        guard draggedID != targetID else { return }

        var reordered = orderedExercises
        guard let sourceIndex = reordered.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = reordered.firstIndex(where: { $0.id == targetID }) else { return }

        withAnimation(.snappy(duration: 0.2)) {
            reordered.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
            )
            for (index, exercise) in reordered.enumerated() {
                exercise.orderIndex = index
            }
            session.exercises = reordered
        }
        if hapticsEnabled {
            UISelectionFeedbackGenerator().selectionChanged()
        }
        session.updatedAt = .now
        schedulePersist()
    }

    private func removeExercise(_ workoutExercise: WorkoutExercise) {
        let removedIndex = orderedExercises.firstIndex { $0.id == workoutExercise.id } ?? 0
        session.exercises.removeAll { $0.id == workoutExercise.id }
        session.normalizeExerciseOrder()
        session.updatedAt = .now
        modelContext.delete(workoutExercise)
        let remainingExercises = session.orderedExercises
        selectedExerciseID = remainingExercises.isEmpty
            ? nil
            : remainingExercises[min(removedIndex, remainingExercises.count - 1)].id
        persist()
    }

    private func addSet(to workoutExercise: WorkoutExercise) {
        let previous = workoutExercise.orderedSets.last
        let set = WorkoutSet(
            orderIndex: workoutExercise.sets.count,
            setType: previous?.setType ?? .working,
            weight: previous?.weight,
            repetitions: previous?.repetitions,
            durationSeconds: previous?.durationSeconds,
            distance: previous?.distance,
            assistanceWeight: previous?.assistanceWeight
        )
        workoutExercise.sets.append(set)
        workoutExercise.normalizeSetOrder()
        session.updatedAt = .now
        persist()
    }

    private func removeSet(_ set: WorkoutSet, from workoutExercise: WorkoutExercise) {
        workoutExercise.sets.removeAll { $0.id == set.id }
        workoutExercise.normalizeSetOrder()
        session.updatedAt = .now
        modelContext.delete(set)
        persist()
    }

    private func toggleCompletion(of set: WorkoutSet, in workoutExercise: WorkoutExercise) {
        if set.isCompleted {
            set.reopen()
        } else {
            set.markCompleted()
            if let nextIncomplete = workoutExercise.orderedSets.first(where: { !$0.isCompleted }) {
                WorkoutLiveActivityStateBuilder.prefillEmptyValues(on: nextIncomplete, from: set)
            }
            WorkoutLiveActivityWorkoutCoordinator.advanceAfterCompletion(
                session: session,
                completedSetID: set.id,
                preferredUnit: preferredUnit
            )
            let restSeconds = workoutExercise.defaultRestSeconds ?? defaultRestSeconds
            if restSeconds > 0 {
                restTimer.start(
                    seconds: restSeconds,
                    nextExerciseName: nextExerciseName(afterCompleting: set, in: workoutExercise)
                )
            }
        }
        session.updatedAt = .now
        persist()
    }

    private func nextExerciseName(afterCompleting set: WorkoutSet, in workoutExercise: WorkoutExercise) -> String {
        if let nextSet = workoutExercise.orderedSets.first(where: { !$0.isCompleted }) {
            let exerciseName = workoutExercise.exercise?.name ?? "Exercise"
            return "\(exerciseName) · Set \(nextSet.orderIndex + 1)"
        }

        guard let index = orderedExercises.firstIndex(where: { $0.id == workoutExercise.id }) else {
            return workoutExercise.exercise?.name ?? "Next exercise"
        }

        let upcoming = orderedExercises.suffix(from: min(index + 1, orderedExercises.endIndex))
        if let nextExercise = upcoming.first {
            return nextExercise.exercise?.name ?? "Next exercise"
        }

        let exerciseName = workoutExercise.exercise?.name ?? "Exercise"
        return "\(exerciseName) · Another set"
    }

    private func previousWorkoutExercise(for workoutExercise: WorkoutExercise) -> (exercise: WorkoutExercise, date: Date)? {
        guard let exerciseID = workoutExercise.exercise?.id else { return nil }
        guard let previous = WorkoutCreationService().previousPerformance(
            for: exerciseID,
            routineID: session.routineID,
            before: session.startedAt,
            sessions: allSessions
        ) else { return nil }
        return (
            exercise: previous.exercise,
            date: previous.session.completedAt ?? previous.session.startedAt
        )
    }

    private func shortSetDescription(_ set: WorkoutSet) -> String {
        if let weight = set.weight, let repetitions = set.repetitions {
            let displayed = UnitConversion.weight(weight, from: .kilograms, to: preferredUnit)
            return "\(displayed.formatted(.number.precision(.fractionLength(0...2))))×\(repetitions)"
        }
        if let repetitions = set.repetitions { return "\(repetitions) reps" }
        if let duration = set.durationSeconds { return "\(duration)s" }
        if let distance = set.distance { return "\(distance.formatted(.number.precision(.fractionLength(0...2)))) m" }
        return "Done"
    }

    private func finishWorkout() {
        do {
            try WorkoutService(context: modelContext).finish(session)
            clearRememberedSelection()
            restTimer.endWorkout()
            isShowingCompletion = true
        } catch {
            AppLog.persistenceFailure(operation: "Finish workout", error: error)
            errorMessage = error.localizedDescription
        }
    }

    private func discardWorkout() {
        do {
            try WorkoutService(context: modelContext).abandon(session)
            clearRememberedSelection()
            restTimer.endWorkout()
            onClose()
            dismiss()
        } catch {
            AppLog.persistenceFailure(operation: "Discard workout", error: error)
            errorMessage = error.localizedDescription
        }
    }

    private func schedulePersist() {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            persist()
        }
    }

    private func persist() {
        do {
            try modelContext.save()
            synchronizeLiveActivity()
        } catch {
            AppLog.persistenceFailure(operation: "Save active workout", error: error)
            errorMessage = error.localizedDescription
        }
    }

    private static func selectionStorageKey(for sessionID: UUID) -> String {
        "active-workout-selection-\(sessionID.uuidString)"
    }

    private static func restoredSelection(for session: WorkoutSession) -> UUID? {
        let key = selectionStorageKey(for: session.id)
        guard let storedValue = UserDefaults.standard.string(forKey: key),
              let storedID = UUID(uuidString: storedValue),
              session.orderedExercises.contains(where: { $0.id == storedID }) else {
            return session.orderedExercises.first?.id
        }
        return storedID
    }

    private func rememberSelection(_ exerciseID: UUID?) {
        let key = Self.selectionStorageKey(for: session.id)
        if let exerciseID {
            UserDefaults.standard.set(exerciseID.uuidString, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func clearRememberedSelection() {
        UserDefaults.standard.removeObject(forKey: Self.selectionStorageKey(for: session.id))
    }

    private func synchronizeLiveActivity() {
        WorkoutLiveActivityWorkoutCoordinator.synchronize(
            session: session,
            selectedExerciseID: selectedExerciseID,
            preferredUnit: preferredUnit
        )
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func navigateFromKeyboard(to destination: WorkoutKeyboardDestination) {
        dismissKeyboard()
        debouncedSaveTask?.cancel()
        persist()
        onKeyboardNavigate(destination)
    }
}

private struct WorkoutExerciseDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedID: UUID?
    let onMove: (UUID, UUID) -> Void
    let onDrop: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedID, draggedID != targetID else { return }
        onMove(draggedID, targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        onDrop()
        return true
    }
}

private struct KeyboardDismissTapInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WindowReaderView {
        let view = WindowReaderView()
        view.isUserInteractionEnabled = false
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.install(in: window)
        }
        return view
    }

    func updateUIView(_ uiView: WindowReaderView, context: Context) {
        context.coordinator.install(in: uiView.window)
    }

    static func dismantleUIView(_ uiView: WindowReaderView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class WindowReaderView: UIView {
        var onWindowChange: ((UIWindow?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindowChange?(window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var installedWindow: UIWindow?
        private lazy var tapRecognizer: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            return recognizer
        }()

        func install(in window: UIWindow?) {
            guard installedWindow !== window else { return }
            uninstall()
            installedWindow = window
            window?.addGestureRecognizer(tapRecognizer)
        }

        func uninstall() {
            installedWindow?.removeGestureRecognizer(tapRecognizer)
            installedWindow = nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var touchedView = touch.view
            while let view = touchedView {
                if view is UITextField || view is UITextView {
                    return false
                }
                touchedView = view.superview
            }
            return true
        }

        @objc private func handleTap() {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }
    }
}

private struct SetColumnHeader: View {
    let measurementType: MeasurementType
    let preferredUnit: WeightUnit

    var body: some View {
        HStack(spacing: 8) {
            Text("Set")
                .frame(width: 30)
            Group {
                switch measurementType {
                case .weightAndRepetitions, .bodyweightPlusAddedWeight, .custom:
                    Text(preferredUnit.symbol).frame(maxWidth: .infinity)
                    Text("Reps").frame(maxWidth: .infinity)
                case .repetitionsOnly, .bodyweightAndRepetitions:
                    Text("Reps").frame(maxWidth: .infinity)
                case .duration:
                    Text("Seconds").frame(maxWidth: .infinity)
                case .weightAndDuration:
                    Text(preferredUnit.symbol).frame(maxWidth: .infinity)
                    Text("Seconds").frame(maxWidth: .infinity)
                case .distanceAndDuration:
                    Text("Meters").frame(maxWidth: .infinity)
                    Text("Seconds").frame(maxWidth: .infinity)
                case .assistedBodyweight:
                    Text("Assist").frame(maxWidth: .infinity)
                    Text("Reps").frame(maxWidth: .infinity)
                }
            }
            Color.clear.frame(width: 42, height: 1)
        }
        .font(.caption.weight(.semibold))
        .repSecondaryText()
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .accessibilityHidden(true)
    }
}

private struct ActiveWorkoutSetRow: View {
    @Bindable var set: WorkoutSet
    let measurementType: MeasurementType
    let preferredUnit: WeightUnit
    let weightStep: Double
    let onEdit: () -> Void
    let onToggleCompletion: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                Picker("Set type", selection: $set.setTypeRaw) {
                    ForEach(WorkoutSetType.allCases) { type in
                        Text(type.displayName).tag(type.rawValue)
                    }
                }
            } label: {
                Text("\(set.orderIndex + 1)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .frame(width: 30, height: 42)
                    .background(set.setType == .working ? Color.clear : Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            .foregroundStyle(.primary)
            .accessibilityLabel("Set \(set.orderIndex + 1), \(set.setType.displayName)")

            metricFields

            Button(action: onToggleCompletion) {
                ZStack {
                    Circle()
                        .fill(set.isCompleted ? RepVisualSystem.tint : Color.clear)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    set.isCompleted ? Color.clear : Color.accentColor.opacity(0.72),
                                    lineWidth: 2
                                )
                        }
                        .frame(width: 30, height: 30)
                    if set.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: 42, height: 42)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set.isCompleted ? "Reopen set \(set.orderIndex + 1)" : "Complete set \(set.orderIndex + 1)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(set.isCompleted ? RepVisualSystem.tint.opacity(0.07) : .clear)
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .onChange(of: set.setTypeRaw) { _, _ in touchAndSave() }
        .contextMenu {
            Button("Delete set", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    @ViewBuilder
    private var metricFields: some View {
        switch measurementType {
        case .weightAndRepetitions, .bodyweightPlusAddedWeight, .custom:
            OptionalWeightField(title: "Weight", kilograms: $set.weight, preferredUnit: preferredUnit, step: weightStep, onCommit: touchAndSave)
            OptionalIntField(title: "Repetitions", value: $set.repetitions, onCommit: touchAndSave)
        case .repetitionsOnly, .bodyweightAndRepetitions:
            OptionalIntField(title: "Repetitions", value: $set.repetitions, onCommit: touchAndSave)
        case .duration:
            OptionalIntField(title: "Duration in seconds", value: $set.durationSeconds, onCommit: touchAndSave)
        case .weightAndDuration:
            OptionalWeightField(title: "Weight", kilograms: $set.weight, preferredUnit: preferredUnit, step: weightStep, onCommit: touchAndSave)
            OptionalIntField(title: "Duration in seconds", value: $set.durationSeconds, onCommit: touchAndSave)
        case .distanceAndDuration:
            OptionalDoubleField(title: "Distance in meters", value: $set.distance, onCommit: touchAndSave)
            OptionalIntField(title: "Duration in seconds", value: $set.durationSeconds, onCommit: touchAndSave)
        case .assistedBodyweight:
            OptionalWeightField(title: "Assistance weight", kilograms: $set.assistanceWeight, preferredUnit: preferredUnit, step: weightStep, onCommit: touchAndSave)
            OptionalIntField(title: "Repetitions", value: $set.repetitions, onCommit: touchAndSave)
        }
    }

    private func touchAndSave() {
        set.updatedAt = .now
        onEdit()
    }
}

private struct OptionalDoubleField: View {
    let title: String
    @Binding var value: Double?
    let onCommit: () -> Void

    @FocusState private var isFocused: Bool
    @State private var text: String = ""

    var body: some View {
        TextField("—", text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .font(.body.monospacedDigit().weight(.medium))
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel(title)
            .focused($isFocused)
            .onAppear { syncFromValue() }
            .onChange(of: value) { _, _ in
                guard !isFocused else { return }
                syncFromValue()
            }
            .onChange(of: text) { _, text in
                guard isFocused else { return }
                updateValueWhileTyping(text)
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
    }

    private func syncFromValue() {
        if let value {
            text = value.formatted(.number.precision(.fractionLength(0...2)))
        } else {
            text = ""
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if value != nil {
                value = nil
                onCommit()
            }
            return
        }

        guard let parsed = parsedLocalizedDecimal(trimmed), parsed.isFinite else {
            syncFromValue()
            return
        }

        if value != parsed {
            value = parsed
            onCommit()
        }
    }

    private func updateValueWhileTyping(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let parsed = parsedLocalizedDecimal(trimmed),
              parsed.isFinite,
              value != parsed else { return }
        value = parsed
        onCommit()
    }
}

private struct OptionalWeightField: View {
    let title: String
    @Binding var kilograms: Double?
    let preferredUnit: WeightUnit
    let step: Double
    let onCommit: () -> Void

    @FocusState private var isFocused: Bool
    @State private var text: String = ""

    var body: some View {
        ZStack {
            TextField("—", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.body.monospacedDigit().weight(.medium))
                .padding(.horizontal, 29)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .accessibilityLabel("\(title) in \(preferredUnit.displayName.lowercased())")
                .focused($isFocused)
                .onAppear { syncFromValue() }
                .onChange(of: kilograms) { _, _ in
                    guard !isFocused else { return }
                    syncFromValue()
                }
                .onChange(of: text) { _, text in
                    guard isFocused else { return }
                    updateValueWhileTyping(text)
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }

            HStack(spacing: 0) {
                RepeatStepButton(systemImage: "minus", accessibilityLabel: "Decrease \(title.lowercased())") {
                    adjustWeight(by: -step)
                }
                Spacer(minLength: 0)
                RepeatStepButton(systemImage: "plus", accessibilityLabel: "Increase \(title.lowercased())") {
                    adjustWeight(by: step)
                }
            }
        }
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func adjustWeight(by displayDelta: Double) {
        let currentDisplay = currentDisplayValue
        let newDisplay = max(0, currentDisplay + displayDelta)
        guard newDisplay > 0 else {
            kilograms = nil
            syncFromValue()
            onCommit()
            return
        }
        kilograms = UnitConversion.weight(newDisplay, from: preferredUnit, to: .kilograms)
        syncFromValue()
        onCommit()
    }

    private var currentDisplayValue: Double {
        kilograms.map { UnitConversion.weight($0, from: .kilograms, to: preferredUnit) } ?? 0
    }

    private func syncFromValue() {
        if let kilograms {
            let display = UnitConversion.weight(kilograms, from: .kilograms, to: preferredUnit)
            text = display.formatted(.number.precision(.fractionLength(0...2)))
        } else {
            text = ""
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if kilograms != nil {
                kilograms = nil
                onCommit()
            }
            return
        }

        guard let parsedDisplay = parsedLocalizedDecimal(trimmed),
              parsedDisplay.isFinite,
              parsedDisplay >= 0 else {
            syncFromValue()
            return
        }

        let newKilograms = UnitConversion.weight(parsedDisplay, from: preferredUnit, to: .kilograms)
        if kilograms != newKilograms {
            kilograms = newKilograms
            onCommit()
        }
    }

    private func updateValueWhileTyping(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let parsedDisplay = parsedLocalizedDecimal(trimmed),
              parsedDisplay.isFinite,
              parsedDisplay >= 0 else { return }

        let newKilograms = UnitConversion.weight(parsedDisplay, from: preferredUnit, to: .kilograms)
        guard kilograms != newKilograms else { return }
        kilograms = newKilograms
        onCommit()
    }
}

private struct OptionalIntField: View {
    let title: String
    @Binding var value: Int?
    let onCommit: () -> Void
    var step: Int = 1

    @FocusState private var isFocused: Bool
    @State private var text: String = ""

    var body: some View {
        ZStack {
            TextField("—", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.body.monospacedDigit().weight(.medium))
                .padding(.horizontal, 29)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .accessibilityLabel(title)
                .focused($isFocused)
                .onAppear { syncFromValue() }
                .onChange(of: value) { _, _ in
                    guard !isFocused else { return }
                    syncFromValue()
                }
                .onChange(of: text) { _, text in
                    guard isFocused else { return }
                    updateValueWhileTyping(text)
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }

            HStack(spacing: 0) {
                RepeatStepButton(systemImage: "minus", accessibilityLabel: "Decrease \(title.lowercased())") {
                    adjust(by: -step)
                }
                Spacer(minLength: 0)
                RepeatStepButton(systemImage: "plus", accessibilityLabel: "Increase \(title.lowercased())") {
                    adjust(by: step)
                }
            }
        }
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func adjust(by delta: Int) {
        let current = Int(text) ?? (value ?? 0)
        let updated = max(0, current + delta)
        if updated == 0 {
            value = nil
            text = ""
        } else {
            value = updated
            text = "\(updated)"
        }
        onCommit()
    }

    private func syncFromValue() {
        if let value {
            text = "\(value)"
        } else {
            text = ""
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if value != nil {
                value = nil
                onCommit()
            }
            return
        }

        guard let parsed = Int(trimmed), parsed >= 0 else {
            syncFromValue()
            return
        }

        let newValue = parsed == 0 ? nil : parsed
        if value != newValue {
            value = newValue
            onCommit()
        }
    }

    private func updateValueWhileTyping(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let parsed = Int(trimmed),
              parsed >= 0 else { return }
        let newValue = parsed == 0 ? nil : parsed
        guard value != newValue else { return }
        value = newValue
        onCommit()
    }
}

private func parsedLocalizedDecimal(_ text: String) -> Double? {
    var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return nil }

    let locale = Locale.current
    if let groupingSeparator = locale.groupingSeparator, !groupingSeparator.isEmpty {
        normalized = normalized.replacingOccurrences(of: groupingSeparator, with: "")
    }
    if let decimalSeparator = locale.decimalSeparator,
       !decimalSeparator.isEmpty,
       decimalSeparator != "." {
        normalized = normalized.replacingOccurrences(of: decimalSeparator, with: ".")
    }
    return Double(normalized)
}

private struct WorkoutExercisePicker: View {
    @Environment(\.dismiss) private var dismiss

    let exercises: [Exercise]
    let title: String
    let onSelect: (Exercise) -> Void

    @State private var isCreatingExercise = false

    var body: some View {
        NavigationStack {
            ExerciseQuickAddList(
                exercises: exercises,
                isCreatingExercise: $isCreatingExercise,
                dismissOnSelect: true,
                onSelect: onSelect,
                onDismiss: { dismiss() }
            )
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New Exercise", systemImage: "plus") {
                        isCreatingExercise = true
                    }
                }
            }
        }
    }
}

extension TimeInterval {
    var formattedWorkoutClock: String {
        let total = max(0, Int(self))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
