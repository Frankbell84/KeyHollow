import SwiftUI

private enum VaultMediaNavigationPagerMetrics {
    static let minimumSwipeDistance: CGFloat = 56
    static let horizontalDominanceRatio: CGFloat = 1.15
    static let videoControlExclusionMinimumHeight: CGFloat = 140
    static let videoControlExclusionHeightRatio: CGFloat = 0.24
}

/// A single-surface pager for an application-owned active payload. The content
/// builder is invoked only for `queue.currentItem`; this add-on never builds
/// adjacent full-resolution pages or requests media on its own.
public struct VaultMediaNavigationPager<ActiveContent: View>: View {
    private let queue: VaultMediaNavigationQueue
    private let isNavigationEnabled: Bool
    private let onSelectionChange: (VaultMediaNavigationID) -> Void
    private let activeContent: (VaultMediaNavigationItem) -> ActiveContent

    public init(
        queue: VaultMediaNavigationQueue,
        isNavigationEnabled: Bool = true,
        onSelectionChange: @escaping (VaultMediaNavigationID) -> Void,
        @ViewBuilder activeContent: @escaping (VaultMediaNavigationItem) -> ActiveContent
    ) {
        self.queue = queue
        self.isNavigationEnabled = isNavigationEnabled
        self.onSelectionChange = onSelectionChange
        self.activeContent = activeContent
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                activeContent(queue.currentItem)
                    .id(queue.currentItem.id)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(
                    minimumDistance: VaultMediaNavigationPagerMetrics.minimumSwipeDistance
                )
                    .onEnded { value in
                        handleDrag(value, viewportHeight: geometry.size.height)
                    }
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            navigationBar
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 16) {
            navigationButton(
                direction: .previous,
                systemImage: "chevron.left",
                accessibilityLabel: "Previous item",
                isAvailable: queue.canNavigatePrevious
            )

            Spacer(minLength: 8)

            VStack(spacing: 2) {
                Text(queue.currentItem.accessibilityTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(queue.accessibilityPosition)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(queue.accessibilityLabel)
            .accessibilityValue(queue.accessibilityPosition)
            .accessibilityHint(
                isNavigationEnabled
                    ? "Swipe left or right, or adjust, to navigate media"
                    : "Navigation is temporarily unavailable"
            )
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    navigate(.next)
                case .decrement:
                    navigate(.previous)
                @unknown default:
                    break
                }
            }

            Spacer(minLength: 8)

            navigationButton(
                direction: .next,
                systemImage: "chevron.right",
                accessibilityLabel: "Next item",
                isAvailable: queue.canNavigateNext
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func navigationButton(
        direction: VaultMediaNavigationDirection,
        systemImage: String,
        accessibilityLabel: String,
        isAvailable: Bool
    ) -> some View {
        Button {
            navigate(direction)
        } label: {
            Image(systemName: systemImage)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(
            !isNavigationEnabled
                ? "Navigation is temporarily unavailable"
                : isAvailable
                    ? "Displays the adjacent media item"
                    : "No item available"
        )
        .disabled(!isNavigationEnabled || !isAvailable)
    }

    private func handleDrag(
        _ value: DragGesture.Value,
        viewportHeight: CGFloat
    ) {
        guard isNavigationEnabled else { return }

        // Native video controls own the lower playback region. Ignoring drags
        // that begin there prevents a scrub gesture from also changing pages,
        // while the rest of the video surface remains swipeable.
        if queue.currentItem.kind == .video {
            let excludedHeight = max(
                VaultMediaNavigationPagerMetrics.videoControlExclusionMinimumHeight,
                viewportHeight
                    * VaultMediaNavigationPagerMetrics.videoControlExclusionHeightRatio
            )
            guard value.startLocation.y < viewportHeight - excludedHeight else {
                return
            }
        }

        let horizontalDistance = value.translation.width
        let verticalDistance = value.translation.height
        guard abs(horizontalDistance) >= VaultMediaNavigationPagerMetrics.minimumSwipeDistance,
              abs(horizontalDistance) > abs(verticalDistance)
                * VaultMediaNavigationPagerMetrics.horizontalDominanceRatio else {
            return
        }

        navigate(horizontalDistance < 0 ? .next : .previous)
    }

    private func navigate(_ direction: VaultMediaNavigationDirection) {
        guard isNavigationEnabled else { return }
        guard let destination = queue.item(in: direction) else { return }
        onSelectionChange(destination.id)
    }
}
