import SwiftData
import SwiftUI

struct TrainingProgressView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case exercise = "Exercise"
        case bodyweight = "Bodyweight"

        var id: Self { self }
    }

    @State private var selectedSection: Section = .exercise

    var body: some View {
        NavigationStack {
            ZStack {
                RepScreenBackground()

                VStack(spacing: 0) {
                    Picker("Progress category", selection: $selectedSection) {
                        ForEach(Section.allCases) { section in
                            Text(section.rawValue).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, RepVisualSystem.pageSpacing)
                    .padding(.bottom, 10)

                    switch selectedSection {
                    case .exercise:
                        ExerciseProgressView()
                            .id(Section.exercise)
                    case .bodyweight:
                        BodyweightProgressView()
                            .id(Section.bodyweight)
                    }
                }
            }
            .navigationTitle("Progress")
        }
    }
}
