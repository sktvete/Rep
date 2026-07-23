import SwiftUI
import UIKit

/// Reorders the views that are already on screen instead of asking the system to
/// manufacture a drag preview. The moving child remains the same SwiftUI view, so
/// thumbnails, controls, and local state stay attached while its neighbors shuffle.
@MainActor
struct RepLiveReorderStack<Item, ID, RowContent>: View where ID: Hashable & Sendable, RowContent: View {
    @Binding private var items: [Item]

    private let id: KeyPath<Item, ID>
    private let axis: Axis
    private let spacing: CGFloat
    private let hapticsEnabled: Bool
    private let onInteraction: () -> Void
    private let onStationaryHold: ((ID) -> Void)?
    private let onCommit: ([Item]) -> Void
    private let rowContent: (Item, Bool) -> RowContent

    @State private var activeID: ID?
    @State private var movingCenter: CGFloat?
    @State private var dragOriginCenter: CGFloat = 0
    @State private var measuredSizes: [ID: CGSize] = [:]
    @State private var startingItems: [Item] = []
    @State private var hasDragged = false
    @State private var stationaryActionFired = false
    @State private var stationaryTask: Task<Void, Never>?

    init(
        items: Binding<[Item]>,
        id: KeyPath<Item, ID>,
        axis: Axis = .vertical,
        spacing: CGFloat = 10,
        hapticsEnabled: Bool = true,
        onInteraction: @escaping () -> Void = {},
        onStationaryHold: ((ID) -> Void)? = nil,
        onCommit: @escaping ([Item]) -> Void = { _ in },
        @ViewBuilder content: @escaping (Item, Bool) -> RowContent
    ) {
        _items = items
        self.id = id
        self.axis = axis
        self.spacing = spacing
        self.hapticsEnabled = hapticsEnabled
        self.onInteraction = onInteraction
        self.onStationaryHold = onStationaryHold
        self.onCommit = onCommit
        rowContent = content
    }

    var body: some View {
        RepLiveReorderLayout(
            axis: axis,
            spacing: spacing,
            activeIndex: activeID.flatMap { activeID in
                items.firstIndex { $0[keyPath: id] == activeID }
            },
            movingCenter: movingCenter
        ) {
            ForEach(items, id: id) { item in
                let itemID = item[keyPath: id]
                let isMoving = activeID == itemID

                rowContent(item, isMoving)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: RepLiveReorderSizePreferenceKey<ID>.self,
                                value: [itemID: proxy.size]
                            )
                        }
                    }
                    .scaleEffect(isMoving ? 1.015 : 1)
                    .shadow(
                        color: isMoving ? Color.black.opacity(0.16) : .clear,
                        radius: isMoving ? 11 : 0,
                        y: isMoving ? 6 : 0
                    )
                    .zIndex(isMoving ? 1_000 : 0)
                    .contentShape(Rectangle())
                    .highPriorityGesture(reorderGesture(for: itemID))
                    .animation(.snappy(duration: 0.12), value: isMoving)
            }
        }
        .onPreferenceChange(RepLiveReorderSizePreferenceKey<ID>.self) { sizes in
            measuredSizes.merge(sizes) { _, latest in latest }
        }
        .onDisappear {
            stationaryTask?.cancel()
            guard activeID != nil, !startingItems.isEmpty else { return }
            items = startingItems
            resetGestureState()
        }
        .accessibilityAction(named: "Finish reordering") {
            finishGesture()
        }
    }

    private func reorderGesture(for itemID: ID) -> some Gesture {
        LongPressGesture(minimumDuration: 0.14, maximumDistance: 14)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { state in
                switch state {
                case .first(true):
                    beginLift(for: itemID)
                case .second(true, let dragValue):
                    guard let dragValue else { return }
                    updateDrag(for: itemID, value: dragValue)
                default:
                    break
                }
            }
            .onEnded { _ in
                finishGesture()
            }
    }

    private func beginLift(for itemID: ID) {
        guard !stationaryActionFired else { return }
        if activeID == nil {
            activeID = itemID
            startingItems = items
            hasDragged = false
            onInteraction()
            if hapticsEnabled {
                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.72)
            }
            scheduleStationaryAction(for: itemID)
        }
    }

    private func updateDrag(for itemID: ID, value: DragGesture.Value) {
        guard !stationaryActionFired else { return }
        beginLift(for: itemID)
        guard activeID == itemID else { return }

        let movement = hypot(value.translation.width, value.translation.height)
        if !hasDragged, movement > 6 {
            hasDragged = true
            stationaryTask?.cancel()
            dragOriginCenter = slotCenter(for: itemID)
        }
        guard hasDragged else { return }

        let translation = axis == .vertical ? value.translation.height : value.translation.width
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            movingCenter = dragOriginCenter + translation
        }

        moveAcrossCrossedMidpoint(itemID: itemID)
    }

    private func moveAcrossCrossedMidpoint(itemID: ID) {
        guard let movingCenter,
              let currentIndex = items.firstIndex(where: { $0[keyPath: id] == itemID })
        else { return }

        let centers = slotCenters()
        guard centers.indices.contains(currentIndex) else { return }
        let hysteresis: CGFloat = 8
        var destination = currentIndex

        if movingCenter > centers[currentIndex], currentIndex + 1 < centers.count {
            for index in (currentIndex + 1)..<centers.count where movingCenter > centers[index] + hysteresis {
                destination = index
            }
        } else if movingCenter < centers[currentIndex], currentIndex > 0 {
            for index in stride(from: currentIndex - 1, through: 0, by: -1)
                where movingCenter < centers[index] - hysteresis {
                destination = index
            }
        }

        guard destination != currentIndex else { return }
        var reordered = items
        let movingItem = reordered.remove(at: currentIndex)
        reordered.insert(movingItem, at: destination)

        withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.9)) {
            items = reordered
        }
        if hapticsEnabled {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func scheduleStationaryAction(for itemID: ID) {
        stationaryTask?.cancel()
        guard let onStationaryHold else { return }
        stationaryTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(310))
            guard !Task.isCancelled,
                  activeID == itemID,
                  !hasDragged,
                  !stationaryActionFired
            else { return }

            stationaryActionFired = true
            if hapticsEnabled {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.72)
            }
            onStationaryHold(itemID)
            activeID = nil
            movingCenter = nil
        }
    }

    private func finishGesture() {
        stationaryTask?.cancel()
        if hasDragged {
            onCommit(items)
            if hapticsEnabled {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.65)
            }
        }
        resetGestureState()
    }

    private func resetGestureState() {
        activeID = nil
        movingCenter = nil
        dragOriginCenter = 0
        startingItems = []
        hasDragged = false
        stationaryActionFired = false
        stationaryTask = nil
    }

    private func slotCenter(for itemID: ID) -> CGFloat {
        guard let index = items.firstIndex(where: { $0[keyPath: id] == itemID }) else { return 0 }
        let centers = slotCenters()
        return centers.indices.contains(index) ? centers[index] : 0
    }

    private func slotCenters() -> [CGFloat] {
        var cursor: CGFloat = 0
        return items.map { item in
            let key = item[keyPath: id]
            let size = measuredSizes[key] ?? CGSize(width: 44, height: 44)
            let extent = axis == .vertical ? size.height : size.width
            let center = cursor + extent / 2
            cursor += extent + spacing
            return center
        }
    }

}

private struct RepLiveReorderLayout: Layout {
    let axis: Axis
    let spacing: CGFloat
    let activeIndex: Int?
    let movingCenter: CGFloat?

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let sizes = measuredSubviewSizes(proposal: proposal, subviews: subviews)
        guard !sizes.isEmpty else { return .zero }

        if axis == .vertical {
            return CGSize(
                width: proposal.width ?? sizes.map(\.width).max() ?? 0,
                height: sizes.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, sizes.count - 1))
            )
        }
        return CGSize(
            width: sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(0, sizes.count - 1)),
            height: proposal.height ?? sizes.map(\.height).max() ?? 0
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let sizes = measuredSubviewSizes(proposal: ProposedViewSize(bounds.size), subviews: subviews)
        var cursor = axis == .vertical ? bounds.minY : bounds.minX

        for (index, subview) in subviews.enumerated() {
            let size = sizes[index]
            let extent = axis == .vertical ? size.height : size.width
            let slotCenter = cursor + extent / 2
            let isActive = index == activeIndex
            let placedMovingCenter: CGFloat? = if isActive, let movingCenter {
                (axis == .vertical ? bounds.minY : bounds.minX) + movingCenter
            } else {
                nil
            }

            if axis == .vertical {
                subview.place(
                    at: CGPoint(x: bounds.midX, y: placedMovingCenter ?? slotCenter),
                    anchor: .center,
                    proposal: ProposedViewSize(width: bounds.width, height: size.height)
                )
            } else {
                subview.place(
                    at: CGPoint(x: placedMovingCenter ?? slotCenter, y: bounds.midY),
                    anchor: .center,
                    proposal: ProposedViewSize(width: size.width, height: bounds.height)
                )
            }
            cursor += extent + spacing
        }
    }

    private func measuredSubviewSizes(proposal: ProposedViewSize, subviews: Subviews) -> [CGSize] {
        subviews.map { subview in
            if axis == .vertical {
                subview.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
            } else {
                subview.sizeThatFits(ProposedViewSize(width: nil, height: proposal.height))
            }
        }
    }
}

private struct RepLiveReorderSizePreferenceKey<ID: Hashable & Sendable>: PreferenceKey {
    static var defaultValue: [ID: CGSize] { [:] }

    static func reduce(
        value: inout [ID: CGSize],
        nextValue: () -> [ID: CGSize]
    ) {
        value.merge(nextValue()) { _, latest in latest }
    }
}
