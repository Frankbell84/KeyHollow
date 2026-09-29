import SwiftUI
import UIKit
import KeyHollowMediaNavigationAddOn
import KeyHollowSecurePreviewAddOn

@MainActor
struct VaultMediaImagePage: View {
    @ObservedObject var coordinator: VaultImagePreviewCoordinator

    let item: VaultMediaNavigationItem
    let placeholder: UIImage?
    let isFailed: Bool
    let loadGeneration: UInt64
    let isInteractionDisabled: Bool
    let onRetry: () -> Void
    let onImageWillAttach: () -> Bool
    let onImageReleased: () -> Void
    let onZoomStateChange: (Bool) -> Void

    @State private var showsLoadingIndicator = false

    var body: some View {
        ZStack {
            if let active = coordinator.active,
               active.id == item.id {
                VaultSecureZoomableImageSurface(
                    renderedImage: active.preview.displayImage,
                    accessibilityLabel: item.accessibilityTitle,
                    onImageWillAttach: onImageWillAttach,
                    onImageReleased: onImageReleased,
                    onZoomStateChange: onZoomStateChange
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                placeholderView

                if isFailed {
                    failureView
                } else if showsLoadingIndicator {
                    ProgressView("Opening…")
                        .padding()
                        .background(
                            .regularMaterial,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                }
            }
        }
        .task(id: loadGeneration) {
            showsLoadingIndicator = false
            guard coordinator.active?.id != item.id, !isFailed else { return }
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  coordinator.active?.id != item.id,
                  !isFailed else { return }
            showsLoadingIndicator = true
        }
        .onChange(of: coordinator.active?.id) { _, activeID in
            if activeID == item.id {
                showsLoadingIndicator = false
            }
        }
        .onChange(of: isFailed) { _, failed in
            if failed {
                showsLoadingIndicator = false
            }
        }
    }

    @ViewBuilder
    private var placeholderView: some View {
        if let placeholder {
            Image(uiImage: placeholder)
                .resizable()
                .scaledToFit()
                .opacity(0.72)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private var failureView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
            Text("Unable to Open")
                .font(.headline)
            Button("Try Again", action: onRetry)
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
    }
}
