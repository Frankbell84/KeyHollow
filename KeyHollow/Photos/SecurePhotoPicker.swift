import SwiftUI
@preconcurrency import PhotosUI
@preconcurrency import UIKit
import KeyHollowPhotosAdapter

enum PickedVaultPhotoEvent: @unchecked Sendable {
    case started(total: Int)
    case photo(PickedVaultPhoto)
    case video(PickedVaultVideo)
    case failed
    case finished
}

struct SecurePhotoPickerProgressState: Equatable, Sendable {
    let total: Int
    private(set) var completed: Int = 0

    init(total: Int) {
        self.total = max(0, total)
    }

    var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(completed) / Double(total))
    }

    var statusText: String {
        "Encrypting \(completed) of \(total)"
    }

    mutating func advance() {
        completed = min(total, completed + 1)
    }
}

@MainActor
private final class SecurePhotoPickerProgressOverlay {
    private let container = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let statusLabel = UILabel()

    init(attachingTo parent: UIView, progress: SecurePhotoPickerProgressState) {
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.cornerRadius = 14
        container.clipsToBounds = true
        container.isAccessibilityElement = true
        container.accessibilityTraits = [.updatesFrequently]

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textColor = .white
        statusLabel.textAlignment = .center

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progressTintColor = .systemBlue
        progressView.trackTintColor = UIColor.white.withAlphaComponent(0.25)

        let stack = UIStackView(arrangedSubviews: [statusLabel, progressView])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 14
        container.contentView.addSubview(stack)
        parent.addSubview(container)

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: parent.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: parent.centerYAnchor),
            container.widthAnchor.constraint(lessThanOrEqualTo: parent.widthAnchor, multiplier: 0.82),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
            stack.leadingAnchor.constraint(equalTo: container.contentView.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: container.contentView.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: container.contentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: container.contentView.bottomAnchor, constant: -20),
        ])
        update(progress)
    }

    func update(_ progress: SecurePhotoPickerProgressState) {
        statusLabel.text = progress.statusText
        progressView.setProgress(Float(progress.fractionCompleted), animated: true)
        container.accessibilityLabel = "Importing photos and videos"
        container.accessibilityValue = progress.statusText
    }

    func remove() {
        container.removeFromSuperview()
    }
}

struct SecurePhotoPicker: UIViewControllerRepresentable {
    /// Full-resolution images are decoded, normalized, handed to encrypted
    /// storage, and released one at a time. Never increase this without a
    /// device-memory test and a corresponding bounded-pipeline test.
    static let maximumResidentFullSizePhotos = SequentialPhotoBatchProcessor.maximumConcurrentItems

    let selectionLimit: Int
    let onPicked: @MainActor (PickedVaultPhotoEvent) async -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = selectionLimit
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    static func dismantleUIViewController(
        _ uiViewController: PHPickerViewController,
        coordinator: Coordinator
    ) {
        coordinator.cancel()
    }

    @MainActor
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPicked: @MainActor (PickedVaultPhotoEvent) async -> Void
        private var processingTask: Task<Void, Never>?
        private var progressOverlay: SecurePhotoPickerProgressOverlay?

        init(onPicked: @escaping @MainActor (PickedVaultPhotoEvent) async -> Void) {
            self.onPicked = onPicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard processingTask == nil else { return }
            guard !results.isEmpty else {
                picker.dismiss(animated: true)
                return
            }

            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.prepare()
            impact.impactOccurred(intensity: 0.85)
            picker.view.isUserInteractionEnabled = false
            var progress = SecurePhotoPickerProgressState(total: results.count)
            let overlay = SecurePhotoPickerProgressOverlay(
                attachingTo: picker.view,
                progress: progress
            )
            progressOverlay = overlay
            UIAccessibility.post(
                notification: .announcement,
                argument: "Import started. \(results.count) selected."
            )

            processingTask = Task { @MainActor [onPicked, weak self] in
                await onPicked(.started(total: results.count))

                await SequentialPhotoBatchProcessor.process(
                    results,
                    load: ApplePhotoPickerItemLoader.loadMedia,
                    consume: { media in
                        // Awaiting the consumer is the memory/disk back-pressure:
                        // encrypted storage completes before the next full item is loaded.
                        switch media {
                        case .photo(let photo):
                            await onPicked(.photo(photo))
                        case .video(let video):
                            await onPicked(.video(video))
                            video.discard()
                        }
                        progress.advance()
                        overlay.update(progress)
                    },
                    didFail: {
                        await onPicked(.failed)
                        progress.advance()
                        overlay.update(progress)
                    }
                )

                guard !Task.isCancelled else { return }
                await onPicked(.finished)
                let completionFeedback = UINotificationFeedbackGenerator()
                completionFeedback.notificationOccurred(.success)
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "Import finished."
                )
                overlay.remove()
                self?.progressOverlay = nil
                picker.dismiss(animated: true)
            }
        }

        func cancel() {
            processingTask?.cancel()
            processingTask = nil
            progressOverlay?.remove()
            progressOverlay = nil
        }
    }
}

