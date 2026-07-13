import SwiftData
import SwiftUI

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
    let onClose: () -> Void

    @State private var selectedExerciseID: UUID?
    @State private var restTimer: WorkoutRestTimerViewModel
    @State private var isShowingExercisePicker = false
    @State private var isShowingExerciseOrder = false
    @State private var replacementTarget: WorkoutExercise?
    @State private var formReferenceExercise: Exercise?
    @State private var isShowingFinishConfirmation = false
    @State private var isShowingDiscardConfirmation = false
    @State private var isShowingRemoveExerciseConfirmation = false
    @State private var errorMessage: String?

    init(session: WorkoutSession, onClose: @escaping () -> Void = {}) {
        self.session = session
        self.onClose = onClose
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if restTimer.isPresented {
                    WorkoutRestTimerBanner(restTimer: restTimer)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: restTimer.isPresented)
        }
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
            ActiveWorkoutRestTimerBridge.register {
                restTimer.start(seconds: 5, nextExerciseName: "Development test")
            }
        }
        .onDisappear {
            ActiveWorkoutRestTimerBridge.unregister()
        }
        .onChange(of: settings.first?.hapticsEnabled) { _, _ in
            updateRestTimerHapticsPreference()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            restTimer.reconcileAfterForeground()
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
        .sheet(item: $replacementTarget) { target in
            WorkoutExercisePicker(
                exercises: availableExercises.filter { $0.id != target.exercise?.id },
                title: "Replace exercise"
            ) { exercise in
                replace(target, with: exercise)
            }
        }
        .sheet(item: $formReferenceExercise) { exercise in
            ExerciseDetailView(exercise: exercise)
        }
        .sheet(isPresented: $isShowingExerciseOrder) {
            WorkoutExerciseOrderEditor(session: session) {
                persist()
            }
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
                if let currentExercise { removeExercise(currentExercise) }
            }
            Button("Cancel", role: .cancel) {}
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
    }

    private func updateRestTimerHapticsPreference() {
        restTimer.shouldPlayCompletionHaptic = { hapticsEnabled }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Close workout", systemImage: "chevron.down") {
                persist()
                onClose()
                dismiss()
            }
            .labelStyle(.iconOnly)
            .accessibilityHint("Keeps the workout active so you can resume it later")
        }

        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text(session.name)
                    .font(.headline)
                    .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(session.duration(at: context.date).formattedWorkoutDuration)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Elapsed time \(session.duration(at: context.date).formattedWorkoutDuration)")
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
                if shouldOfferDiscard {
                    isShowingDiscardConfirmation = true
                } else {
                    isShowingFinishConfirmation = true
                }
            }
            .fontWeight(.semibold)
        }
    }

    private var shouldOfferDiscard: Bool {
        session.duration < 60 || session.exercises.isEmpty
    }

    private var discardWorkoutMessage: String {
        if session.exercises.isEmpty {
            return "You haven't added any exercises yet. Nothing will be saved to your history."
        }
        return "This workout just started. Nothing will be saved to your history."
    }

    private func workoutContent(_ workoutExercise: WorkoutExercise) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    exerciseNavigation

                    currentExerciseHeader(workoutExercise)
                    previousPerformance(for: workoutExercise)
                    setsCard(workoutExercise, proxy: proxy)

                    Button {
                        addSet(to: workoutExercise)
                    } label: {
                        Label("Add set", systemImage: "plus")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .repSecondaryButton()

                    Button {
                        isShowingExercisePicker = true
                    } label: {
                        Label("Add exercise", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .repSoftScrollEdges()
        }
    }

    private var exerciseNavigation: some View {
        ScrollView(.horizontal) {
            RepGlassEffectGroup(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(orderedExercises) { workoutExercise in
                    let isSelected = workoutExercise.id == currentExercise?.id
                    let completeCount = workoutExercise.sets.filter(\.isCompleted).count
                    let isComplete = !workoutExercise.sets.isEmpty && completeCount == workoutExercise.sets.count

                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            selectedExerciseID = workoutExercise.id
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isComplete {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(isSelected ? .white : .green)
                                    .imageScale(.small)
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text(workoutExercise.exercise?.name ?? "Exercise")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(workoutExercise.isSkipped ? "Skipped" : isComplete ? "Complete" : "\(completeCount)/\(workoutExercise.sets.count) sets")
                                    .font(.caption2)
                                    .foregroundStyle(isSelected ? Color.white.opacity(0.82) : .secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(minHeight: 44)
                        .foregroundStyle(isSelected ? .white : .primary)
                        .contentShape(.capsule)
                        .repGlassControl(
                            tint: isSelected ? RepVisualSystem.tint : (isComplete ? Color.green.opacity(0.12) : nil),
                            cornerRadius: 99
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(workoutExercise.exercise?.name ?? "Exercise"), \(isComplete ? "complete" : "\(completeCount) of \(workoutExercise.sets.count) sets complete")")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }

                    Button("Reorder exercises", systemImage: "arrow.up.arrow.down") {
                        isShowingExerciseOrder = true
                    }
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .repGlassControl(cornerRadius: 99)
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 1, for: .scrollContent)
    }

    private func currentExerciseHeader(_ workoutExercise: WorkoutExercise) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(workoutExercise.exercise?.name ?? "Unavailable exercise")
                    .font(.title2.bold())
                if let exercise = workoutExercise.exercise {
                    Text("\(exercise.primaryMuscleGroup.displayName) · \(exercise.equipment.displayName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Menu("Exercise options", systemImage: "ellipsis.circle") {
                if let exercise = workoutExercise.exercise {
                    Button("View form reference", systemImage: "play.rectangle") {
                        formReferenceExercise = exercise
                    }
                    Divider()
                }
                Button("Replace for this workout", systemImage: "arrow.triangle.2.circlepath") {
                    replacementTarget = workoutExercise
                }
                Button(workoutExercise.isSkipped ? "Unskip exercise" : "Skip for now", systemImage: "forward") {
                    workoutExercise.isSkipped.toggle()
                    persist()
                    if workoutExercise.isSkipped { selectNextExercise(after: workoutExercise) }
                }
                Button("Reorder exercises", systemImage: "arrow.up.arrow.down") {
                    isShowingExerciseOrder = true
                }
                Divider()
                Button("Remove exercise", systemImage: "trash", role: .destructive) {
                    isShowingRemoveExerciseConfirmation = true
                }
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .frame(width: 44, height: 44)
            .repGlassControl(cornerRadius: 99)
        }
    }

    @ViewBuilder
    private func previousPerformance(for workoutExercise: WorkoutExercise) -> some View {
        if let previous = previousWorkoutExercise(for: workoutExercise) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Previous")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                let completedSets = previous.exercise.orderedSets.filter(\.isCompleted)
                if completedSets.isEmpty {
                    Text("No completed sets")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(completedSets.map(shortSetDescription).joined(separator: "  ·  "))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(previous.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .repSurface(cornerRadius: RepVisualSystem.controlRadius)
            .accessibilityElement(children: .combine)
        }
    }

    private func setsCard(_ workoutExercise: WorkoutExercise, proxy: ScrollViewProxy) -> some View {
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
                    Divider().padding(.leading, 42)
                    ActiveWorkoutSetRow(
                        set: set,
                        measurementType: workoutExercise.exercise?.measurementType ?? .weightAndRepetitions,
                        preferredUnit: preferredUnit,
                        onEdit: persist,
                        onToggleCompletion: {
                            toggleCompletion(of: set, in: workoutExercise)
                            if set.isCompleted,
                               let nextSet = workoutExercise.orderedSets.first(where: { !$0.isCompleted }) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo(nextSet.id, anchor: .center)
                                }
                            }
                        },
                        onDelete: { removeSet(set, from: workoutExercise) }
                    )
                    .id(set.id)
                }
            }
        }
        .repSurface(cornerRadius: RepVisualSystem.cardRadius)
        .clipShape(.rect(cornerRadius: RepVisualSystem.cardRadius))
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
        let set = WorkoutSet(orderIndex: 0)
        let workoutExercise = WorkoutExercise(
            exercise: exercise,
            orderIndex: session.exercises.count,
            defaultRestSeconds: defaultRestSeconds,
            sets: [set]
        )
        session.exercises.append(workoutExercise)
        session.normalizeExerciseOrder()
        session.updatedAt = .now
        selectedExerciseID = workoutExercise.id
        persist()
    }

    private func replace(_ workoutExercise: WorkoutExercise, with exercise: Exercise) {
        workoutExercise.substitutionForExerciseID = workoutExercise.exercise?.id
        workoutExercise.exercise = exercise
        session.updatedAt = .now
        persist()
    }

    private func removeExercise(_ workoutExercise: WorkoutExercise) {
        session.exercises.removeAll { $0.id == workoutExercise.id }
        session.normalizeExerciseOrder()
        session.updatedAt = .now
        modelContext.delete(workoutExercise)
        selectedExerciseID = session.orderedExercises.first?.id
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
        if let nextExercise = upcoming.first(where: { !$0.isSkipped }) {
            return nextExercise.exercise?.name ?? "Next exercise"
        }

        return orderedExercises.first(where: { !$0.isSkipped })?.exercise?.name ?? "Next exercise"
    }

    private func selectNextExercise(after workoutExercise: WorkoutExercise) {
        guard let index = orderedExercises.firstIndex(where: { $0.id == workoutExercise.id }) else { return }
        let remaining = orderedExercises.suffix(from: min(index + 1, orderedExercises.endIndex))
        selectedExerciseID = remaining.first(where: { !$0.isSkipped })?.id
            ?? orderedExercises.first(where: { !$0.isSkipped })?.id
            ?? workoutExercise.id
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
            return "\(displayed.formatted(.number.precision(.fractionLength(0...2)))) × \(repetitions)"
        }
        if let repetitions = set.repetitions { return "\(repetitions) reps" }
        if let duration = set.durationSeconds { return "\(duration)s" }
        if let distance = set.distance { return "\(distance.formatted(.number.precision(.fractionLength(0...2)))) m" }
        return "Done"
    }

    private func finishWorkout() {
        do {
            try WorkoutService(context: modelContext).finish(session)
            restTimer.skip()
            onClose()
            dismiss()
        } catch {
            AppLog.persistenceFailure(operation: "Finish workout", error: error)
            errorMessage = error.localizedDescription
        }
    }

    private func discardWorkout() {
        do {
            try WorkoutService(context: modelContext).abandon(session)
            restTimer.skip()
            onClose()
            dismiss()
        } catch {
            AppLog.persistenceFailure(operation: "Discard workout", error: error)
            errorMessage = error.localizedDescription
        }
    }

    private func persist() {
        do {
            try modelContext.save()
        } catch {
            AppLog.persistenceFailure(operation: "Save active workout", error: error)
            errorMessage = error.localizedDescription
        }
    }
}

private struct SetColumnHeader: View {
    let measurementType: MeasurementType
    let preferredUnit: WeightUnit

    var body: some View {
        HStack(spacing: 8) {
            Text("Set")
                .frame(width: 34)
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
            Color.clear.frame(width: 48, height: 1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .accessibilityHidden(true)
    }
}

private struct ActiveWorkoutSetRow: View {
    @Bindable var set: WorkoutSet
    let measurementType: MeasurementType
    let preferredUnit: WeightUnit
    let onEdit: () -> Void
    let onToggleCompletion: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Set type", selection: $set.setTypeRaw) {
                    ForEach(WorkoutSetType.allCases) { type in
                        Text(type.displayName).tag(type.rawValue)
                    }
                }
            } label: {
                Text("\(set.orderIndex + 1)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .frame(width: 34, height: 44)
                    .background(set.setType == .working ? Color.clear : Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            .foregroundStyle(.primary)
            .accessibilityLabel("Set \(set.orderIndex + 1), \(set.setType.displayName)")

            metricFields

            Button(action: onToggleCompletion) {
                ZStack {
                    Circle()
                        .fill(set.isCompleted ? RepVisualSystem.tint : Color.primary.opacity(0.075))
                        .frame(width: 38, height: 38)
                    Image(systemName: set.isCompleted ? "checkmark" : "circle")
                        .font(.body.weight(.bold))
                        .foregroundStyle(set.isCompleted ? .white : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set.isCompleted ? "Reopen set \(set.orderIndex + 1)" : "Complete set \(set.orderIndex + 1)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(set.isCompleted ? RepVisualSystem.tint.opacity(0.045) : .clear)
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .onChange(of: set.weight) { _, _ in touchAndSave() }
        .onChange(of: set.repetitions) { _, _ in touchAndSave() }
        .onChange(of: set.durationSeconds) { _, _ in touchAndSave() }
        .onChange(of: set.distance) { _, _ in touchAndSave() }
        .onChange(of: set.assistanceWeight) { _, _ in touchAndSave() }
        .onChange(of: set.setTypeRaw) { _, _ in touchAndSave() }
        .contextMenu {
            Button("Delete set", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    @ViewBuilder
    private var metricFields: some View {
        switch measurementType {
        case .weightAndRepetitions, .bodyweightPlusAddedWeight, .custom:
            OptionalWeightField(title: "Weight", kilograms: $set.weight, preferredUnit: preferredUnit)
            OptionalIntField(title: "Repetitions", value: $set.repetitions)
        case .repetitionsOnly, .bodyweightAndRepetitions:
            OptionalIntField(title: "Repetitions", value: $set.repetitions)
        case .duration:
            OptionalIntField(title: "Duration in seconds", value: $set.durationSeconds)
        case .weightAndDuration:
            OptionalWeightField(title: "Weight", kilograms: $set.weight, preferredUnit: preferredUnit)
            OptionalIntField(title: "Duration in seconds", value: $set.durationSeconds)
        case .distanceAndDuration:
            OptionalDoubleField(title: "Distance in meters", value: $set.distance)
            OptionalIntField(title: "Duration in seconds", value: $set.durationSeconds)
        case .assistedBodyweight:
            OptionalWeightField(title: "Assistance weight", kilograms: $set.assistanceWeight, preferredUnit: preferredUnit)
            OptionalIntField(title: "Repetitions", value: $set.repetitions)
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

    var body: some View {
        TextField("—", value: $value, format: .number.precision(.fractionLength(0...2)))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .font(.body.monospacedDigit().weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 9))
            .accessibilityLabel(title)
    }
}

private struct OptionalWeightField: View {
    let title: String
    @Binding var kilograms: Double?
    let preferredUnit: WeightUnit

    private var weightStep: Double { 5 }

    private var displayedValue: Binding<Double?> {
        Binding(
            get: {
                kilograms.map { UnitConversion.weight($0, from: .kilograms, to: preferredUnit) }
            },
            set: { newValue in
                kilograms = newValue.map { UnitConversion.weight($0, from: preferredUnit, to: .kilograms) }
            }
        )
    }

    var body: some View {
        ZStack {
            TextField("—", value: displayedValue, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.body.monospacedDigit().weight(.medium))
                .padding(.horizontal, 34)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityLabel("\(title) in \(preferredUnit.displayName.lowercased())")

            HStack(spacing: 0) {
                RepeatStepButton(systemImage: "minus", accessibilityLabel: "Decrease \(title.lowercased())") {
                    adjustWeight(by: -weightStep)
                }
                Spacer(minLength: 0)
                RepeatStepButton(systemImage: "plus", accessibilityLabel: "Increase \(title.lowercased())") {
                    adjustWeight(by: weightStep)
                }
            }
        }
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 9))
    }

    private func adjustWeight(by displayDelta: Double) {
        let currentDisplay = kilograms.map { UnitConversion.weight($0, from: .kilograms, to: preferredUnit) } ?? 0
        let newDisplay = max(0, currentDisplay + displayDelta)
        guard newDisplay > 0 else {
            kilograms = nil
            return
        }
        kilograms = UnitConversion.weight(newDisplay, from: preferredUnit, to: .kilograms)
    }
}

private struct OptionalIntField: View {
    let title: String
    @Binding var value: Int?
    var step: Int = 1

    var body: some View {
        ZStack {
            TextField("—", value: $value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.body.monospacedDigit().weight(.medium))
                .padding(.horizontal, 34)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityLabel(title)

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
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 9))
    }

    private func adjust(by delta: Int) {
        let current = value ?? 0
        let updated = max(0, current + delta)
        value = updated == 0 ? nil : updated
    }
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

private struct WorkoutExerciseOrderEditor: View {
    @Environment(\.dismiss) private var dismiss
    let session: WorkoutSession
    let onChange: () -> Void

    @State private var orderedExercises: [WorkoutExercise]

    init(session: WorkoutSession, onChange: @escaping () -> Void) {
        self.session = session
        self.onChange = onChange
        _orderedExercises = State(initialValue: session.orderedExercises)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(orderedExercises) { workoutExercise in
                    Label(workoutExercise.exercise?.name ?? "Unavailable exercise", systemImage: "line.3.horizontal")
                }
                .onMove { source, destination in
                    orderedExercises.move(fromOffsets: source, toOffset: destination)
                    for (index, workoutExercise) in orderedExercises.enumerated() {
                        workoutExercise.orderIndex = index
                    }
                    session.updatedAt = .now
                    onChange()
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Exercise order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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
