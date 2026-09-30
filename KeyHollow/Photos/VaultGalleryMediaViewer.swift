import SwiftUI
import KeyHollowMediaNavigationAddOn

/// Presentation only. Composition supplies readiness and owns every operation,
/// active payload, task and cleanup barrier through the existing callbacks.
struct VaultGalleryMediaViewer<ActiveContent: View>: View {
    enum Action {
        case dismiss
        case toggleChrome
        case saveImage
        case delete
    }

    let queue: VaultMediaNavigationQueue
    let isNavigationEnabled: Bool
    let isBusy: Bool
    let isChromeVisible: Bool
    let isImageSaveEnabled: Bool
    @Binding var previewMessage: String?
    let onSelectionChange: (VaultMediaNavigationID) -> Void
    let perform: (Action) -> Void
    let activeContent: (VaultMediaNavigationItem) -> ActiveContent

    var body: some View {
        VaultMediaNavigationPager(
            queue: queue,
            isNavigationEnabled: isNavigationEnabled,
            onSelectionChange: onSelectionChange,
            onDismissalRequested: { perform(.dismiss) },
            onChromeToggleRequested: {
                // The module-owned video session owns the native AVKit
                // controls. Only image pages use a content
                // tap to reveal or hide KeyHollow's action overlay.
                guard VaultMediaChromeInteractionPolicy.acceptsContentTap(
                    for: queue.currentItem.kind
                ) else { return }
                perform(.toggleChrome)
            }
        ) { item in
            activeContent(item)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if queue.currentItem.kind == .video {
                toolbar
            }
        }
        .overlay(alignment: .top) {
            if isChromeVisible && queue.currentItem.kind == .image {
                toolbar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isChromeVisible)
        .alert("KeyHollow", isPresented: Binding(
            get: { previewMessage != nil },
            set: { if !$0 { previewMessage = nil } }
        )) {
            Button("OK") { previewMessage = nil }
        } message: {
            Text(previewMessage ?? "")
        }
    }

    private var toolbar: some View {
        ZStack {
            VStack(spacing: 1) {
                Text(queue.currentItem.accessibilityTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(queue.accessibilityPosition)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 96)

            HStack(spacing: 18) {
                Button("Done") { perform(.dismiss) }
                    .disabled(isBusy)

                Spacer()

                if isBusy {
                    ProgressView()
                        .tint(.white)
                } else if queue.currentItem.kind == .image {
                    Button {
                        perform(.saveImage)
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Save to Photos")
                    .disabled(!isImageSaveEnabled)
                }

                Button(role: .destructive) {
                    perform(.delete)
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete from Vault")
                .disabled(isBusy)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

}

/// The existing failed/opening presentation, without loading authority.
struct VaultGalleryMediaLoadState: View {
    let isFailed: Bool
    let isInteractionDisabled: Bool
    let onRetry: () -> Void

    @ViewBuilder
    var body: some View {
        if isFailed {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                Text("Unable to Open")
                    .font(.headline)
                Button("Try Again") {
                    onRetry()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isInteractionDisabled)
            }
            .padding()
            .foregroundStyle(.white)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .accessibilityElement(children: .contain)
        } else {
            ProgressView("Opening…")
                .padding()
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: 12)
                )
        }
    }

}
