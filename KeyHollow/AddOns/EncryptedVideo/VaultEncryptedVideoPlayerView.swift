import AVFoundation
import AVKit
import SwiftUI

/// Native, module-owned playback for one application-prepared local video.
/// The application retains ownership of the temporary file and removes it
/// after this surface closes or the unlocked vault session ends.
@MainActor
public struct VaultEncryptedVideoPlayerView: View {
    private let playback: VaultPreparedVideoPlayback
    private let onDismiss: () -> Void

    @State private var player: AVPlayer?

    public init(
        playback: VaultPreparedVideoPlayback,
        onDismiss: @escaping () -> Void
    ) {
        self.playback = playback
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .accessibilityLabel(playback.descriptor.displayName)
            } else {
                ProgressView()
                    .tint(.white)
                    .accessibilityLabel("Preparing encrypted video")
            }
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Button("Done", action: onDismiss)

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
            guard player == nil else { return }
            player = AVPlayer(url: playback.fileURL)
        }
        .onDisappear(perform: releasePlayer)
    }

    private func releasePlayer() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }
}
