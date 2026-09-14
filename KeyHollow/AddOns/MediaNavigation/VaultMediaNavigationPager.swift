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
    private let onChromeToggleRequested: () -> Void
    private let activeContent: (VaultMediaNavigationItem) -> ActiveContent

    public init(
        queue: VaultMediaNavigationQueue,
        isNavigationEnabled: Bool = true,
        onSelectionChange: @escaping (VaultMediaNavigationID) -> Void,
        onChromeToggleRequested: @escaping () -> Void = {},
        @ViewBuilder activeContent: @escaping (VaultMediaNavigationItem) -> ActiveContent
    ) {
        self.queue = queue
        self.isNavigationEnabled = isNavigationEnabled
        self.onSelectionChange = onSelectionChange
        self.onChromeToggleRequested = onChromeToggleRequested
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
            .simultaneousGesture(
                TapGesture().onEnded(onChromeToggleRequested)
            )
            .accessibilityAction(named: "Previous item") {
                navigate(.previous)
            }
            .accessibilityAction(named: "Next item") {
                navigate(.next)
            }
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
        }
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
