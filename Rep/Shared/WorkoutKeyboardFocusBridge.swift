import Foundation
import Observation

/// Tracks whether an active-workout set field is focused so chrome (tab bar / rest
/// banner) can hide while typing.
@MainActor
@Observable
final class WorkoutKeyboardFocusBridge {
    static let shared = WorkoutKeyboardFocusBridge()

    private(set) var isSetFieldFocused = false
    private var focusedFieldCount = 0

    func setFocused(_ focused: Bool) {
        if focused {
            focusedFieldCount += 1
        } else {
            focusedFieldCount = max(0, focusedFieldCount - 1)
        }
        isSetFieldFocused = focusedFieldCount > 0
    }

    func reset() {
        focusedFieldCount = 0
        isSetFieldFocused = false
    }
}
