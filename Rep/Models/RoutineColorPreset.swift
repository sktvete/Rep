import SwiftUI

enum RoutineColorPreset: String, CaseIterable, Identifiable, Sendable {
    case blue
    case indigo
    case purple
    case pink
    case orange
    case amber
    case green
    case teal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blue: "Blue"
        case .indigo: "Indigo"
        case .purple: "Purple"
        case .pink: "Pink"
        case .orange: "Orange"
        case .amber: "Amber"
        case .green: "Green"
        case .teal: "Teal"
        }
    }

    var color: Color {
        switch self {
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .orange: .orange
        case .amber: Color(red: 0.92, green: 0.58, blue: 0.06)
        case .green: .green
        case .teal: .teal
        }
    }
}
