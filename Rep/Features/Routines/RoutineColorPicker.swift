import SwiftUI

struct RoutineColorPicker: View {
    @Binding var selection: RoutineColorPreset

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(RoutineColorPreset.allCases) { preset in
                    Button {
                        selection = preset
                    } label: {
                        Circle()
                            .fill(preset.color)
                            .frame(width: 34, height: 34)
                            .overlay {
                                if selection == preset {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                        .shadow(color: .black.opacity(0.2), radius: 1)
                                }
                            }
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        selection == preset ? Color.primary.opacity(0.75) : Color.primary.opacity(0.12),
                                        lineWidth: selection == preset ? 2 : 0.5
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset.displayName)
                    .accessibilityAddTraits(selection == preset ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Routine color")
    }
}
