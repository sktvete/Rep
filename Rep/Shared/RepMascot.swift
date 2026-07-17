import SwiftUI

enum RepMascotPose: String {
    case flex = "MascotFlex"
    case welcome = "MascotWelcome"
    case celebrate = "MascotCelebrate"
    case empty = "MascotEmpty"
    case rest = "MascotRest"
}

struct RepMascot: View {
    let pose: RepMascotPose
    var size: CGFloat = 140

    var body: some View {
        Image(pose.rawValue)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct RepMascotEmptyState: View {
    let pose: RepMascotPose
    let title: String
    let description: String
    var actionTitle: String? = nil
    var actionSystemImage: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            VStack(spacing: 14) {
                RepMascot(pose: pose, size: 148)
                Text(title)
                    .font(.title2.bold())
            }
        } description: {
            Text(description)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, systemImage: actionSystemImage ?? "plus", action: action)
                    .repPrimaryButton()
                    .controlSize(.large)
            }
        }
    }
}
