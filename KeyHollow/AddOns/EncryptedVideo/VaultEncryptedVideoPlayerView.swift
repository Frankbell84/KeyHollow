import AVFoundation
import AVKit
import Foundation
import SwiftUI

/// Kept separate from the SwiftUI state transition so teardown can be verified
/// directly and remains idempotent on every dismissal path.
@MainActor
enum VaultEncryptedVideoPlayerLifecycle {
    static func release(_ player: AVPlayer?) {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
    }
}

enum VaultEncryptedVideoPlayerFailurePolicy {
    static func indicatesFailure(_ status: AVPlayerItem.Status) -> Bool {
        status == .failed
    }
}

/// Keeps protected playback on the device and inside KeyHollow's lifecycle.
/// The settings live in one testable policy instead of depending on AVKit's
/// permissive defaults.
@MainActor
enum VaultEncryptedVideoPlayerSecurityPolicy {
    static func configure(_ player: AVPlayer) {
        player.allowsExternalPlayback = false
        player.usesExternalPlaybackWhileExternalScreenIsActive = false
    }

    static func configure(_ controller: AVPlayerViewController) {
        controller.allowsPictureInPicturePlayback = false
        controller.canStartPictureInPictureAutomaticallyFromInline = false
    }
}

private struct VaultRestrictedVideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        VaultEncryptedVideoPlayerSecurityPolicy.configure(controller)
        controller.player = player
        return controller
    }

    func updateUIViewController(
        _ controller: AVPlayerViewController,
        context: Context
    ) {
        VaultEncryptedVideoPlayerSecurityPolicy.configure(controller)
        if controller.player !== player {
            controller.player = player
        }
    }

    static func dismantleUIViewController(
        _ controller: AVPlayerViewController,
        coordinator: Void
    ) {
        controller.player = nil
    }
}

/// AVPlayerItem is intentionally contained in this narrowly scoped monitor.
/// AVFoundation owns its synchronization; callers receive only a Sendable
/// Boolean result. This lets strict-concurrency tasks race the two independent
/// failure channels without moving application state between executors.
@MainActor
final class VaultEncryptedVideoPlayerFailureMonitor: @unchecked Sendable {
    typealias StatusProvider = () -> AVPlayerItem.Status
    typealias PlaybackEndFailureWaiter = () async -> Bool

    private let statusProvider: StatusProvider
    private let playbackEndFailureWaiter: PlaybackEndFailureWaiter

    init(item: AVPlayerItem) {
        statusProvider = { item.status }
        playbackEndFailureWaiter = {
            let failures = NotificationCenter.default.notifications(
                named: AVPlayerItem.failedToPlayToEndTimeNotification,
                object: item
            ).map { _ in () }

            for await _ in failures {
                return !Task.isCancelled
            }
            return false
        }
    }

    init(
        statusProvider: @escaping StatusProvider,
        playbackEndFailureWaiter: @escaping PlaybackEndFailureWaiter
    ) {
        self.statusProvider = statusProvider
        self.playbackEndFailureWaiter = playbackEndFailureWaiter
    }

    func waitForFailure() async -> Bool {
        await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            group.addTask { [self] in
                await waitForFailedStatus()
            }
            group.addTask { [self] in
                await waitForPlaybackEndFailure()
            }

            while let didFail = await group.next() {
                if didFail {
                    group.cancelAll()
                    return true
                }
            }
            return false
        }
    }

    private func waitForFailedStatus() async -> Bool {
        while !Task.isCancelled {
            if VaultEncryptedVideoPlayerFailurePolicy.indicatesFailure(
                statusProvider()
            ) {
                return true
            }

            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return false
            }
        }
        return false
    }

    private func waitForPlaybackEndFailure() async -> Bool {
        await playbackEndFailureWaiter()
    }
}

/// Native, module-owned playback for one validated local video. The
/// application retains ownership of the temporary file and removes it after
/// this surface closes or the unlocked vault session ends.
@MainActor
public struct VaultEncryptedVideoPlayerView: View {
    private let playback: VaultPreparedVideoPlayback
    private let onPlayerWillAttach: () -> Bool
    private let onPlayerReleased: () -> Void
    private let onDismiss: () -> Void
    private let onFailure: ((VaultPreparedVideoPlaybackError) -> Void)?

    @State private var player: AVPlayer?

    public init(
        playback: VaultPreparedVideoPlayback,
        onPlayerWillAttach: @escaping () -> Bool = { true },
        onPlayerReleased: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void,
        onFailure: ((VaultPreparedVideoPlaybackError) -> Void)? = nil
    ) {
        self.playback = playback
        self.onPlayerWillAttach = onPlayerWillAttach
        self.onPlayerReleased = onPlayerReleased
        self.onDismiss = onDismiss
        self.onFailure = onFailure
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VaultRestrictedVideoPlayerView(player: player)
                    .accessibilityLabel(playback.descriptor.displayName)
            } else {
                ProgressView()
                    .tint(.white)
                    .accessibilityLabel("Preparing encrypted video")
            }
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Button("Done", action: dismiss)

                Spacer()

                Text(playback.descriptor.displayName)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                // Keeps the title centered relative to the leading control.
                Color.clear
                    .frame(width: 44, height: 1)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .task(id: playback.id) {
            let didAcquirePlayerLease = await installAndMonitorPlayer()
            if didAcquirePlayerLease {
                // This runs only after the monitoring routine has returned and
                // released its AVPlayerItem/asset references. The application
                // can now safely remove the protected plaintext export.
                onPlayerReleased()
            }
        }
        .onDisappear {
            detachPlayer()
        }
    }

    private func dismiss() {
        // Detach immediately, then ask the application to dismiss. The
        // coordinator still waits for the task-terminal release acknowledgement
        // before removing the protected plaintext file.
        detachPlayer()
        onDismiss()
    }

    private func installAndMonitorPlayer() async -> Bool {
        detachPlayer()
        guard !Task.isCancelled, onPlayerWillAttach() else { return false }
        guard !Task.isCancelled else { return true }

        await runAttachedPlayer()
        return true
    }

    private func runAttachedPlayer() async {
        let item = AVPlayerItem(asset: playback.makeRestrictedAsset())
        let candidate = AVPlayer(playerItem: item)
        VaultEncryptedVideoPlayerSecurityPolicy.configure(candidate)
        player = candidate

        // The task is tied to playback.id. Detaching here covers identity
        // changes, failure, and normal SwiftUI task cancellation. Lease
        // acknowledgement happens in the outer task only after this routine
        // and its failure monitor have fully unwound.
        defer { detachPlayer(candidate) }

        let monitor = VaultEncryptedVideoPlayerFailureMonitor(item: item)
        guard await monitor.waitForFailure(),
              !Task.isCancelled,
              player === candidate else {
            return
        }

        detachPlayer(candidate)
        onFailure?(.unplayableVideo)
    }

    private func detachPlayer(_ expectedPlayer: AVPlayer? = nil) {
        if let expectedPlayer {
            VaultEncryptedVideoPlayerLifecycle.release(expectedPlayer)
            guard player === expectedPlayer else { return }
            player = nil
            return
        }

        guard let activePlayer = player else { return }
        VaultEncryptedVideoPlayerLifecycle.release(activePlayer)
        player = nil
    }
}
