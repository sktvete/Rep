import SwiftUI

struct RoutineColorPicker: View {
    @Binding var selection: RoutineColorPreset

    var body: some View {
        HStack(spacing: 10) {
            ForEach(RoutineColorPreset.allCases) { preset in
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        selection = preset
                    }
                } label: {
                    Circle()
                        .fill(preset.color)
                        .frame(width: 30, height: 30)
                        .overlay {
                            if selection == preset {
                                Image(systemName: "checkmark")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.2), radius: 1)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    selection == preset
                                        ? Color.primary.opacity(0.8)
                                        : Color.primary.opacity(0.12),
                                    lineWidth: selection == preset ? 2 : 0.5
                                )
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preset.displayName)
                .accessibilityAddTraits(selection == preset ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Routine color")
    }
}
