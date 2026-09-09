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
