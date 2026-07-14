import SwiftUI

struct ExercisePickerRow: View {
    let exercise: Exercise
    let onSelect: () -> Void
    let onShowDetails: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onShowDetails) {
                ExerciseMediaThumbnail(exercise: exercise)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show details for \(exercise.name)")

            Button(action: onSelect) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text("\(exercise.primaryMuscleGroup.displayName) · \(exercise.equipment.displayName)")
                            .font(.caption)
                            .repSecondaryText()
                            .lineLimit(1)
                    }

                    Spacer(minLength: 2)

                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(exercise.name)")
            .accessibilityHint("Adds this exercise to your workout or routine")
        }
    }
}

/// A deterministic local placeholder. Exercise media is shown only after Rep has a
/// redistribution license and serves assets from Rep-controlled storage.
struct ExerciseMediaThumbnail: View {
    let exercise: Exercise
    var size: CGFloat = 58

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0.055)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: symbolName)
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(.tint)
        }
        .frame(width: size, height: size)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: max(10, size * 0.2)))
        .overlay {
            RoundedRectangle(cornerRadius: max(10, size * 0.2))
                .strokeBorder(Color.primary.opacity(0.06))
        }
        .accessibilityHidden(true)
    }

    private var symbolName: String {
        switch exercise.primaryMuscleGroup {
        case .chest, .back, .shoulders, .biceps, .triceps:
            "figure.strengthtraining.traditional"
        case .quadriceps, .hamstrings, .glutes, .calves:
            "figure.strengthtraining.functional"
        case .core:
            "figure.core.training"
        case .fullBody, .other:
            "dumbbell.fill"
        }
    }
}

struct ExerciseDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let exercise: Exercise

    private var sourceURL: URL? {
        guard let value = exercise.sourceURLString,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else { return nil }
        return url
    }

    private var instructionSteps: [String] {
        ExerciseInstructionFormatter.steps(from: exercise.instructions)
    }

    private var userNotes: String? {
        guard let value = exercise.userNotes?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    media

                    VStack(alignment: .leading, spacing: 8) {
                        Text(exercise.name)
                            .font(.largeTitle.bold())
                            .fixedSize(horizontal: false, vertical: true)

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 14) {
                                Label(muscleSummary, systemImage: "figure.strengthtraining.traditional")
                                Label(exercise.equipment.displayName, systemImage: "dumbbell")
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Label(muscleSummary, systemImage: "figure.strengthtraining.traditional")
                                Label(exercise.equipment.displayName, systemImage: "dumbbell")
                            }
                        }
                        .font(.subheadline.weight(.medium))
                        .repSecondaryText()
                    }

                    instructions

                    if let userNotes {
                        notes(userNotes)
                    }

                    if let sourceURL {
                        Link(destination: sourceURL) {
                            HStack(spacing: 10) {
                                Image(systemName: "safari")
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Catalog source")
                                        .font(.caption)
                                        .repSecondaryText()
                                    Text(exercise.sourceName ?? "View source")
                                        .font(.subheadline.weight(.semibold))
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.semibold))
                            }
                            .padding()
                            .repSurface(cornerRadius: RepVisualSystem.controlRadius)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens in your browser")
                    }
                }
                .padding()
                .padding(.bottom, 24)
            }
            .background(RepScreenBackground())
            .navigationTitle("Exercise Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var muscleSummary: String {
        let muscles = [exercise.primaryMuscleGroup] + exercise.secondaryMuscleGroups
        return muscles
            .reduce(into: [MuscleGroup]()) { result, muscle in
                if !result.contains(muscle) { result.append(muscle) }
            }
            .map(\.displayName)
            .joined(separator: ", ")
    }

    private var media: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.tint)
            Text("Movement media isn’t bundled yet")
                .font(.subheadline.weight(.medium))
                .repSecondaryText()
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .aspectRatio(4 / 3, contentMode: .fit)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(.rect(cornerRadius: RepVisualSystem.cardRadius))
    }

    @ViewBuilder
    private var instructions: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("How to perform")
                    .font(.title3.bold())

                if !instructionSteps.isEmpty {
                    Text("\(instructionSteps.count) steps")
                        .font(.subheadline)
                        .repSecondaryText()
                }
            }

            if instructionSteps.isEmpty {
                Text("Form guidance is not available for this exercise yet.")
                    .font(.subheadline)
                    .repSecondaryText()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(instructionSteps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            Button {
                                ExerciseStepSpeechService.shared.speakStep(number: index + 1, text: step)
                            } label: {
                                Text("\(index + 1)")
                                    .font(.caption.bold().monospacedDigit())
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Color.accentColor, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Speak step \(index + 1)")

                            Text(step)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Step \(index + 1), \(step)")

                        if index < instructionSteps.count - 1 {
                            Divider()
                                .padding(.leading, 42)
                        }
                    }
                }
            }

            Text("Use this as a general form guide. Adjust setup and technique for your body, equipment, and goals.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .repSurface(cornerRadius: RepVisualSystem.cardRadius)
    }

    private func notes(_ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.title3.bold())
            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .repSurface(cornerRadius: RepVisualSystem.cardRadius)
    }
}
