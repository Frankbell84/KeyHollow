import AVFoundation
import AVKit
import CoreGraphics
import XCTest
@testable import KeyHollowEncryptedVideoAddOn

final class VaultEncryptedVideoHardeningTests: XCTestCase {
    @MainActor
    func testPlayerSecurityPolicyDisablesExternalAndPictureInPicturePlayback() {
        let player = AVPlayer()
        let controller = AVPlayerViewController()

        VaultEncryptedVideoPlayerSecurityPolicy.configure(player)
        VaultEncryptedVideoPlayerSecurityPolicy.configure(controller)

        XCTAssertFalse(player.allowsExternalPlayback)
        XCTAssertFalse(player.usesExternalPlaybackWhileExternalScreenIsActive)
        XCTAssertFalse(controller.allowsPictureInPicturePlayback)
        XCTAssertFalse(controller.canStartPictureInPictureAutomaticallyFromInline)
        XCTAssertFalse(controller.updatesNowPlayingInfoCenter)
        XCTAssertFalse(controller.allowsVideoFrameAnalysis)
    }

    @MainActor
    func testFailureMonitorSurfacesFailedStatusChannel() async {
        let monitor = VaultEncryptedVideoPlayerFailureMonitor(
            statusProvider: { .failed },
            playbackEndFailureWaiter: {
                await waitUntilCancelled()
            }
        )

        let didFail = await monitor.waitForFailure()
        XCTAssertTrue(didFail)
    }

    @MainActor
    func testFailureMonitorSurfacesFailedToEndNotificationChannel() async {
        let monitor = VaultEncryptedVideoPlayerFailureMonitor(
            statusProvider: { .readyToPlay },
            playbackEndFailureWaiter: { true }
        )

        let didFail = await monitor.waitForFailure()
        XCTAssertTrue(didFail)
    }

    @MainActor
    func testPlaybackSessionOwnsPlayerGraphBeyondAnchorDismantle() async throws {
        let fixture = try makePreparedPlayback()
        defer { removePreparedPlayback(fixture) }
        var releaseCount = 0
        let session = VaultEncryptedVideoPlaybackSession(
            waitForFailure: { _ in await waitUntilCancelled() }
        )

        XCTAssertTrue(
            session.activate(
                playback: fixture.playback,
                onPlayerReleased: { releaseCount += 1 }
            )
        )
        let player = try XCTUnwrap(session.activePlayer)
        let item = try XCTUnwrap(player.currentItem)
        let controller = session.retainedPlayerController
        var anchor: VaultEncryptedVideoPresentationAnchorViewController? =
            VaultEncryptedVideoPresentationAnchorViewController()
        session.presentationAnchorDidUpdate(try XCTUnwrap(anchor))

        XCTAssertTrue(controller.player === player)
        XCTAssertTrue(player.currentItem === item)
        XCTAssertTrue(session.attachedAnchorController === anchor)
        XCTAssertFalse(session.presentationAnchorIsReady)
        XCTAssertTrue(session.presentationIsPending)

        // The first anchor appearance is not a dismissal. With no attached
        // window UIKit cannot present yet, so the original explicit request
        // must remain pending instead of being mistaken for a completed modal.
        session.presentationAnchorDidAppear(try XCTUnwrap(anchor))
        XCTAssertTrue(session.presentationAnchorIsReady)
        XCTAssertTrue(session.presentationIsPending)

        // SwiftUI may dismantle its anchor while UIKit changes presentation.
        // The weak presenter disappears, but the stable session must retain the
        // exact controller/player/item graph and must not release its lease.
        anchor?.prepareForRepresentableDismantle()
        weak var weakAnchor = anchor
        anchor = nil

        XCTAssertNil(weakAnchor)
        XCTAssertNil(session.attachedAnchorController)
        XCTAssertTrue(session.retainedPlayerController === controller)
        XCTAssertTrue(controller.player === player)
        XCTAssertTrue(player.currentItem === item)
        XCTAssertEqual(releaseCount, 0)

        await session.stopAndWait()
        XCTAssertEqual(releaseCount, 1)
    }

    @MainActor
    func testPlaybackSessionAppliesSecurityPolicyToOwnedGraph() async throws {
        let fixture = try makePreparedPlayback()
        defer { removePreparedPlayback(fixture) }
        let session = VaultEncryptedVideoPlaybackSession(
            waitForFailure: { _ in await waitUntilCancelled() }
        )

        XCTAssertTrue(session.activate(playback: fixture.playback))
        let player = try XCTUnwrap(session.activePlayer)
        let controller = session.retainedPlayerController

        XCTAssertFalse(player.allowsExternalPlayback)
        XCTAssertFalse(player.usesExternalPlaybackWhileExternalScreenIsActive)
        XCTAssertFalse(controller.allowsPictureInPicturePlayback)
        XCTAssertFalse(controller.canStartPictureInPictureAutomaticallyFromInline)
        XCTAssertFalse(controller.updatesNowPlayingInfoCenter)
        XCTAssertFalse(controller.allowsVideoFrameAnalysis)

        await session.stopAndWait()
    }

    @MainActor
    func testModalDismissalReturnsToPosterWithoutReleasingPlayback() async throws {
        let fixture = try makePreparedPlayback()
        defer { removePreparedPlayback(fixture) }
        var releaseCount = 0
        let session = VaultEncryptedVideoPlaybackSession(
            waitForFailure: { _ in await waitUntilCancelled() }
        )

        XCTAssertTrue(
            session.activate(
                playback: fixture.playback,
                onPlayerReleased: { releaseCount += 1 }
            )
        )
        let player = try XCTUnwrap(session.activePlayer)
        let item = try XCTUnwrap(player.currentItem)
        let controller = session.retainedPlayerController

        // Exercise AVKit's actual direct-presentation dismissal callbacks.
        // A replay request during the transition must be rejected, not queued.
        session.playerViewControllerWillBeginDismissalTransition(controller)
        session.requestPresentation()
        XCTAssertFalse(session.presentationIsPending)
        session.playerViewControllerDidEndDismissalTransition(controller)

        XCTAssertEqual(releaseCount, 0)
        XCTAssertEqual(session.activePlaybackID, fixture.playback.id)
        XCTAssertTrue(session.canPresent)
        XCTAssertFalse(session.isPlayerPresented)
        XCTAssertTrue(session.activePlayer === player)
        XCTAssertTrue(player.currentItem === item)

        // Repeated explicit requests collapse into one pending presentation.
        session.requestPresentation()
        session.requestPresentation()
        XCTAssertTrue(session.presentationIsPending)

        await session.stopAndWait()
        XCTAssertEqual(releaseCount, 1)
    }

    @MainActor
    func testTerminalStopIsOrderedIdempotentAndReleasesLeaseOnce() async throws {
        let fixture = try makePreparedPlayback()
        defer { removePreparedPlayback(fixture) }
        var releaseCount = 0
        var callbackObservedDetachedGraph = false
        var events: [VaultEncryptedVideoSessionTeardownEvent] = []
        let session = VaultEncryptedVideoPlaybackSession(
            waitForFailure: { _ in await waitUntilCancelled() },
            teardownObserver: { events.append($0) }
        )

        XCTAssertTrue(
            session.activate(
                playback: fixture.playback,
                onPlayerReleased: {
                    releaseCount += 1
                    callbackObservedDetachedGraph =
                        session.retainedPlayerController.player == nil
                        && session.activePlayer == nil
                }
            )
        )
        let player = try XCTUnwrap(session.activePlayer)

        session.requestStop()
        session.requestStop()
        await session.stopAndWait()
        await session.stopAndWait()

        XCTAssertEqual(
            events,
            [
                .rejectedNewPresentations,
                .playerPaused,
                .monitorFinished,
                .modalDismissed,
                .playerDetached,
                .leaseReleased
            ]
        )
        XCTAssertEqual(releaseCount, 1)
        XCTAssertTrue(callbackObservedDetachedGraph)
        XCTAssertNil(player.currentItem)
        XCTAssertNil(session.retainedPlayerController.player)
        XCTAssertNil(session.activePlayer)
        XCTAssertNil(session.activePlaybackID)
        XCTAssertFalse(session.canPresent)
    }

    @MainActor
    func testPlaybackFailureUsesSameTerminalReleaseOrdering() async throws {
        let fixture = try makePreparedPlayback()
        defer { removePreparedPlayback(fixture) }
        var releaseCount = 0
        var failureCount = 0
        var failureWaiterReturned = false
        var monitorWasFinishedBeforeTeardown = false
        var events: [VaultEncryptedVideoSessionTeardownEvent] = []
        let session = VaultEncryptedVideoPlaybackSession(
            waitForFailure: { _ in
                defer { failureWaiterReturned = true }
                return true
            },
            teardownObserver: { event in
                if event == .monitorFinished {
                    monitorWasFinishedBeforeTeardown = failureWaiterReturned
                }
                events.append(event)
            }
        )

        XCTAssertTrue(
            session.activate(
                playback: fixture.playback,
                onPlayerReleased: { releaseCount += 1 },
                onFailure: { _ in failureCount += 1 }
            )
        )
        await waitForSessionToStop(session)

        XCTAssertEqual(failureCount, 1)
        XCTAssertEqual(releaseCount, 1)
        XCTAssertTrue(monitorWasFinishedBeforeTeardown)
        XCTAssertEqual(
            events,
            [
                .rejectedNewPresentations,
                .playerPaused,
                .monitorFinished,
                .modalDismissed,
                .playerDetached,
                .leaseReleased
            ]
        )
    }

    func testSourceDimensionPolicyAdmitsEightKAndRejectsExtremeFrames() {
        XCTAssertTrue(
            VaultEncryptedVideoPolicy.allowsSourceDimensions(
                CGSize(width: 7_680, height: 4_320)
            )
        )
        XCTAssertTrue(
            VaultEncryptedVideoPolicy.allowsSourceDimensions(
                CGSize(width: -4_320, height: 7_680)
            )
        )
        XCTAssertFalse(
            VaultEncryptedVideoPolicy.allowsSourceDimensions(
                CGSize(width: 8_193, height: 1)
            )
        )
        XCTAssertFalse(
            VaultEncryptedVideoPolicy.allowsSourceDimensions(
                CGSize(width: 8_192, height: 8_192)
            )
        )
        XCTAssertFalse(
            VaultEncryptedVideoPolicy.allowsSourceDimensions(.zero)
        )
        XCTAssertFalse(
            VaultEncryptedVideoPolicy.allowsSourceDimensions(
                CGSize(width: CGFloat.infinity, height: 1)
            )
        )
        XCTAssertFalse(
            VaultEncryptedVideoPolicy.allowsSourceDimensions(
                CGSize(width: CGFloat.nan, height: 1)
            )
        )

        let scaledDownPresentation = CGSize(
            width: 16_384,
            height: 16_384
        ).applying(CGAffineTransform(scaleX: 0.01, y: 0.01))
        XCTAssertTrue(
            VaultEncryptedVideoPolicy.allowsSourceDimensions(
                scaledDownPresentation
            )
        )
        XCTAssertFalse(
            VaultEncryptedVideoPolicy.allowsSourceDimensions(
                CGSize(width: 16_384, height: 16_384)
            )
        )
    }
}

private func waitUntilCancelled() async -> Bool {
    while !Task.isCancelled {
        await Task.yield()
    }
    return false
}

private struct PreparedPlaybackFixture {
    let playback: VaultPreparedVideoPlayback
    let fileURL: URL
}

private func makePreparedPlayback() throws -> PreparedPlaybackFixture {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("PlaybackSession-\(UUID().uuidString)")
        .appendingPathExtension("mov")
    try Data([0x00]).write(to: fileURL, options: .atomic)
    let playback = try VaultPreparedVideoPlayback(
        id: UUID(),
        descriptor: VaultEncryptedVideoDescriptor(
            displayName: "Portrait.mov",
            contentTypeIdentifier: "com.apple.quicktime-movie",
            originalByteCount: 1
        ),
        fileURL: fileURL
    )
    return PreparedPlaybackFixture(playback: playback, fileURL: fileURL)
}

private func removePreparedPlayback(_ fixture: PreparedPlaybackFixture) {
    try? FileManager.default.removeItem(at: fixture.fileURL)
}

@MainActor
private func waitForSessionToStop(
    _ session: VaultEncryptedVideoPlaybackSession
) async {
    for _ in 0..<1_000 where session.activePlaybackID != nil {
        await Task.yield()
    }
    XCTAssertNil(session.activePlaybackID)
}
