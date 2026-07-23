import SwiftData
import SwiftUI

struct RoutineCreationFlowView: View {
    fileprivate enum Destination: Hashable {
        case guided
        case blank
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            RoutineCreationMenuView()
                .navigationDestination(for: Destination.self) { destination in
                    switch destination {
                    case .guided:
                        GuidedRoutineBuilderView(onSaved: { dismiss() })
                    case .blank:
                        CreateRoutineView(
                            embeddedInNavigationStack: true,
                            onDismiss: { dismiss() }
                        )
                    }
                }
                .navigationTitle("New Routine")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
    }
}

private struct RoutineCreationMenuView: View {
    var body: some View {
        ZStack {
            RepScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("How do you want to build?")
                            .font(.title2.bold())
                        Text("Get a balanced starting point or choose everything yourself.")
                            .font(.subheadline)
                            .repSecondaryText()
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    NavigationLink(value: RoutineCreationFlowView.Destination.guided) {
                        GuidedBuilderHeroCard()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Build a routine, recommended")
                    .accessibilityHint("Creates a guided routine from three choices per exercise")

                    NavigationLink(value: RoutineCreationFlowView.Destination.blank) {
                        HStack(spacing: 14) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.tint)
                                .frame(width: 42, height: 42)
                                .repGlassControl(cornerRadius: 13, interactive: false)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Start blank")
                                    .font(.headline)
                                Text("Search the full catalog and set it up manually")
                                    .font(.subheadline)
                                    .repSecondaryText()
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 8)

                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(16)
                        .repSurface(cornerRadius: 18, shadowRadius: 5, shadowY: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the manual routine editor")

                    Label("Every generated routine can be reordered and edited before saving.", systemImage: "checkmark.seal")
                        .font(.footnote)
                        .repSecondaryText()
                        .padding(.horizontal, 4)
                }
                .padding(20)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct GuidedBuilderHeroCard: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [Color.accentColor, Color.accentColor.opacity(0.72), .indigo.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { context, size in
                context.fill(
                    Path(ellipseIn: CGRect(x: size.width - 122, y: -78, width: 180, height: 180)),
                    with: .color(.white.opacity(0.12))
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: 44, y: 116, width: 104, height: 104)),
                    with: .color(.white.opacity(0.08))
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("RECOMMENDED", systemImage: "sparkles")
                        .font(.caption2.bold())
                        .tracking(0.7)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.16), in: Capsule())

                    Spacer()

                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                }

                Spacer(minLength: 10)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Build a routine")
                        .font(.title2.bold())
                    Text("Choose Legs, Push, Pull or Core, then pick one of three exercises for every movement.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 14) {
                    Label("About 55 min", systemImage: "clock")
                    Label("Guided", systemImage: "wand.and.stars")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
            }
            .foregroundStyle(.white)
            .padding(20)
        }
        .frame(minHeight: 220)
        .clipShape(.rect(cornerRadius: RepVisualSystem.cardRadius))
        .contentShape(.rect(cornerRadius: RepVisualSystem.cardRadius))
        .shadow(color: Color.accentColor.opacity(0.24), radius: 16, y: 8)
        .overlay {
            RoundedRectangle(cornerRadius: RepVisualSystem.cardRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.75)
        }
    }
}

private struct GuidedRoutineBuilderView: View {
    private enum Phase {
        case setup
        case exercises
        case review
    }

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Exercise> { $0.isArchived == false }, sort: \Exercise.name)
    private var exercises: [Exercise]

    @State private var phase: Phase = .setup
    @State private var focus: GuidedRoutineFocus = .legs
    @State private var experience: GuidedRoutineExperience = .beginner
    @State private var equipmentProfile: GuidedRoutineEquipmentProfile = .fullGym
    @State private var duration: GuidedRoutineDuration = .standard
    @State private var currentSlotIndex = 0
    @State private var optionsBySlot: [String: [GuidedResolvedExerciseOption]] = [:]
    @State private var selectedExerciseIDs: [String: UUID] = [:]
    @State private var orderedSlotIDs: [String] = []
    @State private var routineName = GuidedRoutineFocus.legs.title
    @State private var colorPreset: RoutineColorPreset = .blue
    @State private var detailExercise: Exercise?
    @State private var isBrowsingAllExercises = false
    @State private var errorMessage: String?
    @FocusState private var isNameFocused: Bool

    let onSaved: () -> Void

    private var template: GuidedRoutineTemplate {
        GuidedRoutineCatalog.template(for: focus)
    }

    private var currentSlot: GuidedMovementSlot? {
        template.slots.indices.contains(currentSlotIndex) ? template.slots[currentSlotIndex] : nil
    }

    private var visiblePrefetchExercises: [Exercise] {
        let indices = [currentSlotIndex, min(currentSlotIndex + 1, template.slots.count - 1)]
        return indices.flatMap { index -> [Exercise] in
            guard template.slots.indices.contains(index) else { return [] }
            return optionsBySlot[template.slots[index].id, default: []].map(\.exercise)
        }
    }

    private var thumbnailPrefetchSignature: Int {
        var hasher = Hasher()
        hasher.combine(currentSlotIndex)
        hasher.combine(visiblePrefetchExercises.map(\.id))
        switch phase {
        case .setup: hasher.combine(0)
        case .exercises: hasher.combine(1)
        case .review: hasher.combine(2)
        }
        return hasher.finalize()
    }

    var body: some View {
        Group {
            switch phase {
            case .setup:
                setupScreen
            case .exercises:
                exerciseScreen
            case .review:
                reviewScreen
            }
        }
        .background(RepScreenBackground().ignoresSafeArea())
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(phase != .setup)
        .toolbar {
            if phase != .setup {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        navigateBack()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
        }
        .sheet(item: $detailExercise) { exercise in
            ExerciseDetailView(exercise: exercise)
        }
        .sheet(isPresented: $isBrowsingAllExercises) {
            ExercisePickerView { exercise in
                chooseBrowsedExercise(exercise)
                isBrowsingAllExercises = false
            }
        }
        .alert("Couldn’t build routine", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
        .exerciseThumbnailScope {
            ExerciseThumbnailPrefetch.sources(from: visiblePrefetchExercises, thumbnailSize: 58)
        }
        .task(id: thumbnailPrefetchSignature) {
            scheduleBuilderThumbnailWarm()
        }
        .onDisappear {
            ExerciseThumbnailIdlePreloader.shared.cancel()
        }
    }

    private var navigationTitle: String {
        switch phase {
        case .setup: "Build a Routine"
        case .exercises: focus.title
        case .review: "Review Routine"
        }
    }

    private var setupScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Make it yours")
                        .font(.title.bold())
                    Text("Rep will keep every workout balanced while you choose the exercises you prefer.")
                        .font(.subheadline)
                        .repSecondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }

                setupSection("What are you training?") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(GuidedRoutineFocus.allCases) { item in
                            focusButton(item)
                        }
                    }
                }

                setupSection("Experience") {
                    Picker("Experience", selection: $experience) {
                        ForEach(GuidedRoutineExperience.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                setupSection("Available equipment") {
                    HStack(spacing: 10) {
                        ForEach(GuidedRoutineEquipmentProfile.allCases) { profile in
                            equipmentButton(profile)
                        }
                    }
                    Text("We’ll prioritize this equipment and use the nearest suitable option when needed.")
                        .font(.caption)
                        .repSecondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }

                setupSection("Workout length") {
                    Picker("Workout length", selection: $duration) {
                        ForEach(GuidedRoutineDuration.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding(20)
            .padding(.bottom, 84)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            primaryFooterButton("Choose Exercises", systemImage: "arrow.right") {
                prepareExercises()
            }
        }
        .onChange(of: focus) { _, newFocus in
            routineName = newFocus.title
            colorPreset = defaultColor(for: newFocus)
        }
    }

    private func setupSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func focusButton(_ item: GuidedRoutineFocus) -> some View {
        let isSelected = focus == item
        return Button {
            focus = item
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: item.systemImage)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                Text(item.title)
                    .font(.headline)
                Text(item.summary)
                    .font(.caption)
                    .repSecondaryText()
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color.clear,
                in: .rect(cornerRadius: 18)
            )
            .repSurface(cornerRadius: 18, shadowRadius: isSelected ? 7 : 3, shadowY: 2)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.72) : Color.clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func equipmentButton(_ profile: GuidedRoutineEquipmentProfile) -> some View {
        let isSelected = equipmentProfile == profile
        return Button {
            equipmentProfile = profile
        } label: {
            VStack(spacing: 7) {
                Image(systemName: profile.systemImage)
                    .font(.body.weight(.semibold))
                Text(profile.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color.clear,
                in: .rect(cornerRadius: 15)
            )
            .repGlassControl(tint: isSelected ? Color.accentColor.opacity(0.15) : nil, cornerRadius: 15)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var exerciseScreen: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Text("Exercise \(currentSlotIndex + 1) of \(template.slots.count)")
                        .font(.caption.weight(.semibold))
                        .repSecondaryText()
                    Spacer()
                    Text("≈ \(duration.estimatedMinutes) min")
                        .font(.caption.weight(.semibold))
                        .repSecondaryText()
                }

                ProgressView(value: Double(currentSlotIndex + 1), total: Double(template.slots.count))
                    .tint(colorPreset.color)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)

            TabView(selection: $currentSlotIndex) {
                ForEach(Array(template.slots.enumerated()), id: \.element.id) { index, slot in
                    GuidedExerciseChoicePage(
                        slot: slot,
                        options: optionsBySlot[slot.id, default: []],
                        selectedExerciseID: selectedExerciseIDs[slot.id],
                        color: colorPreset.color,
                        onSelect: {
                            ExerciseThumbnailIdlePreloader.shared.cancel()
                            selectedExerciseIDs[slot.id] = $0.id
                            scheduleBuilderThumbnailWarm()
                        },
                        onDetails: {
                            ExerciseThumbnailIdlePreloader.shared.cancel()
                            detailExercise = $0
                        },
                        onBrowseAll: {
                            ExerciseThumbnailIdlePreloader.shared.cancel()
                            currentSlotIndex = index
                            isBrowsingAllExercises = true
                        }
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in ExerciseThumbnailIdlePreloader.shared.cancel() }
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    previousExercisePage()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .repSecondaryButton()
                .controlSize(.large)

                Button {
                    nextExercisePage()
                } label: {
                    Label(
                        currentSlotIndex == template.slots.count - 1 ? "Review" : "Next",
                        systemImage: currentSlotIndex == template.slots.count - 1 ? "checkmark" : "chevron.right"
                    )
                    .frame(maxWidth: .infinity)
                }
                .repPrimaryButton()
                .tint(colorPreset.color)
                .controlSize(.large)
                .disabled(currentSlot.flatMap { selectedExerciseIDs[$0.id] } == nil)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .guidedStickyFooterBackdrop()
        }
    }

    private var reviewScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(colorPreset.color)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your routine is ready")
                            .font(.title2.bold())
                        Text("\(orderedSlotIDs.count) exercises · about \(duration.estimatedMinutes) minutes")
                            .font(.subheadline)
                            .repSecondaryText()
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(.caption.weight(.semibold))
                            .repSecondaryText()
                        TextField("Routine name", text: $routineName)
                            .font(.title3.weight(.semibold))
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .focused($isNameFocused)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Color")
                            .font(.caption.weight(.semibold))
                            .repSecondaryText()
                        RoutineColorPicker(selection: $colorPreset)
                    }
                }
                .padding(16)
                .repSurface(cornerRadius: 18, shadowRadius: 5, shadowY: 2)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Exercises")
                            .font(.headline)
                        Spacer()
                        Label("Hold and drag", systemImage: "line.3.horizontal")
                            .font(.caption)
                            .repSecondaryText()
                    }

                    RepLiveReorderStack(
                        items: $orderedSlotIDs,
                        id: \.self,
                        axis: .vertical,
                        spacing: 10,
                        onInteraction: { ExerciseThumbnailIdlePreloader.shared.cancel() },
                        onCommit: { _ in scheduleBuilderThumbnailWarm() }
                    ) { slotID, _ in
                        if let index = orderedSlotIDs.firstIndex(of: slotID),
                           let slot = template.slots.first(where: { $0.id == slotID }),
                           let exercise = selectedExercise(for: slotID) {
                            guidedReviewRow(slot: slot, exercise: exercise, index: index)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(20)
            .padding(.bottom, 84)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .scrollClipDisabled()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            primaryFooterButton("Save Routine", systemImage: "checkmark") {
                saveRoutine()
            }
            .disabled(routineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func guidedReviewRow(
        slot: GuidedMovementSlot,
        exercise: Exercise,
        index: Int
    ) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(colorPreset.color)
                .frame(width: 26, height: 26)
                .background(colorPreset.color.opacity(0.12), in: Circle())

            ExerciseMediaThumbnail(exercise: exercise, size: 42, listIndex: index)

            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Text("\(slot.setCount(for: duration)) × \(slot.repetitions) · \(formatRest(slot.restSeconds)) rest")
                    .font(.caption)
                    .repSecondaryText()
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)
            }

            Spacer(minLength: 4)

            HStack(spacing: 8) {
                Button {
                    if let index = template.slots.firstIndex(where: { $0.id == slot.id }) {
                        currentSlotIndex = index
                        withAnimation(.snappy(duration: 0.22)) { phase = .exercises }
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 30, height: 30)
                        .foregroundStyle(colorPreset.color)
                        .background(colorPreset.color.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Replace \(exercise.name)")
                .accessibilityHint("Returns to this movement’s exercise choices")

                Image(systemName: "line.3.horizontal")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(12)
        .repSurface(cornerRadius: 16, shadowRadius: 3, shadowY: 1)
    }

    private func primaryFooterButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .repPrimaryButton()
        .tint(colorPreset.color)
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .guidedStickyFooterBackdrop()
    }

    private func prepareExercises() {
        ExerciseThumbnailIdlePreloader.shared.cancel()
        do {
            let resolvedPairs = try template.slots.map { slot in
                let options = try GuidedExerciseResolver.options(
                    for: slot,
                    experience: experience,
                    equipmentProfile: equipmentProfile,
                    exercises: exercises
                )
                return (slot.id, options)
            }
            optionsBySlot = Dictionary(uniqueKeysWithValues: resolvedPairs)
            selectedExerciseIDs = Dictionary(uniqueKeysWithValues: resolvedPairs.map { slotID, options in
                (slotID, options[0].exercise.id)
            })
            orderedSlotIDs = template.slots.map(\.id)
            currentSlotIndex = 0
            withAnimation(.snappy(duration: 0.24)) { phase = .exercises }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func chooseBrowsedExercise(_ exercise: Exercise) {
        guard let slot = currentSlot else { return }
        var options = optionsBySlot[slot.id, default: []]
        let replacement = GuidedResolvedExerciseOption(
            candidateID: "browse-\(exercise.id.uuidString)",
            exercise: exercise,
            reason: "Chosen from the full catalog",
            isRecommended: false
        )
        options.removeAll { $0.exercise.id == exercise.id }
        if options.count >= 3 {
            options[2] = replacement
        } else {
            options.append(replacement)
        }
        optionsBySlot[slot.id] = Array(options.prefix(3))
        selectedExerciseIDs[slot.id] = exercise.id
    }

    private func previousExercisePage() {
        ExerciseThumbnailIdlePreloader.shared.cancel()
        if currentSlotIndex > 0 {
            withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.9)) {
                currentSlotIndex -= 1
            }
        } else {
            withAnimation(.snappy(duration: 0.22)) { phase = .setup }
        }
    }

    private func nextExercisePage() {
        ExerciseThumbnailIdlePreloader.shared.cancel()
        if currentSlotIndex < template.slots.count - 1 {
            withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.9)) {
                currentSlotIndex += 1
            }
        } else {
            isNameFocused = false
            withAnimation(.snappy(duration: 0.22)) { phase = .review }
        }
    }

    private func navigateBack() {
        ExerciseThumbnailIdlePreloader.shared.cancel()
        switch phase {
        case .setup:
            break
        case .exercises:
            previousExercisePage()
        case .review:
            currentSlotIndex = max(0, template.slots.count - 1)
            withAnimation(.snappy(duration: 0.22)) { phase = .exercises }
        }
    }

    private func selectedExercise(for slotID: String) -> Exercise? {
        guard let exerciseID = selectedExerciseIDs[slotID] else { return nil }
        return exercises.first { $0.id == exerciseID }
    }

    private func saveRoutine() {
        ExerciseThumbnailIdlePreloader.shared.cancel()
        let selections = orderedSlotIDs.compactMap { slotID -> GuidedRoutineSelection? in
            guard let slot = template.slots.first(where: { $0.id == slotID }),
                  let exercise = selectedExercise(for: slotID) else { return nil }
            return GuidedRoutineSelection(slot: slot, exercise: exercise)
        }

        guard selections.count == template.slots.count else {
            errorMessage = "Choose one exercise for every movement before saving."
            return
        }

        let routine = GuidedRoutineFactory.makeRoutine(
            name: routineName,
            colorPreset: colorPreset,
            duration: duration,
            selections: selections
        )
        modelContext.insert(routine)
        do {
            try modelContext.save()
            onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func defaultColor(for focus: GuidedRoutineFocus) -> RoutineColorPreset {
        switch focus {
        case .legs: .blue
        case .push: .orange
        case .pull: .indigo
        case .core: .teal
        }
    }

    private func formatRest(_ seconds: Int) -> String {
        if seconds >= 60 {
            let minutes = seconds / 60
            let remainder = seconds % 60
            return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
        }
        return "\(seconds)s"
    }

    private func scheduleBuilderThumbnailWarm() {
        let sources = ExerciseThumbnailPrefetch.sources(
            from: visiblePrefetchExercises,
            thumbnailSize: 58
        )
        ExerciseThumbnailIdlePreloader.shared.schedule(sources: sources)
    }
}

private struct GuidedExerciseChoicePage: View {
    let slot: GuidedMovementSlot
    let options: [GuidedResolvedExerciseOption]
    let selectedExerciseID: UUID?
    let color: Color
    let onSelect: (Exercise) -> Void
    let onDetails: (Exercise) -> Void
    let onBrowseAll: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(slot.title)
                        .font(.title2.bold())
                    Text(slot.purpose)
                        .font(.subheadline)
                        .repSecondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        optionRow(option, listIndex: index)
                    }
                }

                Button(action: onBrowseAll) {
                    Label("Browse all exercises", systemImage: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
                .repGlassControl(cornerRadius: 15)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 92)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
    }

    private func optionRow(
        _ option: GuidedResolvedExerciseOption,
        listIndex: Int
    ) -> some View {
        let isSelected = selectedExerciseID == option.exercise.id
        return HStack(spacing: 13) {
            Button {
                onDetails(option.exercise)
            } label: {
                ExerciseMediaThumbnail(exercise: option.exercise, size: 58, listIndex: listIndex)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, color)
                            .background(.black.opacity(0.24), in: Circle())
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show instructions for \(option.exercise.name)")

            Button {
                onSelect(option.exercise)
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(option.exercise.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)

                            if option.isRecommended {
                                Text("Top pick")
                                    .font(.caption2.bold())
                                    .foregroundStyle(color)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(color.opacity(0.12), in: Capsule())
                            }
                        }

                        Text(option.reason)
                            .font(.subheadline)
                            .repSecondaryText()
                            .lineLimit(2)

                        Text(option.exercise.equipment.displayName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? color : Color.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(option.exercise.name), \(option.reason)")
            .accessibilityHint("Selects this exercise")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .padding(13)
        .background(
            isSelected ? color.opacity(0.11) : Color.clear,
            in: .rect(cornerRadius: 18)
        )
        .repSurface(cornerRadius: 18, shadowRadius: isSelected ? 7 : 3, shadowY: 2)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? color.opacity(0.72) : Color.clear, lineWidth: 1.5)
        }
    }
}

private struct GuidedStickyFooterBackdrop: ViewModifier {
    @Environment(\.repThemeSettings) private var themeSettings
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.background {
            LinearGradient(
                stops: [
                    .init(color: canvasColor.opacity(0), location: 0),
                    .init(color: canvasColor.opacity(0.94), location: 0.32),
                    .init(color: canvasColor, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.top, -32)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }

    private var canvasColor: Color {
        themeSettings.resolved(for: colorScheme).canvasColor
    }
}

private extension View {
    func guidedStickyFooterBackdrop() -> some View {
        modifier(GuidedStickyFooterBackdrop())
    }
}
