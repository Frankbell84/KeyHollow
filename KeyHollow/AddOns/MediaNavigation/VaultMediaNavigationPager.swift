import SwiftUI

private enum VaultMediaNavigationPagerMetrics {
    static let minimumSwipeDistance: CGFloat = 56
    static let horizontalDominanceRatio: CGFloat = 1.15
    static let videoControlExclusionMinimumHeight: CGFloat = 140
    static let videoControlExclusionHeightRatio: CGFloat = 0.24

    static func videoControlExclusionHeight(for viewportHeight: CGFloat) -> CGFloat {
        // A fixed portrait exclusion would consume the center of a short
        // landscape page once safe areas and the Done bar are accounted for.
        min(
            max(videoControlExclusionMinimumHeight,
                viewportHeight * videoControlExclusionHeightRatio),
            viewportHeight * 0.35
        )
    }
}

/// Keeps application chrome gestures away from AVKit's native playback and
/// fullscreen controls. Images have no native control overlay, so their single
/// tap remains available to reveal or hide KeyHollow's action header.
public enum VaultMediaChromeInteractionPolicy {
    public static func acceptsContentTap(for kind: VaultMediaNavigationKind) -> Bool {
        kind == .image
    }
}

/// Close from the content, leaving the screen edge and playback controls to
/// their existing owners. An incomplete or primarily horizontal drag is inert.
public enum VaultMediaDismissalGesturePolicy {
    public static func accepts(
        translation: CGSize,
        startY: CGFloat,
        viewportHeight: CGFloat
    ) -> Bool {
        let bottomExclusion = VaultMediaNavigationPagerMetrics
            .videoControlExclusionHeight(for: viewportHeight)
        return startY >= 44
            && startY < viewportHeight - bottomExclusion
            && translation.height >= 96
            && translation.height > abs(translation.width) * 1.5
    }
}

/// A single-surface pager for an application-owned active payload. The content
/// builder is invoked only for `queue.currentItem`; this add-on never builds
/// adjacent full-resolution pages or requests media on its own.
public struct VaultMediaNavigationPager<ActiveContent: View>: View {
    private let queue: VaultMediaNavigationQueue
    private let isNavigationEnabled: Bool
    private let onSelectionChange: (VaultMediaNavigationID) -> Void
    private let onDismissalRequested: () -> Void
    private let onChromeToggleRequested: () -> Void
    private let activeContent: (VaultMediaNavigationItem) -> ActiveContent

    public init(
        queue: VaultMediaNavigationQueue,
        isNavigationEnabled: Bool = true,
        onSelectionChange: @escaping (VaultMediaNavigationID) -> Void,
        onDismissalRequested: @escaping () -> Void = {},
        onChromeToggleRequested: @escaping () -> Void = {},
        @ViewBuilder activeContent: @escaping (VaultMediaNavigationItem) -> ActiveContent
    ) {
        self.queue = queue
        self.isNavigationEnabled = isNavigationEnabled
        self.onSelectionChange = onSelectionChange
        self.onDismissalRequested = onDismissalRequested
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

        if queue.currentItem.kind == .video,
           VaultMediaDismissalGesturePolicy.accepts(
               translation: value.translation,
               startY: value.startLocation.y,
               viewportHeight: viewportHeight
           ) {
            onDismissalRequested()
            return
        }

        // Native video controls own the lower playback region. Ignoring drags
        // that begin there prevents a scrub gesture from also changing pages,
        // while the rest of the video surface remains swipeable.
        if queue.currentItem.kind == .video {
            let excludedHeight = VaultMediaNavigationPagerMetrics
                .videoControlExclusionHeight(for: viewportHeight)
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
