import SwiftUI

struct RoutineColorPicker: View {
    @Binding var selection: RoutineColorPreset

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(RoutineColorPreset.allCases) { preset in
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        selection = preset
                    }
                } label: {
                    Circle()
                        .fill(preset.color)
                        .frame(width: 36, height: 36)
                        .overlay {
                            if selection == preset {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.2), radius: 1)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    selection == preset
                                        ? Color.primary.opacity(0.75)
                                        : Color.primary.opacity(0.12),
                                    lineWidth: selection == preset ? 2 : 0.5
                                )
                        }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preset.displayName)
                .accessibilityAddTraits(selection == preset ? .isSelected : [])
            }
        }
        .accessibilityLabel("Routine color")
    }
}
